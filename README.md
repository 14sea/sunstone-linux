# sunstone-linux

Mainline Linux (7.3) and Ubuntu Server 26.04 LTS on the **Xiaomi Redmi Note 12 5G** (`sunstone`,
Qualcomm SM4375 "blair" / Snapdragon 4 Gen 1), run as a mostly screen-off server, with GNOME or
Lomiri as an optional desktop. Brought up one milestone at a time, with Arch Linux ARM until
2026-10-25. No Android, no Halium: the stock bootloaders chainload a boot shim, the shim boots the
mainline kernel, the kernel boots Ubuntu from `userdata`.
The working notes (`PLAN.md`, `TODO.md`, `LOG.md`) are in Chinese.

## Status (2026-10-27)

| Hardware | State |
| --- | --- |
| CPU, memory, UFS | 6x A55 + 2x A78 with cpufreq and cooling maps, 8 GB, UFS (local patch 0001) |
| Display | 1080x2400 AMOLED, DSI + DSC panel driver (0008), 120 Hz and 60 Hz, backlight, power-key blanking |
| GPU | Adreno 619 (0007), freedreno (Mesa), OpenGL 4.6 (Vulkan not tried); zap shader from the phone's vendor partition |
| Touch, keys | FT5452 touchscreen (0002), power and volume keys |
| Wi-Fi | WCN3988 over ath10k, the modem (MPSS) running its firmware; Xiaomi's board data from `modem_a`; linux-firmware's `firmware-5.bin` with single-chan-info-per-channel (`sunstone-ath10k-fw5`: scan survey data, no chan info warnings) |
| Bluetooth | WCN3988 on its UART, Xiaomi's firmware from `bluetooth_a`; classic and LE keyboards and mice tested |
| Battery | SM5602 fuel gauge (0003), SC89890H charger (0004), charge limit 4.1 V for life on the charger |
| microSD | UHS-I SDR104 (sdhc_2), card detect on the SIM tray switch; a card labelled `sdcard` (ext4) mounted at `/srv/sd` at boot and again after a tray swap |
| USB | NCM + ACM gadget (ssh and a serial console from the host); OTG host through the HUSB311 Type-C port controller (TCPM, dual role), VBUS from the charger's boost (0028); USB 2.0 |
| Audio | speaker (LPASS, WCD9370 codec, SIA8159 amplifier: 0011-0016), main and second microphones, headphones with jack detection; ALSA UCM for PipeWire and GNOME |
| Cameras | 48 MP OV48B2Q main (4000x3000 and 2000x1500: 0020, 0022) with contrast-detect autofocus on its DW9800 actuator (libcamera patch, `tools/ubuntu/add-libcamera-af.sh`; `sunstone-camera-focus fixed` holds it at about 2 m instead), 8 MP OV08D10 front, 2 MP SC202CS (monochrome depth: 0021); CAMSS for SM6375 (0018), WL2866D camera LDOs (0017); libcamera's software ISP, GNOME Snapshot (portrait and landscape); rear flash LED (KTD2691 as an LM36011: 0025, 0027); the OPE offline ISP (upstream v5 series, 0042-0047) converts Bayer to YUV in hardware, but libcamera does not use it yet; the main camera module's calibration EEPROM is readable (`sunstone-cam-otp`: module data and its lens shading grid) |
| Cellular | mobile data through IPA v4.11 and ModemManager (tested with an IoT SIM); the SIM comes back by itself after the SIM/microSD tray is swapped (`sunstone-sim-watch`) |
| Sensors | accelerometer, gyroscope, light, proximity, magnetometer and compass through the ADSP's SSC (hexagonrpcd with writes, libssc, iio-sensor-proxy); GNOME auto-rotate |
| DSPs | ADSP (audio, sensors), CDSP (Turing) with FastRPC (nothing uses it yet); fastrpc resumes an interrupted invoke instead of sending it again (0033) |
| Power | s2idle with RTC and power-key wake (0032, 0033), automatic suspend left off for the server; bus scaling through the SM6375 NoC driver (0036: BIMC/CNOC/SNOC, CPU DDR floors per OPP and the CPU BWMON, votes from display, GPU, cameras, UFS, SD, USB, IPA, QUP); runtime PM fixes for gpucc (0034), UFS lane clocks (0035), wcd937x RX clocks (0030), q6afe clock votes (0031); the SoC does not reach XO shutdown / VDD minimization yet (`TODO.md`) |
| Other | vibration motor, IR transmitter |
| Thermal | tsens zones throttle the CPU policies and the GPU; board thermistors (XO, skin, PA, SoC, camera flash) on the PMK8350/PM6125 ADCs, the skin zone throttling from 55 C; battery zone on the gauge's NTC capping the charge current (1 A from 45 C, stopped from 55 C: 0038); PM6125 die alarm at downstream's 95/115/145 C |
| Reliability | hardware watchdog from the boot shim on (kernel hangs too), panics reboot into Linux, the boot marked successful for ABL, pstore (console, oops/panic records) kept across resets by resetting warm through PS_HOLD (0029), a directory per boot in `/var/lib/systemd/pstore`, QRTR HELLO fix (0010) for the modem's init stall; audio and sensors come back after an ADSP restart |
| Not working | earpiece, voice calls, SMS (untested), fingerprint; hardware video codec (Venus probes with 0039-0041, but with the phone's firmware 6.0.52 the decoder corrupts frames after about 20 and encoding hangs the SoC: disabled in the DTS); no NFC chip in this unit; hardware RNG and crypto engine left out (see `TODO.md`) |

| Software | |
| --- | --- |
| System | Ubuntu Server 26.04 LTS on `userdata`, built on the phone itself (`tools/mkrootfs-ubuntu.sh`), no Ubuntu kernel or boot loader; root over ssh only, ufw with ssh in |
| Network | systemd-networkd + wpa_supplicant by default; NetworkManager for Wi-Fi when a desktop wants it (`tools/ubuntu/wifi-to-networkmanager.sh`); usb0 always networkd |
| Desktops | optional, started by hand on tty7: GNOME (Ubuntu session, landscape, `tools/ubuntu/add-gnome.sh`) or Lomiri, Ubuntu Touch's shell (`tools/ubuntu/add-lomiri.sh`) |
| Media | PipeWire in 16 bit with the UCM profile; cameras through libcamera's simple pipeline and PipeWire's libcamera plugin (WirePlumber's V4L2 monitor off), buffers from the system dma-buf heap; GNOME Snapshot built with a patch that turns the preview and the pictures with the display (`tools/ubuntu/add-snapshot.sh`); libcamera 0.7.0 with contrast-detect autofocus in `/usr/local` (`tools/ubuntu/add-libcamera-af.sh`), switched to a fixed focus at about 2 m with `sunstone-camera-focus fixed` or GNOME's Camera Focus launcher |
| Sensors | hexagonrpcd built with a write patch (`tools/ubuntu/add-hexagonrpcd.sh`), libssc and iio-sensor-proxy with SSC support (`tools/ubuntu/add-ssc.sh`) |

Open items are in `TODO.md` (earpiece, SMS, Venus with
this firmware, the OPE and lens shading in libcamera, GNOME's smoothness, panel brightness curve, DSI PHY clock
warning, dispcc PLL latch, ...).

| Milestone | State |
| --- | --- |
| M1 boot | shim chainloads mainline Linux from `boot_a`, simpledrm on ABL's splash |
| M2 ssh | USB NCM gadget, ssh from the test host |
| M3 rootfs | Arch Linux ARM on `userdata` (switch_root from the initramfs) |
| M4 hardware | UFS, keys, FT5452 touch, SM5602 fuel gauge, SC89890H charger, RTC offset, PON reboot modes |
| M5 Wi-Fi | modem (MPSS) + WCN3988 over ath10k, joins on boot |
| M6 desktop | Phosh on the Adreno 619 (freedreno); real display: MDSS/DPU/DSI + DSC panel driver, built in |
| Server | watchdog, boot-success mark, charge limit, text console with power-key blanking; 24 h soak on Ubuntu passed (2026-10-28, boot-192); Docker with Compose and Buildx, published ports local unless given an address (`tools/ubuntu/add-docker.sh`, `docker-selftest.sh`, 2026-10-29); no automatic suspend, but s2idle reaches VDD min (2026-10-29) |
| Ubuntu | Ubuntu Server 26.04 replaces Arch; Bluetooth; GNOME and Lomiri as optional desktops |
| Peripherals | audio, sensors, cellular data, cameras and flash, vibration, IR (2026-10-25/26); board thermistors, pstore, microSD, main camera autofocus, then the SM6375 interconnects, the battery thermal zone, the OPE offline ISP and the camera EEPROM (2026-10-27) |

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

No vendor firmware is in this repository. The phone's own partitions provide it at run time,
all mounted read-only (`rootfs-overlay/usr/local/sbin/sunstone-fw-install`: modem, ADSP and WLAN
firmware from modem_a, Venus' too; the GPU zap shader, the IPA's GSI firmware and the sensor configuration
from the vendor partition; Bluetooth from bluetooth_a; the sensor registry from persist and the
DSP libraries from dsp_a); the GPU SQE microcode comes from `linux-firmware`. The one file
built into the kernel image, regulatory.db, is fetched by `tools/fetch-firmware.sh`, pinned by sha256.

## Licensing

Kernel patches are GPL-2.0 (the kernel's licence); 0042-0045 are Loic Poulain's CAMSS OPE v5 series as posted,
and the SM6375 NoC driver (0036) carries node data from Xiaomi's GPL kernel source. The DTS files are BSD-3-Clause. The patches in
`tools/ubuntu/` are under the licence of the program they patch (GNOME Snapshot: GPL-3.0-or-later; libcamera: LGPL-2.1-or-later).
The shim comes from `14sea/ios-sunstone`, which builds on `ios-topaz`; no licence is claimed for it
here.
