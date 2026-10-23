#!/bin/bash
# Write the commits of the kernel tree's `sunstone` branch to kernel/patches/NNNN-*.patch (the
# format build-kernel.sh and mk-kernel-tree.sh read: description, then the diff). Everything is
# exported to a temporary directory first and only then replaces kernel/patches/*.patch, so a failure
# leaves the old set alone. A number that already has a file keeps its name; new numbers get one from
# the commit subject; files beyond the last commit are removed. Review with git diff before committing.
#   tools/export-kernel-patches.sh
set -euo pipefail
shopt -s nullglob
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${KERNEL_SRC:-$(ls -d "$ROOT"/src/linux-*/ | sort -V | tail -1)}; SRC=${SRC%/}
BASE=$(git -C "$SRC" describe --tags --match 'v*-tarball' --abbrev=0 sunstone)
OUT=${PATCH_DIR:-$ROOT/kernel/patches}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
n=0
for c in $(git -C "$SRC" rev-list --reverse "$BASE..sunstone"); do
	n=$((n + 1))
	num=$(printf %04d $n)
	old=("$OUT/$num"-*.patch)
	if [ ${#old[@]} -gt 0 ]; then
		name=$(basename "${old[0]}")
	else
		name=$num-$(git -C "$SRC" log -1 --format=%f "$c" | cut -c1-50).patch
	fi
	{
		git -C "$SRC" log -1 --format='%s%n%n%b' "$c" | grep -v '^From kernel/patches/' | cat -s
		git -C "$SRC" show --format= --no-renames "$c"
	} > "$TMP/$name"
done
[ $n -gt 0 ] || { echo "no commits in $BASE..sunstone" >&2; exit 1; }
rm -f "$OUT"/[0-9][0-9][0-9][0-9]-*.patch
mv "$TMP"/*.patch "$OUT"/
ls "$OUT"
