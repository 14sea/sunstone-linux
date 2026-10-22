#!/bin/bash
# Pack out/Image-STAGE + dts/*-STAGE.dts into a boot_a image: DTB -> SWEETLNX payload -> shim.
#   tools/mkboot.sh m1      -> out/boot-m1.img
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${1:?usage: mkboot.sh STAGE}
DTS=$(ls "$ROOT"/dts/*-"$STAGE".dts)
SRC=$(ls -d "$ROOT"/src/linux-*/ | sort -V | tail -1)
# the kernel's own dts preprocessing: dtsi and dt-bindings from the source tree
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$SRC/arch/arm64/boot/dts/qcom" -I "$SRC/include" \
	"$DTS" -o "$ROOT/out/$STAGE.dts.pp"
dtc -q -I dts -O dtb -o "$ROOT/out/$STAGE.dtb" "$ROOT/out/$STAGE.dts.pp"
python3 "$ROOT/tools/mklinuxpayload.py" "$ROOT/out/Image-$STAGE" "$ROOT/out/$STAGE.dtb" "$ROOT/out/payload-$STAGE.bin"
"$ROOT/shim/build.sh" "$ROOT/out/payload-$STAGE.bin" >/dev/null
cp "$ROOT/shim/out/shim-boot.img" "$ROOT/out/boot-$STAGE.img"
size=$(stat -c%s "$ROOT/out/boot-$STAGE.img")
[ "$size" -lt $((128 << 20)) ] || { echo "boot image is $size bytes, boot_a is 128 MiB" >&2; exit 1; }
ls -l "$ROOT/out/boot-$STAGE.img"
sha256sum "$ROOT/out/boot-$STAGE.img"
