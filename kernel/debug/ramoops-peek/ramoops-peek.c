// SPDX-License-Identifier: GPL-2.0
/*
 * Debug aid: a read-only copy of a physical RAM range (by default the ramoops region), taken when
 * the module loads, at /sys/kernel/debug/ramoops-peek. Used to see what happens to the ramoops
 * region across a reset (decay, or overwritten by the boot chain) without trusting ramoops' own
 * headers. Mapped like ramoops maps it (vmap, write-combine), never written.
 *   insmod ramoops-peek.ko [phys=0xd0000000 size=0x200000]
 */
#include <linux/debugfs.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>

static unsigned long phys = 0xd0000000;
module_param(phys, ulong, 0444);
static unsigned long size = 0x200000;
module_param(size, ulong, 0444);

static struct debugfs_blob_wrapper blob;
static struct dentry *file;

static int __init peek_init(void)
{
	unsigned int n = size >> PAGE_SHIFT, i;
	struct page **pages;
	void *va;

	if (!size || (phys | size) & ~PAGE_MASK || !pfn_valid(PHYS_PFN(phys)))
		return -EINVAL;
	pages = kcalloc(n, sizeof(*pages), GFP_KERNEL);
	blob.data = vmalloc(size);
	if (!pages || !blob.data)
		goto nomem;
	for (i = 0; i < n; i++)
		pages[i] = pfn_to_page(PHYS_PFN(phys) + i);
	va = vmap(pages, n, VM_MAP, pgprot_writecombine(PAGE_KERNEL));
	kfree(pages);
	if (!va) {
		vfree(blob.data);
		return -ENOMEM;
	}
	memcpy(blob.data, va, size);
	vunmap(va);
	blob.size = size;
	file = debugfs_create_blob("ramoops-peek", 0400, NULL, &blob);
	pr_info("ramoops-peek: copied %#lx bytes from %#lx\n", size, phys);
	return 0;
nomem:
	kfree(pages);
	vfree(blob.data);
	return -ENOMEM;
}

static void __exit peek_exit(void)
{
	debugfs_remove(file);
	vfree(blob.data);
}

module_init(peek_init);
module_exit(peek_exit);
MODULE_DESCRIPTION("read-only copy of a physical RAM range (ramoops debugging)");
MODULE_LICENSE("GPL");
