#!/bin/bash
# Configure and build the kernel for a milestone (its initramfs is built in).
#   tools/build-kernel.sh m1
# Source tree: src/linux-*/ (newest), build tree: out/kbuild, result: out/Image-STAGE.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${1:?usage: build-kernel.sh STAGE}
SRC=$(ls -d "$ROOT"/src/linux-*/ | sort -V | tail -1)
KB=$ROOT/out/kbuild
M="make -C $SRC O=$KB ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)"
mkdir -p "$KB"

# local patches (kernel/patches/*.patch), each applied once
for p in "$ROOT"/kernel/patches/*.patch; do
	[ -e "$p" ] || continue
	if ! patch -d "$SRC" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
		patch -d "$SRC" -p1 -N -s < "$p"
		echo "applied $(basename "$p")"
	fi
done

# initramfs list with absolute paths (@ROOT@ = this checkout)
sed -e "s|@ROOT@|$ROOT|g" "$ROOT/initramfs/$STAGE.list" > "$ROOT/out/initramfs-$STAGE.list"
grep -o "$ROOT/[^ ]*" "$ROOT/out/initramfs-$STAGE.list" | while read -r f; do
	[ -e "$f" ] || { echo "initramfs input missing: $f" >&2; exit 1; }
done

[ -f "$KB/.config" ] || $M defconfig >/dev/null
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$KB" "$KB/.config" "$ROOT/kernel/platforms-off.config" "$ROOT/kernel/sunstone.config" >/dev/null
"$SRC/scripts/config" --file "$KB/.config" --set-str INITRAMFS_SOURCE "$ROOT/out/initramfs-$STAGE.list"
$M olddefconfig >/dev/null
for o in DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE PSTORE_RAM PSTORE_CONSOLE DEVTMPFS USB_CONFIGFS_NCM PHY_QCOM_USB_SNPS_FEMTO_V2; do
	grep -q "^CONFIG_$o=y" "$KB/.config" || { echo "CONFIG_$o did not end up =y" >&2; exit 1; }
done
$M Image
cp "$KB/arch/arm64/boot/Image" "$ROOT/out/Image-$STAGE"
ls -l "$ROOT/out/Image-$STAGE"
