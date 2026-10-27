// SPDX-License-Identifier: GPL-2.0
/*
 * Debug aid: the RPM's per-master sleep statistics, read live from RPM message RAM at
 * /sys/kernel/debug/rpm-master-peek, without a DT node. Layout as downstream's
 * qcom,rpm-master-stats@45f0150 on SM4375 (version 2, a block every 0x1000 for APSS, MPSS, ADSP,
 * CDSP, TZ) and the struct of mainline's rpm_master_stats.c. Only read, never written, and only
 * with 32-bit reads: memcpy_fromio's 64-bit reads of this RAM reset the SoC (2026-10-27).
 *   insmod rpm-master-peek.ko [phys=0x45f0150 stride=0x1000 count=5]
 */
#include <linux/debugfs.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/seq_file.h>

static unsigned long phys = 0x45f0150;
module_param(phys, ulong, 0444);
static unsigned long stride = 0x1000;
module_param(stride, ulong, 0444);
static unsigned int count = 1;
module_param(count, uint, 0444);

static const char *const names[] = { "APSS", "MPSS", "ADSP", "CDSP", "TZ" };

struct rpm_master_stats {
	u32 active_cores;
	u32 num_shutdowns;
	u64 shutdown_req;
	u64 wakeup_idx;
	u64 bringup_req;
	u64 bringup_ack;
	u32 wakeup_reason;
	u32 last_sleep_trans_dur;
	u32 last_wake_trans_dur;
	u32 xo_count;
	u64 xo_last_enter;
	u64 last_exit;
	u64 xo_total_dur;
} __packed;

static void __iomem *base[ARRAY_SIZE(names)];

static void read32(void *dst, const void __iomem *src, size_t len)
{
	u32 *d = dst;
	size_t i;

	for (i = 0; i < len / 4; i++)
		d[i] = readl(src + 4 * i);
}
static struct dentry *file;

static int peek_show(struct seq_file *s, void *unused)
{
	struct rpm_master_stats st;
	int i;

	for (i = 0; i < count; i++) {
		read32(&st, base[i], sizeof(st));
		seq_printf(s, "%-4s active_cores 0x%x shutdowns %u shutdown_req 0x%llx wakeup_idx 0x%llx "
			   "bringup_req 0x%llx bringup_ack 0x%llx wakeup_reason %u xo_count %u "
			   "xo_last_enter 0x%llx last_exit 0x%llx xo_total_dur 0x%llx\n",
			   names[i], st.active_cores, st.num_shutdowns, st.shutdown_req, st.wakeup_idx,
			   st.bringup_req, st.bringup_ack, st.wakeup_reason, st.xo_count,
			   st.xo_last_enter, st.last_exit, st.xo_total_dur);
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(peek);

static int __init peek_init(void)
{
	int i;

	if (!count || count > ARRAY_SIZE(names))
		return -EINVAL;
	for (i = 0; i < count; i++) {
		base[i] = ioremap(phys + i * stride, sizeof(struct rpm_master_stats));
		if (!base[i])
			goto unmap;
	}
	file = debugfs_create_file("rpm-master-peek", 0400, NULL, NULL, &peek_fops);
	return 0;
unmap:
	while (i--)
		iounmap(base[i]);
	return -ENOMEM;
}

static void __exit peek_exit(void)
{
	int i;

	debugfs_remove(file);
	for (i = 0; i < count; i++)
		iounmap(base[i]);
}

module_init(peek_init);
module_exit(peek_exit);
MODULE_DESCRIPTION("Read-only view of the RPM master sleep statistics");
MODULE_LICENSE("GPL");
