#!/bin/bash
# Write the commits of the kernel tree's `sunstone` branch to kernel/patches/NNNN-*.patch (the
# format build-kernel.sh and mk-kernel-tree.sh read: subject, body, then the diff). Existing files
# are replaced; review with git diff before committing.
#   tools/export-kernel-patches.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(ls -d "$ROOT"/src/linux-*/ | sort -V | tail -1); SRC=${SRC%/}
BASE=$(git -C "$SRC" describe --tags --match 'v*-tarball' --abbrev=0 sunstone)
OUT=$ROOT/kernel/patches
n=0
for c in $(git -C "$SRC" rev-list --reverse "$BASE..sunstone"); do
	n=$((n + 1))
	old=$(ls "$OUT"/$(printf %04d $n)-*.patch 2>/dev/null | head -1)
	name=${old:-$OUT/$(printf %04d $n)-$(git -C "$SRC" log -1 --format=%f "$c" | cut -c1-50).patch}
	{
		git -C "$SRC" log -1 --format='%s%n%n%b' "$c" | grep -v '^From kernel/patches/' | cat -s
		git -C "$SRC" show --format= --no-renames "$c"
	} > "$name"
	echo "$(basename "$name")"
done
