/*
 * ios-sunstone milestone 1: one RAM boot (fastboot boot, nothing flashed)
 * that answers the questions which decide whether ios-sweet/ios-topaz can
 * be brought up on sunstone (Redmi Note 12 5G, SM4375 "blair"):
 *   - does ABL run a boot image v3 shim and hand over EL1 + DTB in x0
 *   - is the splash framebuffer at 0x85200000, a8r8g8b8, stride 1080*4
 *   - does a payload appended behind _end survive (ios-topaz packing),
 *     and does ABL pass our own ramdisk at all (marker search)
 *   - CPU ids and the 16K granule on every core (A55 x6 + A78 x2)
 *   - PSCI/SMCCC, CPU_ON for the 7 secondaries
 *   - GICv3 Group 1 IRQ from the virtual timer (INTID 19) and SGIs
 *   - EL1 stage-1 MMU with 16K pages
 * Then it keeps the results on screen and resets into fastboot.
 * Any unexpected exception paints a blue panic screen.
 *
 * Helpers and the GIC/IRQ tests follow ios-sweet's shim.c (milestones 2-3).
 */
#include <stdint.h>
#include "console.h"
#include "fdt.h"
#include "loader.h"
#include "mmu.h"

#define IMEM_RESTART_REASON	0x0c12565cUL	/* qcom,msm-imem@c125000 restart_reason@65c */
#define RESTART_BOOTLOADER	0x77665500U
#define PSHOLD			0x0440b000UL	/* restart@440b000 qcom,pshold */

#define GICD_BASE		0x0f200000UL
#define GICR_BASE		0x0f240000UL
#define GICR_SIZE		0x100000UL
#define GICR_PE_SIZE		0x20000UL
#define GICR_TYPER		0x08
#define GICR_WAKER		0x14
#define GICR_SGI		0x10000
#define GICR_IGROUPR0		(GICR_SGI + 0x080)
#define GICR_ISENABLER0		(GICR_SGI + 0x100)
#define GICR_ICENABLER0		(GICR_SGI + 0x180)
#define GICR_IPRIORITYR		(GICR_SGI + 0x400)
#define GICR_ISPENDR0		(GICR_SGI + 0x200)
#define GICR_ISACTIVER0		(GICR_SGI + 0x300)
#define VTIMER_INTID		19	/* DT: <GIC_PPI 3 ...> */
#define PTIMER_INTID		18	/* DT: <GIC_PPI 2 ...> */
#define SGI_INTID		1

/*
 * SPMI PMIC arbiter v5 (DT qcom,spmi@1c40000, ee 0). ABL takes the
 * "reboot to fastboot" request from PM6125 PON SOFT_RB_SPARE (SID 0,
 * 0x88F, bits 7:1 = reason), as Linux msm-poweroff does through
 * qpnp_pon_set_restart_reason(); the IMEM cookie alone is ignored.
 */
#define SPMI_CORE		0x01c40000UL
#define SPMI_CORE_SIZE		0x1100UL
#define SPMI_CHNLS		0x01e00000UL	/* read/write channels, 0x10000 per APID */
#define SPMI_OBSRVR		0x03e00000UL	/* observer channels, 0x80 per APID (EE 0) */
#define SPMI_CNFG		0x01c0a000UL
#define SPMI_CMD		0x00
#define SPMI_STATUS		0x08
#define SPMI_WDATA0		0x10
#define SPMI_RDATA0		0x18
#define SPMI_OP_EXT_WRITEL	0
#define SPMI_OP_EXT_READL	1
#define SPMI_NO_APID		0xffff
#define PON_PPID		0x008		/* SID 0, peripheral 0x08 (PM6125 PON @0x800) */
#define PON_TYPE		0x804		/* 0x01 = PON peripheral */
#define PON_SUBTYPE		0x805
#define PON_SOFT_RB_SPARE	0x88f
#define PON_REASON_BOOTLOADER	2

