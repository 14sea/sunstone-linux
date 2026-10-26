#!/bin/bash
# Build hexagonrpcd 0.4.0 with hexagonrpcd-sunstone.patch (a writable sensor registry and the calls
# sunstone's sensors PD makes; Ubuntu's package serves files read-only and the PD then takes the ADSP
# down) into an Ubuntu root built by build-rootfs.sh (DIR, or / on the running phone), as
# /usr/local/libexec/hexagonrpc/hexagonrpcd; rootfs-overlay's hexagonrpcd.service.d/sunstone.conf
# runs it. The source is upstream's v0.4.0 tag, checked against its commit.
#   add-hexagonrpcd.sh DIR SRC       SRC holds tools/ubuntu/hexagonrpcd-sunstone.patch
set -euo pipefail
R=${1:?usage: add-hexagonrpcd.sh DIR SRC}
SRC=${2:?usage: add-hexagonrpcd.sh DIR SRC}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
URL=https://github.com/linux-msm/hexagonrpc.git TAG=v0.4.0 COMMIT=23a69640bf10dc498226c602c5b5db11d8cb3d8e
BUILD_PKGS="git patch ca-certificates meson ninja-build gcc libc6-dev"
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

# in an image, what was not installed yet is removed afterwards (on the running phone autoremove could
# take more than that: they stay)
NEW=$(for p in $BUILD_PKGS; do in_root dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q '^install ok installed' || echo "$p"; done)
[ -z "$NEW" ] || in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $NEW

B=/usr/local/src/hexagonrpc
rm -rf "${R%/}$B"
in_root git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" "$URL" "$B"
[ "$(in_root git -C "$B" rev-parse HEAD)" = "$COMMIT" ] || { echo "$TAG is not $COMMIT" >&2; exit 1; }
in_root patch -d "$B" -p1 -s < "$SRC/tools/ubuntu/hexagonrpcd-sunstone.patch"
in_root sh -c 'cd /usr/local/src/hexagonrpc && meson setup -Dprefix=/usr/local build >/dev/null &&
	ninja -C build >/dev/null && meson install -C build --destdir $PWD/dest >/dev/null &&
	install -D -m755 dest/usr/local/bin/hexagonrpcd /usr/local/libexec/hexagonrpc/hexagonrpcd'
[ -z "$NEW" ] || [ "$R" = / ] ||
	{ in_root apt-mark auto -qq $NEW >/dev/null; in_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q >/dev/null; }
rm -rf "${R%/}$B"
# meson install drops the build tree's RUNPATH: the packaged libhexagonrpc is the same 0.4
in_root ldd /usr/local/libexec/hexagonrpc/hexagonrpcd | grep -q '/usr/lib/.*libhexagonrpc' ||
	{ echo "hexagonrpcd does not link the packaged libhexagonrpc" >&2; exit 1; }
[ "$R" = / ] && systemctl daemon-reload
echo "hexagonrpcd $TAG + sunstone patch in /usr/local/libexec/hexagonrpc/"
