# Kernel debugging aids

Not used by `tools/build-kernel.sh` unless asked for. Written for the M6 built-in panel hang
(LOG.md boot-34 to 81), kept for the next early-boot problem.

## `patches/`

The kernel tree's `debug/panel-early-bind` branch on top of `sunstone`, exported with
`git format-patch sunstone..debug/panel-early-bind`. Apply them to a branch above `sunstone` with
`git am` to get the same kernel back:

| Patch | What |
| --- | --- |
| 0001, 0002, 0005 | panel: `attach_delay_ms` / `attach_now` (attach from a workqueue, or when the initramfs asks), unbind/bind support, logging around prepare and the attach |
| 0003 | msm: `msm.sunstone_keepfb=1/2/3` keeps simpledrm and/or skips the fbdev client |
| 0004 | msm DSI: snapshot of the first DSI error before the registers are cleared, IRQ counts, the power-on context (`cat /sys/module/msm/parameters/sunstone_dsi_snap`); Lucid PLL latch failures name the PLL and print a stack |
| 0006 | panel: `late_register`, probe context in the log; netconsole: command-line targets wait for their device |
| 0007 | netconsole at `device_initcall`, so a probe that blocks `deferred_probe_initcall` cannot keep it from starting |

## `patches/qrtr-hello-order-log.patch`

Branch `debug/qrtr-fix-verify` on top of `sunstone` (which carries the fix, 0010): logs the HELLO
received from and sent to each QRTR node, a HELLO sent ahead of a packet, a second HELLO skipped and
the name service's announce result. Used for the modem init stall (LOG.md boot-102 to 106); the
loop that cycles the modem is `echo stop/start > /sys/class/remoteproc/remoteproc0/state`.

## Kernel log during kernel init

The normal netconsole starts in the initramfs (after the USB gadget is set up there), so a hang in
kernel init leaves no log, and pstore records do not survive the reset in readable form. With
patches 0006 and 0007, `EXTRA_CONFIG=kernel/debug/m6-display.config` (built-in `g_ncm` gadget,
hung-task reports, deferred fbcon takeover, a large console font) and these extra boot arguments,
the log reaches the test host's netconsole capture from about 0.6 s on:

    g_ncm.dev_addr=02:53:4e:00:00:02 g_ncm.host_addr=02:53:4e:00:00:01
    netconsole=@192.168.7.2/usb0,6666@192.168.7.1/02:53:4e:00:00:01

The MACs are the same as the initramfs gadget's, so the test host's interface name and capture do
not change; `initramfs/init-m6` sees the kernel gadget and the command-line target and skips its own.
`tools/run-exp.sh STAGE N` flashes one experiment image and stages the known-good `out/boot-saved.img` as the
restore for the next fastboot.

## Known limits of the debug patches

The workqueue attach (0001, 0002) uses a bare `mipi_dsi_attach()` with no matching detach: unbinding
the panel driver after a delayed attach leaves the DSI component bound to freed panel/DSC data, a
second bind can add the component twice, and `attached` is set before the attach succeeds. The
unbind/bind of boot-44 only worked because the first probe had not attached yet. Good enough for
the experiments, not for anything else; the `sunstone` branch uses `devm_mipi_dsi_attach()`.

## `ramoops-peek/`

A module that copies a physical RAM range (default: the ramoops region, 2 MiB at 0xd0000000) when it
loads and shows it read-only at `/sys/kernel/debug/ramoops-peek`, to see what a reset does to the
region without trusting ramoops' headers (2026-10-27: DRAM decay under PSCI's cold reset). Built
against the running kernel's build tree:

    make -C src/linux-7.3 O=$PWD/out/kbuild ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        M=$PWD/kernel/debug/ramoops-peek MO=/tmp/peek modules
    insmod ramoops-peek.ko [phys=0x... size=0x...]