#define PSCI_VERSION		0x84000000UL
#define PSCI_CPU_OFF		0x84000002UL
#define PSCI_CPU_ON		0xc4000003UL
#define PSCI_SYSTEM_RESET	0x84000009UL
#define PSCI_FEATURES		0x8400000aUL
#define PSCI_SYSTEM_SUSPEND	0xc400000eUL
#define PSCI_SYSTEM_RESET2	0xc4000012UL
#define SMCCC_VERSION		0x80000000UL

#define NR_CPUS			8	/* DT cpu@0 .. cpu@700: MPIDR Aff1 = index */

/* build.sh: 4K-aligned blob behind _end, and a file in our ramdisk */
#define EMBED_MAGIC		"SUNEMBED"
#define RD_MARKER		"SUNSTONE-RD-MARK-7f3a"

#define rsr(r) ({ uint64_t _v; __asm__ volatile("mrs %0, " r : "=r"(_v)); _v; })
#define wsr(r, v) __asm__ volatile("msr " r ", %0" : : "r"((uint64_t)(v)))
#define isb() __asm__ volatile("isb" ::: "memory")

static inline uint32_t rd32(uintptr_t a) { return *(volatile uint32_t *)a; }
static inline uint64_t rd64(uintptr_t a) { return *(volatile uint64_t *)a; }
static inline void wr32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static inline void wr8(uintptr_t a, uint8_t v) { *(volatile uint8_t *)a = v; }

extern char _head[], _end[], secondary_entry[];

static const char *stage;	/* set at runtime: no absolute pointers in data */
static volatile uint64_t sec_mpidr[NR_CPUS], sec_midr[NR_CPUS], sec_mmfr0[NR_CPUS];
static volatile uint32_t irq_count, irq_other, irq_last;
static volatile int irq_src;

/* ICC_SGI1R_EL1 value targeting the calling core only. */
static uint64_t sgi_self(unsigned id)
{
	uint64_t m = rsr("mpidr_el1");
	return ((m >> 16) & 0xff) << 32 |	/* Aff2 */
	       ((m >> 8) & 0xff) << 16 |	/* Aff1 */
	       (uint64_t)id << 24 |
	       (1U << (m & 0xf));		/* target list: Aff0 */
}

static uint64_t smc(uint64_t fn, uint64_t a1, uint64_t a2, uint64_t a3)
{
	register uint64_t x0 __asm__("x0") = fn;
	register uint64_t x1 __asm__("x1") = a1;
	register uint64_t x2 __asm__("x2") = a2;
	register uint64_t x3 __asm__("x3") = a3;
	__asm__ volatile("smc #0"
			 : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3)
			 :
			 : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11",
			   "x12", "x13", "x14", "x15", "x16", "x17", "memory");
	return x0;
}

static uint64_t now(void)
{
	isb();
	return rsr("cntpct_el0");
}

static void delay_ms(unsigned ms)
{
	uint64_t end = now() + rsr("cntfrq_el0") / 1000 * ms;
	while (now() < end)
		;
}

/* console.c page breaks hold the screen this long (ios-sunstone had it in gpu.c) */
void con_hold_ms(unsigned ms)
{
	delay_ms(ms);
}

static uint32_t to_us(uint64_t ticks)
{
	return ticks * 10 / 192;	/* 19.2 MHz */
}

/* ---- SPMI (PMIC arbiter v5) ---- */

static uint32_t spmi_last_status;

/* v5 can map one PPID more than once; prefer the apps-owned (EE 0) entry. */
static uint16_t spmi_find_apid(uint16_t ppid, uint32_t *owner)
{
	uint16_t found = SPMI_NO_APID;

	for (uint32_t i = 0; 0x900 + 4 * i < SPMI_CORE_SIZE; i++) {
		uint32_t map = rd32(SPMI_CORE + 0x900 + 4 * i);
		if (map == 0 || ((map >> 8) & 0xfff) != ppid)
			continue;
		uint32_t own = rd32(SPMI_CNFG + 0x700 + 4 * i) & 7;
		if (found == SPMI_NO_APID || own == 0) {
			found = i;
			*owner = own;
		}
	}
	return found;
}

