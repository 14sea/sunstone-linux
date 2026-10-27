// SPDX-License-Identifier: GPL-2.0
/*
 * Debug aid: a few 32-bit registers at a physical address, read on each read of
 * /sys/kernel/debug/mmio-peek. Read-only. Only for blocks that are always powered and clocked
 * (e.g. GCC's PLLs): reading the whole GCC regmap in debugfs resets the SoC (2026-10-27).
 *   insmod mmio-peek.ko phys=0x140b000 count=16
 */
#include <linux/debugfs.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/seq_file.h>

static unsigned long phys;
module_param(phys, ulong, 0444);
static unsigned int count = 16;
module_param(count, uint, 0444);

static void __iomem *base;
static struct dentry *file;

static int peek_show(struct seq_file *s, void *unused)
{
	unsigned int i;

	for (i = 0; i < count; i++)
		seq_printf(s, "%08lx: %08x\n", phys + 4 * i, readl(base + 4 * i));
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(peek);

static int __init peek_init(void)
{
	if (!phys || !count || count > 256)
		return -EINVAL;
	base = ioremap(phys, 4 * count);
	if (!base)
		return -ENOMEM;
	file = debugfs_create_file("mmio-peek", 0400, NULL, NULL, &peek_fops);
	return 0;
}

static void __exit peek_exit(void)
{
	debugfs_remove(file);
	iounmap(base);
}

module_init(peek_init);
module_exit(peek_exit);
MODULE_DESCRIPTION("Read a few registers at a physical address");
MODULE_LICENSE("GPL");
