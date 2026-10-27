#!/bin/bash
# Build libcamera 0.7.0 (Ubuntu's version) with libcamera-sunstone-af.patch into /usr/local of an
# Ubuntu root built by build-rootfs.sh (DIR, or / on the running phone): contrast detection
# autofocus for the main camera (OV48B2Q + DW9800) in the software ISP's simple IPA, which has
# none. Only the simple pipeline and IPA are built. The library keeps Ubuntu's SONAME
# (libcamera.so.0.7) and its public ABI, and /usr/local/lib/aarch64-linux-gnu comes first in the
# loader's path, so PipeWire's libcamera plug-in and GNOME Snapshot use it; Ubuntu's packages stay
# installed. Its IPA modules, proxies and tuning files are the ones under /usr/local. Removing
# /usr/local/lib/aarch64-linux-gnu/libcamera* (and ldconfig) goes back to Ubuntu's.
#   add-libcamera-af.sh DIR SRC       SRC holds tools/ubuntu/libcamera-sunstone-af.patch
set -euo pipefail
R=${1:?usage: add-libcamera-af.sh DIR SRC}
SRC=${2:?usage: add-libcamera-af.sh DIR SRC}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
URL=https://git.libcamera.org/libcamera/libcamera.git TAG=v0.7.0
COMMIT=b7854fd07d42168f099b5ce30d1702e0e0875bf5
BUILD_PKGS="git ca-certificates meson ninja-build pkgconf g++ python3-yaml python3-ply python3-jinja2
	libyaml-dev libssl-dev openssl libudev-dev libevent-dev libdrm-dev libjpeg-dev libegl-dev
	libgles-dev libgbm-dev"
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

# in an image, what was not installed yet is removed afterwards (on the running phone it stays)
NEW=$(for p in $BUILD_PKGS; do in_root dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q '^install ok installed' || echo "$p"; done)
[ -z "$NEW" ] || in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $NEW

B=/usr/local/src/libcamera
rm -rf "${R%/}$B"; mkdir -p "${R%/}$B"
in_root git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" "$URL" "$B/src"
[ "$(in_root git -C "$B/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "libcamera $TAG is not $COMMIT" >&2; exit 1; }
cp "$SRC/tools/ubuntu/libcamera-sunstone-af.patch" "${R%/}$B/"
in_root git -C "$B/src" apply "$B/libcamera-sunstone-af.patch"
# libdir: with prefix /usr/local meson would use lib/, which the loader searches after Ubuntu's
# /usr/lib/aarch64-linux-gnu (ld.so.conf.d order), so Ubuntu's library would still be the one loaded
in_root sh -ec "cd $B/src && meson setup build -Dprefix=/usr/local -Dlibdir=lib/aarch64-linux-gnu -Dbuildtype=release \
	-Dpipelines=simple -Dipas=simple -Dcam=enabled -Dqcam=disabled -Dgstreamer=disabled \
	-Dv4l2=false -Dlc-compliance=disabled -Dtest=false -Ddocumentation=disabled -Dpycamera=disabled \
	-Dtracing=disabled -Dudev=enabled >/dev/null &&
	ninja -C build >/dev/null && meson install -C build >/dev/null && ldconfig"

# every libcamera symbol PipeWire's plug-in imports must be in the new library
SPA=$(in_root sh -c 'ls /usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so')
missing=$(in_root sh -c "nm -D --undefined-only $SPA | awk '/libcamera/ { print \$2 }' | sort -u |
	while read -r s; do nm -D --defined-only /usr/local/lib/aarch64-linux-gnu/libcamera.so.0.7 \
		/usr/local/lib/aarch64-linux-gnu/libcamera-base.so.0.7 | grep -q \" \$s\\\$\" || echo \$s; done")
[ -z "$missing" ] || { echo "symbols PipeWire's plug-in needs are missing: $missing" >&2; exit 1; }

[ -z "$NEW" ] || [ "$R" = / ] ||
	in_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q --autoremove $NEW >/dev/null
echo "libcamera with autofocus installed in /usr/local"