static int spmi_wait(uintptr_t chan)
{
	for (int i = 0; i < 1000; i++) {
		spmi_last_status = rd32(chan + SPMI_STATUS);
		if (spmi_last_status & 1)	/* DONE; bits 1-3 = failure/denied/dropped */
			return (spmi_last_status & 0xe) ? -1 : 0;
		delay_ms(1);
	}
	return -2;
}

static int spmi_read(uint16_t apid, uint16_t addr, uint8_t *out)
{
	uintptr_t chan = SPMI_OBSRVR + 0x80UL * apid;

	__asm__ volatile("dsb sy" ::: "memory");
	wr32(chan + SPMI_CMD, SPMI_OP_EXT_READL << 27 | (addr & 0xff) << 4);
	__asm__ volatile("dsb sy" ::: "memory");
	int rc = spmi_wait(chan);
	if (!rc)
		*out = rd32(chan + SPMI_RDATA0) & 0xff;
	return rc;
}

static int spmi_write(uint16_t apid, uint16_t addr, uint8_t val)
{
	uintptr_t chan = SPMI_CHNLS + 0x10000UL * apid;

	wr32(chan + SPMI_WDATA0, val);
	__asm__ volatile("dsb sy" ::: "memory");
	wr32(chan + SPMI_CMD, SPMI_OP_EXT_WRITEL << 27 | (addr & 0xff) << 4);
	__asm__ volatile("dsb sy" ::: "memory");
	return spmi_wait(chan);
}

/*
 * Ask ABL for fastboot on the next boot. Writes only PON SOFT_RB_SPARE
 * bits 7:1 (1:2 on gen1 PONs), and only after the peripheral reads back
 * as a PON. Returns 1 if the reason was written.
 */
static int pon_reason_bootloader(void)
{
	uint32_t owner = 7;
	uint8_t type = 0, sub = 0, old = 0, now = 0;

	stage = "spmi";
	con_hex2("SPMI", "ver=", rd32(SPMI_CORE), 0, 0);
	uint16_t apid = spmi_find_apid(PON_PPID, &owner);
	con_hex2(" pon", "apid=", apid, "owner=", owner);
	if (apid == SPMI_NO_APID)
		return 0;
	int rt = spmi_read(apid, PON_TYPE, &type);
	int rs = spmi_read(apid, PON_SUBTYPE, &sub);
	con_hex2(" type", "", rt ? 0xee000000 | spmi_last_status : type, "sub=", rs ? 0xee : sub);
	int ro = spmi_read(apid, PON_SOFT_RB_SPARE, &old);
	con_hex2(" spare", "old=", ro ? 0xee000000 | spmi_last_status : old, 0, 0);
	if (rt || rs || ro || type != 0x01 || owner != 0) {
		con_str(" skip", "not an apps-owned PON");
		return 0;
	}
	/* gen2/gen3 PON (subtype >= 4): reason in bits 7:1, gen1: bits 7:2 */
	uint8_t val = sub >= 4 ? (old & 0x01) | PON_REASON_BOOTLOADER << 1 :
				 (old & 0x03) | PON_REASON_BOOTLOADER << 2;
	int rw = spmi_write(apid, PON_SOFT_RB_SPARE, val);
	int rb = spmi_read(apid, PON_SOFT_RB_SPARE, &now);
	con_hex2(" write", "val=", val, "st=", rw ? 0xee000000 | spmi_last_status : 0);
	con_hex2(" readbk", "", rb ? 0xee : now, 0, 0);
	return !rw && !rb && now == val;
}

