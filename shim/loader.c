/*
 * sunstone-linux: boot a mainline arm64 Linux Image from the SWEETLNX payload that
 * build.sh appends behind the shim (first 4K boundary after _end).
 *
 *   "SWEETLNX", u32 version = 1, u32 header size, then (all offsets from the payload start)
 *   u64 image_off, image_size, dtb_off, dtb_size, load_pa, dtb_pa, payload_size
 *
 * ABL's downstream DTB is ignored: Linux gets the DTB from the payload. Per
 * Documentation/arch/arm64/booting.rst: the Image goes to a 2 MiB aligned base + text_offset,
 * the DTB 8-byte aligned and outside the image, MMU and D-cache off (ABL entered the shim
 * that way and the shim never turns them on on this path), interrupts masked,
 * x0 = DTB physical address, x1-x3 = 0, at EL1 (where ABL leaves us).
 */
#include <stdint.h>
#include "console.h"
#include "loader.h"

#define ARM64_IMAGE_MAGIC	0x644d5241u	/* "ARM\x64" at offset 0x38 */
#define SZ_2M			0x200000UL

struct lnx_payload {
	char magic[8];
	uint32_t version, hdr_size;
	uint64_t image_off, image_size, dtb_off, dtb_size;
	uint64_t load_pa, dtb_pa, payload_size;
};

struct arm64_image_header {
	uint32_t code0, code1;
	uint64_t text_offset, image_size, flags;
	uint64_t res2, res3, res4;
	uint32_t magic, res5;
};

_Static_assert(sizeof(struct lnx_payload) == 72, "SWEETLNX header layout");
_Static_assert(__builtin_offsetof(struct arm64_image_header, magic) == 0x38, "arm64 Image header layout");

/* MMU off: device-type accesses, so plain aligned 64-bit words, no memcpy tail tricks */
static void copy64(uintptr_t dst, uintptr_t src, uint64_t n)
{
	volatile uint64_t *d = (volatile uint64_t *)dst;
	volatile const uint64_t *s = (volatile const uint64_t *)src;
	for (uint64_t i = 0; i < (n + 7) / 8; i++)
		d[i] = s[i];
}

static int overlap(uint64_t a, uint64_t alen, uint64_t b, uint64_t blen)
{
	return a < b + blen && b < a + alen;
}

static int magic_ok(const char *m)
{
	static const char want[] = "SWEETLNX";
	for (int i = 0; i < 8; i++)
		if (m[i] != want[i])
			return 0;
	return 1;
}

const char *linux_boot(uintptr_t pl)
{
	const struct lnx_payload *p = (const struct lnx_payload *)pl;

	if (!magic_ok(p->magic))
		return "no SWEETLNX payload";
	if (p->version != 1 || p->hdr_size != sizeof(*p) || (p->image_off & 7) || (p->dtb_off & 7))
		return "bad SWEETLNX header";
	if ((p->load_pa & (SZ_2M - 1)) || (p->dtb_pa & 7) || p->dtb_size > SZ_2M)
		return "bad load or DTB address";

	const struct arm64_image_header *h = (const struct arm64_image_header *)(pl + p->image_off);
	if (h->magic != ARM64_IMAGE_MAGIC)
		return "not an arm64 Image";
	/* image_size covers .bss as well; 0 only in kernels older than 3.17 */
	uint64_t ksize = h->image_size ? h->image_size : p->image_size;
	uintptr_t entry = p->load_pa + h->text_offset;

	con_hex2("PAYLOAD", "at=", pl, "size=", p->payload_size);
	con_hex2("IMAGE", "size=", p->image_size, "mem=", ksize);
	con_hex2("LOAD", "pa=", entry, "flags=", h->flags);
	con_hex2("DTB", "pa=", p->dtb_pa, "size=", p->dtb_size);

	if (overlap(pl, p->payload_size, entry, ksize) || overlap(pl, p->payload_size, p->dtb_pa, p->dtb_size))
		return "payload overlaps the kernel or DTB destination";
	if (overlap(entry, ksize, p->dtb_pa, p->dtb_size))
		return "DTB inside the kernel image";

	copy64(entry, pl + p->image_off, p->image_size);
	copy64(p->dtb_pa, pl + p->dtb_off, p->dtb_size);
	con_str("LINUX", "jumping");

	/* written with the MMU and caches off: drop stale I-cache lines; Linux sets its own VBAR */
	__asm__ volatile("msr daifset, #0xf; dsb sy; ic iallu; dsb sy; isb" ::: "memory");
	register uint64_t x0 __asm__("x0") = p->dtb_pa;
	register uint64_t x1 __asm__("x1") = 0;
	register uint64_t x2 __asm__("x2") = 0;
	register uint64_t x3 __asm__("x3") = 0;
	register uint64_t x4 __asm__("x4") = entry;
	__asm__ volatile("br x4" : : "r"(x0), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
	return "linux returned";
}
