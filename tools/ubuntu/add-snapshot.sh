#!/bin/bash
# Build GNOME Snapshot (the camera) with snapshot-sunstone.patch into /usr/local of an Ubuntu root
# built by build-rootfs.sh (DIR, or / on the running phone). Ubuntu's 50.0 turns the preview upright
# for the phone's natural (portrait) orientation only: in landscape it shows a portrait strip turned
# sideways, and pictures are saved as the sensor delivers them. The patch turns the image by the
# display's rotation as well (mutter's DisplayConfig) and the pictures upright. Ubuntu's
# gnome-snapshot stays installed for its runtime dependencies; /usr/local comes first in PATH and
# XDG_DATA_DIRS (desktop file, D-Bus service, GSettings schema). The source is the pinned 50.0 tag.
#   add-snapshot.sh DIR SRC       SRC holds tools/ubuntu/snapshot-sunstone.patch
set -euo pipefail
R=${1:?usage: add-snapshot.sh DIR SRC}
SRC=${2:?usage: add-snapshot.sh DIR SRC}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
URL=https://gitlab.gnome.org/GNOME/snapshot.git TAG=50.0
COMMIT=79cc14698813eb067d7042c3ab4e5bfdf99f204d
# kept: Ubuntu's build and what it pulls in (GTK, libadwaita, glycin, GStreamer and its plug-ins)
RUNTIME_PKGS="gnome-snapshot gstreamer1.0-plugins-good gstreamer1.0-plugins-bad"
BUILD_PKGS="git ca-certificates cargo rustc meson ninja-build pkgconf gettext desktop-file-utils
	libglib2.0-dev-bin libgtk-4-dev libadwaita-1-dev libglycin-2-dev libglycin-gtk4-2-dev
	libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-bad1.0-dev liblcms2-dev
	libseccomp-dev"
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $RUNTIME_PKGS
# in an image, what was not installed yet is removed afterwards (on the running phone autoremove could
# take more than that: they stay)
NEW=$(for p in $BUILD_PKGS; do in_root dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q '^install ok installed' || echo "$p"; done)
[ -z "$NEW" ] || in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $NEW

B=/usr/local/src/snapshot
rm -rf "${R%/}$B"; mkdir -p "${R%/}$B"
in_root git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" "$URL" "$B/src"
[ "$(in_root git -C "$B/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "snapshot $TAG is not $COMMIT" >&2; exit 1; }
cp "$SRC/tools/ubuntu/snapshot-sunstone.patch" "${R%/}$B/"
in_root git -C "$B/src" apply "$B/snapshot-sunstone.patch"
# the crates (Cargo.lock) come from crates.io into the build directory, removed with it
in_root env CARGO_HOME="$B/cargo" sh -ec "cd $B/src && meson setup -Dprefix=/usr/local build >/dev/null &&
	ninja -C build >/dev/null && meson install -C build >/dev/null"

[ -z "$NEW" ] || [ "$R" = / ] ||
	{ in_root apt-mark auto -qq $NEW >/dev/null; in_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q >/dev/null; }
rm -rf "${R%/}$B"
in_root glib-compile-schemas /usr/local/share/glib-2.0/schemas
echo "Snapshot $TAG with snapshot-sunstone.patch in /usr/local"
