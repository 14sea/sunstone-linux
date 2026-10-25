#!/bin/bash
# Add Lomiri, Ubuntu Touch's shell, to an Ubuntu root built by build-rootfs.sh (DIR, or / on the
# running phone), as an optional desktop: started by hand (systemctl start lomiri), the phone still
# boots to the text console. Runs as the desktop user phone (uid 1000: no password, no ssh, no sudo).
# Ubuntu Touch itself needs a Halium (Android) kernel; its shell runs on Mir over the msm KMS and GPU.
# --no-install-recommends, so the Mir platforms and the keyboard layouts are named here (without a
# layout, maliit-server crashes and takes Lomiri with it).
#   add-lomiri.sh DIR SRC       SRC holds rootfs-overlay-lomiri/
set -euo pipefail
R=${1:?usage: add-lomiri.sh DIR SRC}
SRC=${2:?usage: add-lomiri.sh DIR SRC}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
PKGS="lomiri-desktop-session mir-platform-graphics-gbm-kms mir-platform-input-evdev10
	mir-platform-rendering-egl-generic lomiri-keyboard lomiri-keyboard-english lomiri-keyboard-emoji
	lomiri-keyboard-chinese-pinyin lomiri-polkit-agent suru-icon-theme fonts-ubuntu xdg-user-dirs kbd"
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

# Lomiri's network indicator pulls in NetworkManager, which would take wlan0 from networkd and
# wpa_supplicant@wlan0: masked first (build-rootfs.sh does it too)
ln -sf /dev/null "$R/etc/systemd/system/NetworkManager.service"
in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $PKGS
in_root systemctl disable -q wpa_supplicant.service NetworkManager-wait-online.service NetworkManager-dispatcher.service 2>/dev/null || true
in_root id phone >/dev/null 2>&1 || in_root useradd -m -u 1000 -s /bin/bash -G video,render,input,audio phone
# Lomiri's settings app (its Bluetooth page never lists devices under GNOME) only in Lomiri: a copy
# in /usr/local/share/applications, which comes first in XDG_DATA_DIRS, shadows the package's entry
D=lomiri-system-settings.desktop
install -d "$R/usr/local/share/applications"
grep -v '^OnlyShowIn=' "$R/usr/share/applications/$D" | sed '/^\[Desktop Entry\]/a OnlyShowIn=Lomiri;' \
	> "$R/usr/local/share/applications/$D"
cp -a "$SRC/rootfs-overlay-lomiri/." "$R/"
(cd "$SRC/rootfs-overlay-lomiri" && find . -mindepth 1) | sed "s|^\.|${R%/}|" | xargs chown -h 0:0
[ "$R" = / ] && systemctl daemon-reload && systemctl try-restart sunstone-powerkey
echo "Lomiri added; start it with: systemctl start lomiri"
