// SPDX-License-Identifier: GPL-2.0
/*
 * Experiment: vote 0 in the APSS's RPM sleep set for the bus clocks nothing manages on SM4375.
 * clk-smd-rpm hands BIMC, CNOC, SNOC, MMNRT, MMRT and QUP off at INT_MAX in the active set for an
 * interconnect driver to take over, and mainline has none for SM6375; SNOC_PERIPH and SNOC_LPASS
 * keep their hand-off vote because clk_ignore_unused leaves unused clocks alone. None of them ever
 * gets a sleep set request. Loading sends sleep = 0 for all eight (what an interconnect driver with
 * active-only votes would leave), unloading sends INT_MAX back.
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

static const struct { const char *name; u32 type, id; } buses[] = {
	{ "bimc",        QCOM_SMD_RPM_MEM_CLK,   0 },
	{ "cnoc",        QCOM_SMD_RPM_BUS_CLK,   1 },
	{ "snoc",        QCOM_SMD_RPM_BUS_CLK,   2 },
	{ "mmnrt",       QCOM_SMD_RPM_MMAXI_CLK, 0 },
	{ "mmrt",        QCOM_SMD_RPM_MMAXI_CLK, 1 },
	{ "qup",         QCOM_SMD_RPM_QUP_CLK,   0 },
	{ "snoc_periph", QCOM_SMD_RPM_BUS_CLK,   0 },
	{ "snoc_lpass",  QCOM_SMD_RPM_BUS_CLK,   5 },
};

static struct qcom_smd_rpm *rpm;

static void vote_sleep(u32 value)
{
	struct rpm_req req = {
		.key = cpu_to_le32(QCOM_RPM_SMD_KEY_RATE),
		.nbytes = cpu_to_le32(sizeof(u32)),
		.value = cpu_to_le32(value),
	};
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(buses); i++) {
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
	vote_sleep(0);
	return 0;
}

static void __exit sv_exit(void)
{
	vote_sleep(INT_MAX);
}

module_init(sv_init);
module_exit(sv_exit);
MODULE_DESCRIPTION("Experiment: RPM sleep set votes for unmanaged bus clocks");
MODULE_LICENSE("GPL");