static void __attribute__((noreturn)) reset(unsigned after_s)
{
	static int pon_tried;	/* a fault inside the SPMI code must not recurse */

	con_skip();
	if (!pon_tried) {
		pon_tried = 1;
		con_str("PON", pon_reason_bootloader() ? "fastboot reason set" : "reason NOT set");
	}
	con_str("RESET", after_s >= 120 ? "to fastboot in 2 min" : "to fastboot in 1 min");
	delay_ms(after_s * 1000);
	wr32(IMEM_RESTART_REASON, RESTART_BOOTLOADER);
	__asm__ volatile("dsb sy" ::: "memory");
	smc(PSCI_SYSTEM_RESET, 0, 0, 0);
	wr32(PSHOLD, 0);
	for (;;)
		__asm__ volatile("wfe");
}

/* ---- exceptions ---- */

static void irq_handler(void)
{
	uint64_t iar = rsr("icc_iar1_el1");
	uint32_t id = iar & 0xffffff;

	if (id >= 1020 && id <= 1023)
		return;	/* spurious */
	irq_last = id;
	if (id == (uint32_t)irq_src)
		irq_count++;
	else
		irq_other++;
	if (id == VTIMER_INTID)
		wsr("cntv_tval_el0", rsr("cntfrq_el0") / 100);	/* 10 ms */
	else if (id == PTIMER_INTID)
		wsr("cntp_tval_el0", rsr("cntfrq_el0") / 100);
	wsr("icc_eoir1_el1", iar);
	isb();
}

void exc_handler(uint64_t slot, uint64_t *regs)
{
	if (slot == 5) {	/* IRQ from current EL, SPx */
		irq_handler();
		return;
	}
	con_clear(BLUE);
	switch (slot & 3) {
	case 0: con_str("PANIC", "SYNC"); break;
	case 1: con_str("PANIC", "IRQ"); break;
	case 2: con_str("PANIC", "FIQ"); break;
	default: con_str("PANIC", "SERROR"); break;
	}
	con_hex2("SLOT", "n=", slot, "cpu=", rsr("mpidr_el1"));
	con_str("STAGE", stage);
	con_hex("ESR", rsr("esr_el1"));
	con_hex("ELR", rsr("elr_el1"));
	con_hex("FAR", rsr("far_el1"));
	con_hex("SPSR", rsr("spsr_el1"));
	con_hex("X0", regs[0]);
	con_hex("X1", regs[1]);
	con_hex("X30", regs[29]);	/* stashed lr is just above the frame */
	reset(60);
}

/* ---- CPU identity ---- */

/* TGran16 is ID_AA64MMFR0_EL1[23:20]: 0 = no 16K pages (fatal for iOS XNU) */
static uint32_t tg16(uint64_t mmfr0)
{
	return (mmfr0 >> 20) & 0xf;
}

static void show_cpu(void)
{
	stage = "cpu id";
	uint64_t mmfr0 = rsr("id_aa64mmfr0_el1");
	con_hex2("EL", "cur=", rsr("CurrentEL") >> 2, "sctlr=", rsr("sctlr_el1"));
	con_hex2("MIDR", "", rsr("midr_el1"), "mpidr=", rsr("mpidr_el1"));
	con_hex2("MMFR0", "lo=", mmfr0, "tg16=", tg16(mmfr0));
	con_hex2("ISAR0", "lo=", rsr("id_aa64isar0_el1"), "atom=", (rsr("id_aa64isar0_el1") >> 20) & 0xf);
	con_hex2("ISAR1", "lo=", rsr("id_aa64isar1_el1"), "pac=", (rsr("id_aa64isar1_el1") >> 4) & 0xff);
	con_hex2("IMAGE", "at=", (uintptr_t)_head, "end=", (uintptr_t)_end);
}

/* ---- boot image packing: what did ABL pass? ---- */

static int match(uintptr_t a, const char *s)
{
	for (; *s; s++, a++)
		if (*(volatile const char *)a != *s)
			return 0;
	return 1;
}

