#!/bin/bash
# Pack out/Image-KSTAGE + dts/*-STAGE.dts into a boot_a image: DTB -> SWEETLNX payload -> shim.
#   tools/mkboot.sh sunstone   -> out/boot-sunstone.img (dts/sm4375-xiaomi-sunstone.dts)
#   tools/mkboot.sh rescue     -> out/boot-rescue.img (the same board in rescue mode)
# KSTAGE is the kernel build (tools/build-kernel.sh KSTAGE), m6 unless given.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${1:?usage: mkboot.sh STAGE}
KSTAGE=${KSTAGE:-m6}
DTS=$(ls "$ROOT"/dts/*-"$STAGE".dts)
SRC=$(ls -d "$ROOT"/src/linux-*/ | sort -V | tail -1)
# the kernel's own dts preprocessing: dtsi and dt-bindings from the source tree
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$SRC/arch/arm64/boot/dts/qcom" -I "$SRC/include" \
	"$DTS" -o "$ROOT/out/$STAGE.dts.pp"
dtc -q -I dts -O dtb -o "$ROOT/out/$STAGE.dtb" "$ROOT/out/$STAGE.dts.pp"
python3 "$ROOT/tools/mklinuxpayload.py" "$ROOT/out/Image-$KSTAGE" "$ROOT/out/$STAGE.dtb" "$ROOT/out/payload-$STAGE.bin"
# the shim starts the hardware watchdog only for a kernel that has qcom-wdt to take it over
# (WDT=0/1 overrides); a rescue kernel without it would be reset after 32 s
# or for a rescue system (sunstone.rescue: no systemd to take it over)
if [ -z "${WDT:-}" ]; then
	WDT=0
	grep -aq 'qcom,kpss-wdt' "$ROOT/out/Image-$KSTAGE" && ! grep -q 'sunstone\.rescue' "$ROOT/out/$STAGE.dts.pp" && WDT=1
fi
echo "shim watchdog: $([ "$WDT" = 1 ] && echo started before Linux || echo off)"
WDT=$WDT "$ROOT/shim/build.sh" "$ROOT/out/payload-$STAGE.bin" >/dev/null
cp "$ROOT/shim/out/shim-boot.img" "$ROOT/out/boot-$STAGE.img"
size=$(stat -c%s "$ROOT/out/boot-$STAGE.img")
[ "$size" -lt $((128 << 20)) ] || { echo "boot image is $size bytes, boot_a is 128 MiB" >&2; exit 1; }
ls -l "$ROOT/out/boot-$STAGE.img"
sha256sum "$ROOT/out/boot-$STAGE.img"
