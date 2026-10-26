#!/bin/bash
# Add Ubuntu's GNOME session (Wayland) to an Ubuntu root built by build-rootfs.sh (DIR, or / on the
# running phone), as an optional desktop like add-lomiri.sh: systemctl start gnome, no display
# manager, the desktop user phone (uid 1000: no password, no ssh, no sudo), landscape at scale 2.5,
# the power key handled by sunstone-powerkey. About 280 packages: the session, Files, a terminal,
# Settings and Camera (Snapshot, through PipeWire's libcamera plugin), without snapd and without
# ubuntu-desktop-minimal's printing, updates and the like.
#   add-gnome.sh DIR SRC       SRC holds rootfs-overlay-gnome/
set -euo pipefail
R=${1:?usage: add-gnome.sh DIR SRC}
SRC=${2:?usage: add-gnome.sh DIR SRC}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
PKGS="ubuntu-session nautilus ptyxis gnome-control-center ubuntu-settings yaru-theme-gtk yaru-theme-icon
	yaru-theme-gnome-shell gnome-shell-extension-ubuntu-dock kbd gnome-snapshot libspa-0.2-libcamera gstreamer1.0-pipewire"
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

# NetworkManager would take wlan0 from networkd (build-rootfs.sh masks it as well)
ln -sf /dev/null "$R/etc/systemd/system/NetworkManager.service"
in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $PKGS
in_root id phone >/dev/null 2>&1 || in_root useradd -m -u 1000 -s /bin/bash -G video,render,input,audio phone
cp -a --no-preserve=ownership "$SRC/rootfs-overlay-gnome/." "$R/"
(cd "$SRC/rootfs-overlay-gnome" && find . -mindepth 1) | sed "s|^\.|${R%/}|" | xargs chown -h 0:0
in_root glib-compile-schemas /usr/share/glib-2.0/schemas
# one desktop at a time on tty7
[ -e "$R/etc/systemd/system/lomiri.service" ] &&
	sed -i 's/^Conflicts=getty@tty7.service$/Conflicts=getty@tty7.service gnome.service/' "$R/etc/systemd/system/lomiri.service"
[ "$R" = / ] && systemctl daemon-reload && systemctl try-restart sunstone-powerkey
echo "GNOME added; start it with: systemctl start gnome"