static void show_boot(uint64_t dtb)
{
	stage = "dtb";
	con_hex2("DTB", "at=", dtb, "magic=", dtb ? __builtin_bswap32(rd32(dtb)) : 0);
	if (dtb)
		con_hex2(" size", "", __builtin_bswap32(rd32(dtb + 4)), 0, 0);

	/* ios-topaz packing: the payload rides behind the shim in the Image */
	stage = "embed";
	uintptr_t emb = ((uintptr_t)_end + 0xfff) & ~0xfffUL;
	con_hex2("EMBED", "at=", emb, "ok=", match(emb, EMBED_MAGIC));

	/* Does ABL pass our own boot ramdisk (topaz ABL drops it)? */
	stage = "initrd";
	uint64_t rd_lo, rd_hi;
	if (!fdt_chosen_u64(dtb, "linux,initrd-start", &rd_lo) ||
	    !fdt_chosen_u64(dtb, "linux,initrd-end", &rd_hi)) {
		con_str("INITRD", "none in /chosen");
		return;
	}
	con_hex2("INITRD", "lo=", rd_lo, "hi=", rd_hi);
	stage = "rd marker";
	uintptr_t hit = 0;
	for (uintptr_t a = rd_lo; a + sizeof(RD_MARKER) <= rd_hi; a++)
		if (*(volatile const char *)a == 'S' && match(a, RD_MARKER)) {
			hit = a;
			break;
		}
	con_hex2(" mark", "at=", hit, "off=", hit ? hit - rd_lo : 0);
}

/* ---- PSCI + SMP ---- */

void secondary_main(uint64_t idx)
{
	sec_midr[idx] = rsr("midr_el1");
	sec_mmfr0[idx] = rsr("id_aa64mmfr0_el1");
	sec_mpidr[idx] = rsr("mpidr_el1") | (1ULL << 63);
	__asm__ volatile("dsb sy" ::: "memory");
	smc(PSCI_CPU_OFF, 0, 0, 0);
}

static void show_psci(void)
{
	stage = "psci";
	con_hex2("PSCI", "ver=", smc(PSCI_VERSION, 0, 0, 0), "smccc=", smc(SMCCC_VERSION, 0, 0, 0));
	con_hex2(" feat", "on=", smc(PSCI_FEATURES, PSCI_CPU_ON, 0, 0),
		 "rst2=", smc(PSCI_FEATURES, PSCI_SYSTEM_RESET2, 0, 0));
}

static void test_smp(void)
{
	stage = "smp";
	uint64_t self = rsr("mpidr_el1") & 0xffffff;
	int64_t ret[NR_CPUS];

	for (int i = 0; i < NR_CPUS; i++)
		ret[i] = ((uint64_t)i << 8) == self ? 0 :
			 (int64_t)smc(PSCI_CPU_ON, (uint64_t)i << 8, (uintptr_t)secondary_entry, i);
	delay_ms(500);
	for (int i = 0; i < NR_CPUS; i++) {
		char label[] = "CPU0";
		label[3] = '0' + i;
		if (((uint64_t)i << 8) == self) {
			con_str(label, "boot cpu");
			continue;
		}
		if (!sec_mpidr[i]) {
			con_hex2(label, "ret=", (uint32_t)ret[i], "mpidr=", 0xdead0000);
			continue;
		}
		/* MIDR part number [15:4]: d05 = Cortex-A55, d41 = Cortex-A78 */
		con_hex2(label, "part=", (sec_midr[i] >> 4) & 0xfff, "tg16=", tg16(sec_mmfr0[i]));
	}
}

/* ---- GIC + timer ---- */

