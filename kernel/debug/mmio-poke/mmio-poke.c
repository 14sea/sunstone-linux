// SPDX-License-Identifier: GPL-2.0
/*
 * Debug aid: one read-modify-write of a 32-bit register at load time, old and new value in
 * the kernel log; the module then unloads itself (insmod reports -EAGAIN, as intended).
 *   insmod mmio-poke.ko phys=0x147d078 mask=0x1 val=0x0
 */
#include <linux/io.h>
#include <linux/module.h>

static unsigned long phys;
module_param(phys, ulong, 0444);
static unsigned int mask;
module_param(mask, uint, 0444);
static unsigned int val;
module_param(val, uint, 0444);

static int __init poke_init(void)
{
	void __iomem *reg;
	u32 old, new;

	if (!phys || !mask)
		return -EINVAL;
	reg = ioremap(phys, 4);
	if (!reg)
		return -ENOMEM;
	old = readl(reg);
	new = (old & ~mask) | (val & mask);
	writel(new, reg);
	pr_info("mmio-poke: %#lx: %#010x -> %#010x, reads back %#010x\n", phys, old, new, readl(reg));
	iounmap(reg);
	return -EAGAIN;
}

module_init(poke_init);
MODULE_DESCRIPTION("One read-modify-write of a register");
MODULE_LICENSE("GPL");
