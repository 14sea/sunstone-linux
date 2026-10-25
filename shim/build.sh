#!/bin/bash
# Build the sunstone-linux shim and wrap it in boot images (flashed to boot_a:
# sunstone ABL has no `fastboot boot`). Usage: build.sh [payload.bin]
# payload.bin is a SWEETLNX payload (tools/mklinuxpayload.py): Image + DTB.
# sunstone's stock boot image is v3 (DTB and vendor ramdisk come from
# vendor_boot), so out/shim-boot.img is v3; out/shim-boot-v4.img is the
# ios-topaz packing as a fallback if this ABL refuses v3.
#
# ios-topaz packing: data for the shim (the Linux payload, or a
# test blob) is appended to the kernel Image at the first 4K boundary
# after _end, and the Image header's image_size grows to cover it.
# The ramdisk is an uncompressed cpio with a marker file so the shim can
# tell whether ABL passes our ramdisk at all.
set -euo pipefail
cd "$(dirname "$0")"
CC=aarch64-linux-gnu-gcc
OBJCOPY=aarch64-linux-gnu-objcopy
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
# PON_FASTBOOT=1: ask ABL for fastboot before booting Linux, so any later reset (panic, watchdog,
# long power press) lands in fastboot: the development safety net. Default 0 (an always-on server):
# a panic reboots straight back into Linux; `reboot bootloader` still reaches fastboot.
CFLAGS="$CFLAGS -DSHIM_PON_FASTBOOT=${PON_FASTBOOT:-0}"
# WDT=1: start the APSS watchdog right before Linux (only for a kernel with qcom-wdt, which takes
# it over; tools/mkboot.sh decides). Without a driver feeding it the phone resets after 32 s.
CFLAGS="$CFLAGS -DSHIM_WDT=${WDT:-0}"
SRCS="start.S shim.c console.c mmu.c fdt.c loader.c"
mkdir -p out
for f in $SRCS; do
	$CC $CFLAGS -c $f -o out/${f%.*}.o
done
# The image runs wherever ABL puts it with no relocation pass: only the
# header's image_size (start.o, linked at 0) may be an absolute address.
abs=$(aarch64-linux-gnu-readelf -r out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	out/start.o out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o -o out/shim.elf
$OBJCOPY -O binary out/shim.elf out/Image
# ABL copies the file; pad to image_size so .bss/stacks exist as zeroed bytes.
size=$((16#$(aarch64-linux-gnu-nm out/shim.elf | awk '$3=="_end"{print $1}')))
truncate -s "$size" out/Image

# Embedded blob at the first 4K boundary after _end, then grow image_size:
# the SWEETLNX payload (tools/mklinuxpayload.py) if given as $1, else a 4K test blob.
truncate -s $(( (size + 0xfff) & ~0xfff )) out/Image
if [ -n "${1:-}" ]; then
	cat "$1" >> out/Image
else
	python3 -c 'import sys; sys.stdout.buffer.write(b"SUNEMBED".ljust(4096, b"\0"))' >> out/Image
fi
python3 -c 'import os,struct,sys; f=open(sys.argv[1],"r+b"); f.seek(16); f.write(struct.pack("<Q", os.path.getsize(sys.argv[1])))' out/Image

# Ramdisk: uncompressed newc cpio holding the marker the shim searches for.
rm -rf out/rd && mkdir -p out/rd
printf 'SUNSTONE-RD-MARK-7f3a\n' > out/rd/sunstone-marker
(cd out/rd && find . | LC_ALL=C sort | cpio -o -H newc --quiet > ../ramdisk.cpio)

python3 ../tools/mkbootimg_v3.py --header-version 3 --kernel out/Image --ramdisk out/ramdisk.cpio -o out/shim-boot.img
python3 ../tools/mkbootimg_v3.py --header-version 4 --kernel out/Image --ramdisk out/ramdisk.cpio -o out/shim-boot-v4.img
ls -l out/Image out/shim-boot.img out/shim-boot-v4.img
sha256sum out/shim-boot.img out/shim-boot-v4.img