static uintptr_t find_gicr(void)
{
	uint64_t aff = rsr("mpidr_el1");
	uint32_t want = (aff & 0xffffff) | ((aff >> 8) & 0xff000000);

	for (uintptr_t off = 0; off < GICR_SIZE; off += GICR_PE_SIZE) {
		uint64_t typer = rd64(GICR_BASE + off + GICR_TYPER);
		if ((uint32_t)(typer >> 32) == want)
			return GICR_BASE + off;
		if (typer & (1 << 4))	/* Last */
			break;
	}
	return 0;
}

static void gicd_wait_rwp(void)
{
	for (int i = 0; i < 1000000 && (rd32(GICD_BASE) & (1U << 31)); i++)
		;
}

/* Run one interrupt source for ~300 ms and report what the GIC saw. */
static void irq_window(const char *label, uintptr_t r, int src)
{
	uint64_t f = rsr("cntfrq_el0");

	irq_count = irq_other = 0;
	irq_last = 0x3ff;
	irq_src = src;
	if (src == VTIMER_INTID) {
		wsr("cntv_tval_el0", f / 100);
		wsr("cntv_ctl_el0", 1);
	}
	isb();
	uint64_t t = now() + f / 50;
	while (now() < t)
		;
	if (src == SGI_INTID)
		wsr("icc_sgi1r_el1", sgi_self(SGI_INTID));
	isb();
	uint32_t pend = rd32(r + GICR_ISPENDR0), act = rd32(r + GICR_ISACTIVER0);

	__asm__ volatile("msr daifclr, #2" ::: "memory");
	t = now() + f * 3 / 10;
	/* SGI: one already sent above, send 9 more 10 ms apart -> expect 10 */
	uint64_t next = now() + f / 100;
	for (int sent = 1; now() < t;)
		if (src == SGI_INTID && sent < 10 && now() >= next) {
			wsr("icc_sgi1r_el1", sgi_self(SGI_INTID));
			isb();
			sent++;
			next += f / 100;
		}
	__asm__ volatile("msr daifset, #2" ::: "memory");
	wsr("cntv_ctl_el0", 0);
	isb();

	/* vtimer: expect ~30 in 300 ms; SGI: expect 10 */
	con_hex2(label, "irqs=", irq_count, "other=", irq_other);
	con_hex2(" pre", "pend=", pend, "act=", act);
}

static void test_gic(void)
{
	stage = "gic sre";
	uint64_t sre = rsr("icc_sre_el1");
	if (!(sre & 1)) {
		wsr("icc_sre_el1", sre | 1);
		isb();
	}
	if (!(rsr("icc_sre_el1") & 1)) {
		con_str("GIC", "no sysreg iface, skip");
		return;
	}

	stage = "gic dist";
	uint32_t dctlr = rd32(GICD_BASE);
	/* Non-secure view (DS=0): bit0 EnableGrp1, bit1 EnableGrp1A, bit4 ARE_NS; Linux writes 0x13 */
	wr32(GICD_BASE, dctlr | 0x13);
	gicd_wait_rwp();
	con_hex2("GICD", "was=", dctlr, "now=", rd32(GICD_BASE));
	con_hex2(" typer", "", rd32(GICD_BASE + 4), 0, 0);

	stage = "gic redist";
	uintptr_t r = find_gicr();
	if (!r) {
		con_str("GICR", "not found");
		return;
	}
	uint32_t waker = rd32(r + GICR_WAKER);
	if (waker & 2) {
		wr32(r + GICR_WAKER, waker & ~2U);
		for (int i = 0; i < 100000 && (rd32(r + GICR_WAKER) & 4); i++)
			;
	}
	con_hex2("GICR", "base=", r, "waker=", rd32(r + GICR_WAKER));

	stage = "gic config";
	wr32(r + GICR_IGROUPR0, 0xffffffff);	/* NS view: secure bits are WI */
	for (int id = 0; id < 32; id++)
		wr8(r + GICR_IPRIORITYR + id, 0xa0);
	wr32(r + GICR_ISENABLER0, (1U << VTIMER_INTID) | (1U << SGI_INTID));

	uint64_t ctlr = rsr("icc_ctlr_el1");
	wsr("icc_ctlr_el1", ctlr & ~2ULL);	/* EOImode 0: EOIR also deactivates */
	wsr("icc_pmr_el1", 0xf0);
	wsr("icc_bpr1_el1", 0);
	wsr("icc_igrpen1_el1", 1);
	isb();

	stage = "gic vtimer";
	irq_window("VTIMER", r, VTIMER_INTID);
	stage = "gic sgi";
	irq_window("SGI1", r, SGI_INTID);
	wr32(r + GICR_ICENABLER0, 0xffffffff);
	isb();
}


