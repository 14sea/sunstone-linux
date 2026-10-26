#!/bin/bash
# Build the SSC sensor stack for the desktop into an Ubuntu root built by build-rootfs.sh (DIR, or /
# on the running phone): libssc (the SSC's client library, with ssccli) in /usr/local, and
# iio-sensor-proxy with SSC support as /usr/local/libexec/iio-sensor-proxy (Ubuntu's 3.8 has none;
# upstream added it after 3.8). Ubuntu's iio-sensor-proxy package provides the unit, D-Bus and
# polkit files; rootfs-overlay's iio-sensor-proxy.service.d/sunstone.conf runs this build and
# 79-sunstone-ssc.rules marks the ADSP's fastrpc device as an SSC. The sources are pinned commits.
#   add-ssc.sh DIR
set -euo pipefail
R=${1:?usage: add-ssc.sh DIR}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
SSC_URL=https://codeberg.org/DylanVanAssche/libssc.git SSC_TAG=v0.4.4
SSC_COMMIT=0cf77b93b55752da34dca2dcecc06fca8665184b
ISP_URL=https://gitlab.freedesktop.org/hadess/iio-sensor-proxy.git ISP_BRANCH=master
ISP_COMMIT=ca0d5b08bd647afc5f8ead3ce00a44018fbc633f
# kept: what the builds link against, and the package with the unit files
RUNTIME_PKGS="iio-sensor-proxy libprotobuf-c1 libqmi-glib5 libqrtr-glib0 libgudev-1.0-0 libpolkit-gobject-1-0"
BUILD_PKGS="git ca-certificates meson ninja-build gcc libc6-dev pkgconf protobuf-compiler protobuf-c-compiler
	libprotobuf-c-dev libqmi-glib-dev libqrtr-glib-dev libglib2.0-dev libgudev-1.0-dev
	libpolkit-gobject-1-dev systemd-dev libudev-dev"
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $RUNTIME_PKGS
# in an image, what was not installed yet is removed afterwards (on the running phone autoremove could
# take more than that: they stay)
NEW=$(for p in $BUILD_PKGS; do in_root dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q '^install ok installed' || echo "$p"; done)
[ -z "$NEW" ] || in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $NEW

B=/usr/local/src/ssc
rm -rf "${R%/}$B"; mkdir -p "${R%/}$B"
in_root git -c advice.detachedHead=false clone -q --depth 1 --branch "$SSC_TAG" "$SSC_URL" "$B/libssc"
[ "$(in_root git -C "$B/libssc" rev-parse HEAD)" = "$SSC_COMMIT" ] || { echo "libssc $SSC_TAG is not $SSC_COMMIT" >&2; exit 1; }
in_root git -c advice.detachedHead=false clone -q --filter=blob:none --branch "$ISP_BRANCH" "$ISP_URL" "$B/iio-sensor-proxy"
in_root git -C "$B/iio-sensor-proxy" -c advice.detachedHead=false checkout -q "$ISP_COMMIT"

# libssc's mocking/ and tests/ need Python modules that are not packaged: built without them
in_root sh -ec "cd $B/libssc && sed -i \"/^subdir('mocking')\$/d; /^subdir('tests')\$/d\" meson.build &&
	meson setup -Dprefix=/usr/local -Dlibdir=lib build >/dev/null && ninja -C build >/dev/null &&
	meson install -C build >/dev/null && ldconfig"
in_root sh -ec "cd $B/iio-sensor-proxy && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
	meson setup -Dprefix=/usr/local -Dssc-support=enabled -Dtests=false -Dgtk-tests=false build >/dev/null &&
	ninja -C build >/dev/null && meson install -C build --destdir \$PWD/dest >/dev/null &&
	install -m755 dest/usr/local/libexec/iio-sensor-proxy /usr/local/libexec/iio-sensor-proxy"
[ -z "$NEW" ] || [ "$R" = / ] ||
	{ in_root apt-mark auto -qq $NEW >/dev/null; in_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q >/dev/null; }
rm -rf "${R%/}$B"
in_root ldd /usr/local/libexec/iio-sensor-proxy | grep -q '/usr/local/lib/libssc' ||
	{ echo "iio-sensor-proxy does not link libssc" >&2; exit 1; }
if [ "$R" = / ]; then
	systemctl daemon-reload
	udevadm trigger --action=change /dev/fastrpc-adsp 2>/dev/null || true
fi
echo "libssc $SSC_TAG and iio-sensor-proxy ${ISP_COMMIT:0:12} (SSC) in /usr/local"
