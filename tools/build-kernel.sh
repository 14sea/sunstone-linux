#!/bin/bash
# Configure and build the kernel for a milestone (its initramfs is built in).
#   tools/build-kernel.sh m1
#   EXTRA_CONFIG=path/to/debug.config tools/build-kernel.sh m6   (extra fragment, e.g. lockdep)
# Source tree: src/linux-*/ (newest), build tree: out/kbuild, result: out/Image-STAGE plus
# out/build-STAGE.info (source commit, uncommitted changes, config hash).
#
# The source is a git tree made by tools/mk-kernel-tree.sh: upstream tarball, then one commit per
# kernel/patches/*.patch on the branch `sunstone`, debug work on branches above it. Nothing is
# patched here; the build only checks that `sunstone` is part of what is checked out. A plain
# tarball tree (no .git) still gets the patches applied, as before.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${1:?usage: build-kernel.sh STAGE}
SRC=$(ls -d "$ROOT"/src/linux-*/ | sort -V | tail -1); SRC=${SRC%/}
KB=$ROOT/out/kbuild
M="make -C $SRC O=$KB ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)"
mkdir -p "$KB"

if [ -d "$SRC/.git" ]; then
	git -C "$SRC" merge-base --is-ancestor sunstone HEAD ||
		{ echo "$SRC: branch sunstone is not in HEAD's history" >&2; exit 1; }
	# kernel/patches and the sunstone branch must carry the same changes, in the same order:
	# compare git patch-ids (content, not just subjects)
	BASE=$(git -C "$SRC" describe --tags --match 'v*-tarball' --abbrev=0 sunstone)
	mapfile -t commits < <(git -C "$SRC" rev-list --reverse "$BASE..sunstone")
	patches=("$ROOT"/kernel/patches/[0-9][0-9][0-9][0-9]-*.patch)
	[ -e "${patches[0]}" ] || patches=()
	[ ${#commits[@]} -eq ${#patches[@]} ] ||
		{ echo "sunstone has ${#commits[@]} commits, kernel/patches ${#patches[@]} files" >&2; exit 1; }
	for i in "${!patches[@]}"; do
		a=$(git -C "$SRC" patch-id --stable < "${patches[$i]}" | cut -d' ' -f1)
		b=$(git -C "$SRC" show "${commits[$i]}" | git -C "$SRC" patch-id --stable | cut -d' ' -f1)
		[ -n "$a" ] && [ "$a" = "$b" ] || { echo "$(basename "${patches[$i]}") differs from sunstone commit" \
			"$(git -C "$SRC" log -1 --format='%h %s' "${commits[$i]}") (export or rebuild the tree)" >&2; exit 1; }
	done
else
	# local patches (kernel/patches/*.patch), each applied once
	for p in "$ROOT"/kernel/patches/*.patch; do
		[ -e "$p" ] || continue
		if ! patch -d "$SRC" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
			patch -d "$SRC" -p1 -N -s < "$p"
			echo "applied $(basename "$p")"
		fi
	done
fi

# initramfs list with absolute paths (@ROOT@ = this checkout)
sed -e "s|@ROOT@|$ROOT|g" "$ROOT/initramfs/$STAGE.list" > "$ROOT/out/initramfs-$STAGE.list"
grep -o "$ROOT/[^ ]*" "$ROOT/out/initramfs-$STAGE.list" | while read -r f; do
	[ -e "$f" ] || { echo "initramfs input missing: $f" >&2; exit 1; }
done

# the .config is made from scratch every time, so options of an earlier EXTRA_CONFIG build do not stay
$M defconfig >/dev/null
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$KB" "$KB/.config" "$ROOT/kernel/platforms-off.config" "$ROOT/kernel/sunstone.config" ${EXTRA_CONFIG:-} >/dev/null
"$SRC/scripts/config" --file "$KB/.config" --set-str INITRAMFS_SOURCE "$ROOT/out/initramfs-$STAGE.list"
"$SRC/scripts/config" --file "$KB/.config" --set-str EXTRA_FIRMWARE_DIR "$ROOT/downloads/regdb"
$M olddefconfig >/dev/null
for o in DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE PSTORE_RAM PSTORE_CONSOLE DEVTMPFS USB_CONFIGFS_NCM PHY_QCOM_USB_SNPS_FEMTO_V2 QCOM_Q6V5_PAS ATH10K_SNOC; do
	grep -q "^CONFIG_$o=y" "$KB/.config" || { echo "CONFIG_$o did not end up =y" >&2; exit 1; }
done
$M Image
cp "$KB/arch/arm64/boot/Image" "$ROOT/out/Image-$STAGE"

{
	echo "stage: $STAGE"
	echo "date: $(date -Is)"
	if [ -d "$SRC/.git" ]; then
		echo "source: $(git -C "$SRC" rev-parse --abbrev-ref HEAD) $(git -C "$SRC" rev-parse --short=12 HEAD)"
		echo "uncommitted: $(git -C "$SRC" diff HEAD | sha256sum | cut -c1-16) ($(git -C "$SRC" diff HEAD --stat | tail -1))"
		echo "untracked: $(git -C "$SRC" status --porcelain --untracked-files=all | grep -c '^??' || true) files"
	fi
	echo "extra config: ${EXTRA_CONFIG:-none}"
	echo "config: $(grep -v '^#' "$KB/.config" | grep -v '^CONFIG_INITRAMFS_SOURCE=' | sort | sha256sum | cut -c1-16)"
	echo "Image: $(sha256sum "$ROOT/out/Image-$STAGE" | cut -c1-16)"
} > "$ROOT/out/build-$STAGE.info"
cat "$ROOT/out/build-$STAGE.info"
ls -l "$ROOT/out/Image-$STAGE"