/* ---- MMU (16K granule) ---- */

static uint64_t scratch[8192];	/* 64KB, lives in our (later cacheable) image */

static uint64_t ticks_mem(void)
{
	uint64_t t = now();
	for (int pass = 0; pass < 16; pass++)
		for (int i = 0; i < 8192; i++)
			scratch[i] = scratch[i] * 3 + i;
	return now() - t;
}

/* Fill a 200-line band at the bottom of the screen (does not erase the text). */
static uint64_t ticks_band(uint32_t c)
{
	uint64_t t = now();
	for (int y = FB_H - 200; y < FB_H; y++) {
		volatile uint32_t *line = con_fb + y * (FB_STRIDE / 4);
		for (int x = 0; x < FB_W; x++)
			line[x] = c;
	}
	return now() - t;
}

static void test_mmu(void)
{
	struct mmu_info mi;

	stage = "mmu off";
	uint64_t band_off = ticks_band(GREEN), mem_off = ticks_mem();
	stage = "mmu enable";
	int rc = mmu_enable(&mi);
	stage = "mmu on";
	uint64_t band_on = rc ? 0 : ticks_band(YELLOW), mem_on = rc ? 0 : ticks_mem();

	con_hex2("MMU", "rc=", rc, "l3=", mi.n_l3);
	con_hex2(" tcr", "", rsr("tcr_el1"), "sctlr=", rsr("sctlr_el1"));
	con_hex2(" par", "img=", mmu_probe((uintptr_t)_head), "fb=", mmu_probe(FB_PHYS + 0x1000));
	con_hex2("BAND us", "off=", to_us(band_off), "on=", to_us(band_on));
	con_hex2("MEM us", "off=", to_us(mem_off), "on=", to_us(mem_on));
}

/* ---- main ---- */

/*
 * CPU frequency: sm6375 EPSS (qcom,cpufreq-epss; Linux qcom-cpufreq-hw.c
 * epss_soc_data). Domain 0 at 0xfd91000 = six A55, domain 1 at 0xfd92000 =
 * two A78. LUT at +0x100 (4-byte rows: src[31:30], cores[18:16], lval[7:0],
 * MHz = 19.2 * lval when src != 0), PERF_STATE (vote) at +0x320 (per core
 * +4*n when DCVS_CTRL bit 0), current L-val in DOMAIN_STATE +0x20. Nothing
 * in xnu scales the CPUs yet, so vote the top non-boost entry once, as
 * topaz 0094 does; the EPSS/LMh hardware still throttles on its own.
 */
static uint32_t mmio_rd(uintptr_t a)
{
	uint32_t v;
	__asm__ volatile("ldr %w0, [%1]" : "=r"(v) : "r"(a) : "memory");
	return v;
}

static void mmio_wr(uintptr_t a, uint32_t v)
{
	__asm__ volatile("str %w0, [%1]" : : "rZ"(v), "r"(a) : "memory");
}

static char *put_dec(char *p, uint32_t v)
{
	char t[10];
	int n = 0;
	do {
		t[n++] = (char)('0' + v % 10);
		v /= 10;
	} while (v);
	while (n)
		*p++ = t[--n];
	return p;
}

static uint32_t epss_mhz(uint32_t lut)
{
	return ((lut >> 30) & 3) ? (lut & 0xff) * 192 / 10 : 300;
}

