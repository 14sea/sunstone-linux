# sunstone-linux

Mainline Linux (7.3) and a prebuilt Arch Linux ARM userland on the **Xiaomi Redmi Note 12 5G**
(`sunstone`, Qualcomm SM4375 "blair" / Snapdragon 4 Gen 1), brought up one milestone at a time.
The working notes (`PLAN.md`, `TODO.md`, `LOG.md`) are in Chinese.

## Status (2026-10-23)

| Milestone | State |
| --- | --- |
| M1 boot | shim chainloads mainline Linux from `boot_a`, simpledrm on ABL's splash |
| M2 ssh | USB NCM gadget, ssh from the test host |
| M3 rootfs | Arch Linux ARM on `userdata` (switch_root from the initramfs) |
| M4 hardware | UFS, keys, FT5452 touch, SM5602 fuel gauge, SC89890H charger, RTC offset, PON reboot modes |
| M5 Wi-Fi | modem (MPSS) + WCN3988 over ath10k, joins on boot |
| M6 desktop | Phosh on the Adreno 619 (freedreno); real display: MDSS/DPU/DSI + DSC panel driver (still loaded as a module after boot) |

Open items are in `TODO.md` (modem stall on cold boot, WLAN board data, built-in panel driver
crashing early boot, screen blanking, ...).

## How it boots

ABL only boots the boot image in `boot_a` and passes a downstream DTB, which mainline cannot use.
`shim/` (from the `ios-sunstone` project) is loaded by ABL as the "kernel"; it ignores ABL's DTB and
jumps to a `SWEETLNX` payload appended behind it: the mainline `Image` plus the board DTB from
`dts/`. Only `boot_a` and `userdata` are ever written; the bootloaders, `vendor_boot`, `dtbo`,
`vbmeta`, modem, persist and EFS partitions are left alone.

## Layout

| Path | What |
| --- | --- |
| `dts/` | Board DTS per milestone, each including the previous one (m1 -> ... -> m6 -> m6d) |
| `kernel/` | `sunstone.config` fragment and local patches (`patches/`, applied by `build-kernel.sh`) |
| `initramfs/` | Built-in initramfs per milestone (`init-mN`, `mN.list`) |
| `shim/` | The boot shim and the boot image wrapper |
| `rootfs-overlay/` | Files on top of Arch Linux ARM (Phosh service, wlroots patch build, firmware install, Wi-Fi setup, ...) |
| `tools/` | Build, pack and flash scripts; `tools/remote/` runs on the test host |

## Building

```sh
# kernel source in src/linux-7.3 (not in git), aarch64-linux-gnu- cross toolchain
tools/build-kernel.sh m6          # -> out/Image-m6 (patches applied once)
KSTAGE=m6 tools/mkboot.sh m6d     # -> out/boot-m6d.img: m6 kernel, m6d DTB, shim
tools/mkrootfs.sh                 # -> out/rootfs-arch.img for userdata
cp tools/host.conf.example tools/host.conf   # then tools/flash.sh STAGE N
```

No vendor firmware is in this repository. The phone's own partitions provide it at run time
(`rootfs-overlay/usr/local/sbin/sunstone-fw-install`); the GPU SQE microcode comes from
`linux-firmware`, the GPU zap shader is still copied over by hand (see `TODO.md`).

## Licensing

Kernel patches are GPL-2.0 (the kernel's licence); the DTS files are BSD-3-Clause. The shim comes
from `14sea/ios-sunstone`, which builds on `ios-topaz`; no licence is claimed for it here.
