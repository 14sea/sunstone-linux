# sunstone-linux

Mainline Linux (7.3) and Ubuntu Server 26.04 LTS on the **Xiaomi Redmi Note 12 5G** (`sunstone`,
Qualcomm SM4375 "blair" / Snapdragon 4 Gen 1), brought up one milestone at a time (with Arch Linux
ARM until 2026-10-25), now run as a mostly screen-off server.
The working notes (`PLAN.md`, `TODO.md`, `LOG.md`) are in Chinese.

## Status (2026-10-23, evening)

| Milestone | State |
| --- | --- |
| M1 boot | shim chainloads mainline Linux from `boot_a`, simpledrm on ABL's splash |
| M2 ssh | USB NCM gadget, ssh from the test host |
| M3 rootfs | Arch Linux ARM on `userdata` (switch_root from the initramfs) |
| M4 hardware | UFS, keys, FT5452 touch, SM5602 fuel gauge, SC89890H charger, RTC offset, PON reboot modes |
| M5 Wi-Fi | modem (MPSS) + WCN3988 over ath10k, joins on boot |
| M6 desktop | Phosh on the Adreno 619 (freedreno); real display: MDSS/DPU/DSI + DSC panel driver, built in |
| Server | Ubuntu Server 26.04 on `userdata` (no Ubuntu kernel); watchdog from the boot shim on, boot marked successful for ABL, charge limit 4.1 V, text console with power-key blanking |

Open items are in `TODO.md` (panel error paths, DSI PHY clock warning, dispcc PLL latch, BPF LSM,
...).

## How it boots

ABL only boots the boot image in `boot_a` and passes a downstream DTB, which mainline cannot use.
`shim/` (from the `ios-sunstone` project) is loaded by ABL as the "kernel"; it ignores ABL's DTB and
jumps to a `SWEETLNX` payload appended behind it: the mainline `Image` plus the board DTB from
`dts/`. Only `boot_a` and `userdata` are ever written; the bootloaders, `vendor_boot`, `dtbo`,
`vbmeta`, modem, persist and EFS partitions are left alone. The one other write is the "successful"
bit of `boot_a`'s GPT attributes, set 2 min after each boot (`sunstone-boot-success`), as Android
does: without it ABL counts down boot_a's tries and stops in fastboot after 7 reboots without a flash.

## Layout

| Path | What |
| --- | --- |
| `dts/` | The board DTS (`sm4375-xiaomi-sunstone.dts`) and its rescue-mode variant; the per-milestone chain it was merged from is at the git tag `dts-milestones` |
| `kernel/` | `sunstone.config` fragment, local patches (`patches/`, one per commit of the kernel tree's `sunstone` branch) and debugging aids (`debug/`) |
| `initramfs/` | Built-in initramfs per milestone (`init-mN`, `mN.list`) |
| `shim/` | The boot shim and the boot image wrapper |
| `rootfs-overlay/` | Files on top of the distribution (firmware install, Wi-Fi setup, watchdog, power key, health log, boot-success mark, ...) |
| `rootfs-overlay-arch/` | Arch Linux ARM only: Phosh service, the wlroots patch build, the tqftpserv build |
| `rootfs-overlay-lomiri/` | Lomiri (Ubuntu Touch's shell) as an optional desktop on Ubuntu (`tools/ubuntu/add-lomiri.sh`) |
| `rootfs-overlay-gnome/` | Ubuntu's GNOME session as an optional desktop, landscape (`tools/ubuntu/add-gnome.sh`) |
| `tools/` | Build, pack and flash scripts; `tools/remote/` runs on the test host, `tools/ubuntu/` on the phone (Ubuntu root filesystem) |

## Building

```sh
# downloads/linux-7.3.tar.xz + sha256sums.asc from kernel.org, aarch64-linux-gnu- cross toolchain
tools/mk-kernel-tree.sh 7.3       # -> src/linux-7.3: git tree, tarball + one commit per kernel/patches file
tools/fetch-firmware.sh           # -> downloads/firmware: regulatory.db, built into the image
tools/build-kernel.sh m6          # -> out/Image-m6, out/modules-m6 and out/build-m6.info (checks patches = branch)
tools/mkboot.sh sunstone          # -> out/boot-sunstone.img: m6 kernel, board DTB, shim
tools/mkboot.sh rescue            # -> out/boot-rescue.img: rescue mode (USB ssh, userdata unmounted)
tools/mkrootfs-ubuntu.sh          # -> out/ubuntu-rootfs.img.zst: Ubuntu Server 26.04, built on the phone
tools/install-rootfs.sh N IMG.zst # rescue boot, image -> userdata, boot image -> boot_a, reboot
tools/mkrootfs.sh                 # (the earlier Arch Linux ARM root: out/rootfs-arch.img)
cp tools/host.conf.example tools/host.conf   # then tools/flash.sh STAGE N, tools/push-modules.sh
```

Kernel changes are made as commits on `sunstone` in `src/linux-7.3` and written back with
`tools/export-kernel-patches.sh`.

No vendor firmware is in this repository. The phone's own partitions provide it at run time
(`rootfs-overlay/usr/local/sbin/sunstone-fw-install`: modem, WLAN and the GPU zap shader from
modem_a and the vendor partition); the GPU SQE microcode comes from `linux-firmware`. The one file
built into the kernel image, regulatory.db, is fetched by `tools/fetch-firmware.sh`, pinned by sha256.

## Licensing

Kernel patches are GPL-2.0 (the kernel's licence); the DTS files are BSD-3-Clause. The shim comes
from `14sea/ios-sunstone`, which builds on `ios-topaz`; no licence is claimed for it here.