static void cpufreq_domain(uintptr_t b, const char *name, unsigned ncores)
{
	char line[48], *p = line;
	uint32_t best = 0, best_mhz = 0, prev = 0, n = 0;

	for (uint32_t i = 0; i < 40; i++) {
		uint32_t v = mmio_rd(b + 0x100 + 4 * i), mhz = epss_mhz(v);
		if (i > 0 && mhz == prev)
			break;                          /* the table repeats its last row */
		prev = mhz;
		n++;
		if (((v >> 16) & 7) != 1 && mhz > best_mhz) { /* cores == 1: boost row */
			best_mhz = mhz;
			best = i;
		}
		if (p - line > 38) {
			*p = 0;
			con_str(" lut", line);
			p = line;
		}
		p = put_dec(p, mhz);
		*p++ = ' ';
	}
	*p = 0;
	con_str(" lut", line);
	uint32_t dcvs = mmio_rd(b + 0xb0), old = mmio_rd(b + 0x320);
	uint32_t before = (mmio_rd(b + 0x20) & 0xff) * 192 / 10;
	con_hex2(name, "en=", mmio_rd(b), "dcvs=", dcvs);
	con_hex2(" vote", "old=", old, "MHz now=", before);
	mmio_wr(b + 0x320, best);
	if (dcvs & 1)
		for (unsigned c = 1; c < ncores; c++)
			mmio_wr(b + 0x320 + 4 * c, best);
	delay_ms(20);
	con_hex2(" vote", "new=", best, "MHz now=", (mmio_rd(b + 0x20) & 0xff) * 192 / 10);
	(void)n;
}

static void cpufreq_max(void)
{
	con_clear(DKGREEN);
	con_str("CPUFREQ", "EPSS, top non-boost vote");
	cpufreq_domain(0x0fd91000, " silver", 6);
	con_skip();
	cpufreq_domain(0x0fd92000, " gold", 2);
	delay_ms(10000);
	con_clear(RED);
}

void shim_main(uint64_t dtb)
{
	stage = "clear";
	con_clear(RED);
	con_str("SHIM", "sunstone-linux");
	con_skip();
	show_cpu();
	con_skip();

	/*
	 * A Linux payload behind _end (build.sh payload.bin): boot it. With
	 * SHIM_PON_FASTBOOT (PON_FASTBOOT=1 build.sh) set the PMIC reboot reason
	 * first, so that whatever resets the phone later (a panic, a watchdog, a
	 * long power press, `reboot`) lands in fastboot and not in another boot of
	 * this slot; without it (the default) such a reset boots Linux again.
	 */
	uintptr_t emb = ((uintptr_t)_end + 0xfff) & ~0xfffUL;
	if (match(emb, "SWEETLNX")) {
#if SHIM_PON_FASTBOOT
		con_str("PON", pon_reason_bootloader() ? "fastboot reason set" : "reason NOT set");
#else
		con_str("PON", "left alone: a reset boots Linux again");
#endif
		con_skip();
		stage = "cpufreq";
		cpufreq_max();
		con_skip();
		stage = "loader";
		const char *why = linux_boot(emb);
		con_str("LOADER", why);
		reset(60);
	}
	show_boot(dtb);
	con_skip();
#ifndef QEMU_SMOKE	/* QEMU virt: no EL3 for smc, GIC elsewhere */
	show_psci();
	test_smp();
	con_skip();
	test_gic();
	con_skip();
#endif
	test_mmu();

	stage = "done";
	con_skip();
	con_str("DONE", "page 2 in 20 s");
#ifdef QEMU_SMOKE
	for (;;)
		__asm__ volatile("wfe");
#endif
	delay_ms(20000);

	/* Page 2: SPMI + reboot reason (reset() does the PMIC write) */
	con_clear(DKGREEN);
	con_str("SHIM", "ios-sunstone milestone 1b");
	reset(60);
}
