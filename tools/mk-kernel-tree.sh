#!/bin/bash
# Make the kernel source tree used by build-kernel.sh: src/linux-VER as a git repository with the
# kernel.org tarball as its first commit (tag vVER-tarball) and one commit per kernel/patches/*.patch
# on the branch `sunstone`. Debug work goes on branches above `sunstone`; tools/export-kernel-patches.sh
# writes `sunstone` back to kernel/patches/.
#   tools/mk-kernel-tree.sh 7.3        (needs downloads/linux-7.3.tar.xz, checked against sha256sums.asc)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=${1:?usage: mk-kernel-tree.sh VERSION}
TAR=$ROOT/downloads/linux-$VER.tar.xz
DST=$ROOT/src/linux-$VER
[ -e "$DST" ] && { echo "$DST exists; move it away first" >&2; exit 1; }
(cd "$ROOT/downloads" && grep " linux-$VER.tar.xz\$" sha256sums.asc | sha256sum -c -)
mkdir -p "$DST"
tar -xJf "$TAR" -C "$DST" --strip-components=1
cd "$DST"
git init -q -b master
git config user.name 14sea
git config user.email 14sea@users.noreply.github.com
git add -A -f   # -f: the tarball has files the kernel's .gitignore matches (Documentation/.renames.txt)
git commit -q -m "Linux $VER (kernel.org tarball, sha256 $(sha256sum "$TAR" | cut -c1-8)...)"
git tag "v$VER-tarball"
git checkout -q -b sunstone
for p in "$ROOT"/kernel/patches/*.patch; do
	[ -e "$p" ] || continue
	patch -p1 -s < "$p"
	git add -A
	# commit message: the patch's description (everything before its first diff line)
	git commit -q -m "$(sed -n '/^--- \|^diff --git /q;p' "$p")" -m "From kernel/patches/$(basename "$p")"
done
git log --oneline "v$VER-tarball..sunstone"
