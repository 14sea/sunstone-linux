// SPDX-License-Identifier: GPL-2.0
/*
 * Debug aid: the subsystems' own sleep statistics in SMEM, as mainline qcom_stats reads them on
 * RPMh SoCs (its RPM config leaves them out), at /sys/kernel/debug/smem-sleep-peek. Items that do
 * not exist are skipped. SMEM is shared DDR: only read.
 */
#include <linux/debugfs.h>
#include <linux/err.h>
#include <linux/module.h>
#include <linux/seq_file.h>
#include <linux/soc/qcom/smem.h>

static const struct { const char *name; unsigned int item; unsigned int pid; } subsystems[] = {
	{ "modem", 605, 1 }, { "wpss", 605, 13 }, { "adsp", 606, 2 }, { "cdsp", 607, 5 },
	{ "slpi", 608, 3 }, { "gpu", 609, 0 }, { "display", 610, 0 },
	{ "adsp_island", 613, 2 }, { "slpi_island", 613, 3 }, { "apss", 631, QCOM_SMEM_HOST_ANY },
};

struct sleep_stats {
	u32 stat_type;
	u32 count;
	u64 last_entered_at;
	u64 last_exited_at;
	u64 accumulated;
};

static struct dentry *file;

static int peek_show(struct seq_file *s, void *unused)
{
	struct sleep_stats st;
	size_t size;
	void *p;
	int i;

	for (i = 0; i < ARRAY_SIZE(subsystems); i++) {
		p = qcom_smem_get(subsystems[i].pid, subsystems[i].item, &size);
		if (IS_ERR(p)) {
			seq_printf(s, "%-12s item %u: %ld\n", subsystems[i].name, subsystems[i].item, PTR_ERR(p));
			continue;
		}
		memcpy(&st, p, min(size, sizeof(st)));
		seq_printf(s, "%-12s item %u size %zu: type 0x%x count %u last_entered 0x%llx last_exited 0x%llx accumulated 0x%llx\n",
			   subsystems[i].name, subsystems[i].item, size, st.stat_type, st.count,
			   st.last_entered_at, st.last_exited_at, st.accumulated);
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(peek);

static int __init peek_init(void)
{
	if (!qcom_smem_is_available())
		return -EPROBE_DEFER;
	file = debugfs_create_file("smem-sleep-peek", 0400, NULL, NULL, &peek_fops);
	return 0;
}

static void __exit peek_exit(void)
{
	debugfs_remove(file);
}

module_init(peek_init);
module_exit(peek_exit);
MODULE_DESCRIPTION("Read-only view of the subsystem sleep statistics in SMEM");
MODULE_LICENSE("GPL");
