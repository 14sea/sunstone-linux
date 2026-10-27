// SPDX-License-Identifier: GPL-2.0
/*
 * Experiment: vote 0 in the APSS's RPM sleep set for the bus clocks nothing manages on SM4375.
 * clk-smd-rpm hands BIMC, CNOC, SNOC, MMNRT, MMRT and QUP off at INT_MAX in the active set for an
 * interconnect driver to take over, and mainline has none for SM6375; SNOC_PERIPH and SNOC_LPASS
 * keep their hand-off vote because clk_ignore_unused leaves unused clocks alone. None of them ever
 * gets a sleep set request. Loading sends sleep = 0 for all eight (what an interconnect driver with
 * active-only votes would leave), unloading sends INT_MAX back. With misc=1 also the RPM clocks
 * nothing ever prepared (QDSS, BIMC_FREQ_LOG, CE1, HWKM, PKA), which clk_disable_unused would
 * have switched off, sleep = 0 likewise (hand-off value back on unload).
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/soc/qcom/smd-rpm.h>

struct rpm_req {
	__le32 key;
	__le32 nbytes;
	__le32 value;
};

#define KEY_RATE	QCOM_RPM_SMD_KEY_RATE
#define KEY_ENABLE	QCOM_RPM_SMD_KEY_ENABLE

static const struct { const char *name; u32 type, id, key, handoff; bool misc; } buses[] = {
	{ "bimc",          QCOM_SMD_RPM_MEM_CLK,   0, KEY_RATE,   INT_MAX },
	{ "cnoc",          QCOM_SMD_RPM_BUS_CLK,   1, KEY_RATE,   INT_MAX },
	{ "snoc",          QCOM_SMD_RPM_BUS_CLK,   2, KEY_RATE,   INT_MAX },
	{ "mmnrt",         QCOM_SMD_RPM_MMAXI_CLK, 0, KEY_RATE,   INT_MAX },
	{ "mmrt",          QCOM_SMD_RPM_MMAXI_CLK, 1, KEY_RATE,   INT_MAX },
	{ "qup",           QCOM_SMD_RPM_QUP_CLK,   0, KEY_RATE,   INT_MAX },
	{ "snoc_periph",   QCOM_SMD_RPM_BUS_CLK,   0, KEY_RATE,   INT_MAX },
	{ "snoc_lpass",    QCOM_SMD_RPM_BUS_CLK,   5, KEY_RATE,   INT_MAX },
	{ "qdss",          QCOM_SMD_RPM_MISC_CLK,  1, KEY_ENABLE, 1, true },
	{ "bimc_freq_log", QCOM_SMD_RPM_MISC_CLK,  4, KEY_ENABLE, 1, true },
	{ "ce1",           QCOM_SMD_RPM_CE_CLK,    0, KEY_RATE,   INT_MAX, true },
	{ "hwkm",          QCOM_SMD_RPM_HWKM_CLK,  0, KEY_RATE,   INT_MAX, true },
	{ "pka",           QCOM_SMD_RPM_PKA_CLK,   0, KEY_RATE,   INT_MAX, true },
};

static bool misc;
module_param(misc, bool, 0444);

static struct qcom_smd_rpm *rpm;

static void vote_sleep(bool restore)
{
	struct rpm_req req = { .nbytes = cpu_to_le32(sizeof(u32)) };
	u32 value;
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(buses); i++) {
		if (buses[i].misc && !misc)
			continue;
		value = restore ? buses[i].handoff : 0;
		req.key = cpu_to_le32(buses[i].key);
		req.value = cpu_to_le32(value);
		ret = qcom_rpm_smd_write(rpm, QCOM_SMD_RPM_SLEEP_STATE, buses[i].type, buses[i].id,
					 &req, sizeof(req));
		pr_info("rpm-sleep-vote: %s sleep %u: %d\n", buses[i].name, value, ret);
	}
}

static int __init sv_init(void)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, "qcom,rpmcc-sm6375");
	struct platform_device *pdev = np ? of_find_device_by_node(np) : NULL;

	of_node_put(np);
	if (!pdev)
		return -ENODEV;
	rpm = dev_get_drvdata(pdev->dev.parent);
	put_device(&pdev->dev);
	if (!rpm)
		return -ENODEV;
	vote_sleep(false);
	return 0;
}

static void __exit sv_exit(void)
{
	vote_sleep(true);
}

module_init(sv_init);
module_exit(sv_exit);
MODULE_DESCRIPTION("Experiment: RPM sleep set votes for unmanaged bus clocks");
MODULE_LICENSE("GPL");
