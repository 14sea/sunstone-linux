#!/bin/bash
# Build the Ubuntu Server root filesystem for sunstone in DIR, natively on an arm64 Linux as root (the
# phone itself: tools/mkrootfs-ubuntu.sh runs this there). debootstrap (minbase) plus a chosen package
# list -- never an Ubuntu kernel, initramfs or boot loader: the kernel, its modules and the boot chain
# come from this repository -- then the sunstone configuration and the distribution-neutral
# rootfs-overlay. Re-running on an existing DIR skips debootstrap and applies the rest again.
#   build-rootfs.sh DIR SRC      SRC holds rootfs-overlay/ and authorized_keys (copied from the repo)
set -euo pipefail
R=${1:?usage: build-rootfs.sh DIR SRC}
SRC=${2:?usage: build-rootfs.sh DIR SRC}
SUITE=${SUITE:-resolute}
MIRROR=${MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
TZ=${TZ:-Etc/UTC}
# Ubuntu keeps tools in the sbin directories, which a host with a merged bin (Arch) leaves out of PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
W=$(mktemp -d)
cleanup() {
	for m in dev/pts dev sys proc; do mountpoint -q "$R/$m" && umount "$R/$m"; done
	rm -rf "$W"
}
trap cleanup EXIT

PKGS="systemd systemd-sysv systemd-resolved systemd-timesyncd libpam-systemd libnss-systemd dbus udev kmod
	openssh-server iproute2 iputils-ping iw wpasupplicant rfkill rmtfs tqftpserv qrtr-tools linux-firmware
	python3 ca-certificates curl less nano vim-tiny sudo bash-completion tzdata apparmor ufw
	unattended-upgrades cron logrotate htop iperf3 strace i2c-tools usbutils ethtool lsof file psmisc
	zstd xz-utils gpg evtest ir-keytable mesa-utils libgl1-mesa-dri libegl-mesa0 mesa-vulkan-drivers"

# debootstrap and Ubuntu's archive keyring, if this system has none: the keyring is accepted for
# its 2018 archive key's fingerprint, then the chain InRelease -> Packages.xz -> .deb is checked
get_debootstrap() {
	local fpr=F6ECB3762474EDA9D21B7022871920D1991BC93C p f s
	cd "$W"
	curl -sfL -o InRelease "$MIRROR/dists/$SUITE/InRelease"
	curl -sfL -o Packages.xz "$MIRROR/dists/$SUITE/main/binary-arm64/Packages.xz"
	xz -dk Packages.xz
	field() { awk -v p="$1" -v k="$2:" '$1=="Package:"{m=($2==p)} m&&$1==k{print $2; exit}' Packages; }
	curl -sfL -o keyring.deb "$MIRROR/$(field ubuntu-keyring Filename)"
	mkdir k && (cd k && bsdtar -xf ../keyring.deb && bsdtar -xf data.tar.*)
	KEYRING=$W/k/usr/share/keyrings/ubuntu-archive-keyring.gpg
	gpg --show-keys --with-colons "$KEYRING" | awk -F: '$1=="fpr"{print $10}' | grep -qx $fpr ||
		{ echo "keyring without the archive key $fpr" >&2; exit 1; }
	gpgv --keyring "$KEYRING" InRelease
	s=$(awk '/^SHA256:/{x=1;next} /^[A-Z]/{x=0} x&&$3=="main/binary-arm64/Packages.xz"{print $1}' InRelease)
	echo "$s  Packages.xz" | sha256sum -c --quiet
	for p in ubuntu-keyring debootstrap; do
		curl -sfL -o $p.deb "$MIRROR/$(field $p Filename)"
		echo "$(field $p SHA256)  $p.deb" | sha256sum -c --quiet
		(mkdir -p ds && cd ds && bsdtar -xf ../$p.deb && bsdtar -xf data.tar.* && rm -f data.tar.* control.tar.* debian-binary)
	done
	KEYRING=$W/ds/usr/share/keyrings/ubuntu-archive-keyring.gpg
	export DEBOOTSTRAP_DIR=$W/ds/usr/share/debootstrap PATH=$W/ds/usr/sbin:$PATH
	# debootstrap fetches with wget [-U agent] ... -O dest url
	mkdir -p "$W/bin"
	printf '%s\n' '#!/bin/sh' 'out= ua=' \
		'while [ $# -gt 1 ]; do case $1 in -U) ua=$2; shift 2;; -O) out=$2; shift 2;; *) shift;; esac; done' \
		'exec curl -sfL --retry 3 ${ua:+-A "$ua"} -o "$out" "$1"' > "$W/bin/wget"
	chmod +x "$W/bin/wget"
	command -v wget >/dev/null || export PATH=$W/bin:$PATH
	cd - >/dev/null
}

if [ ! -x "$R/usr/bin/apt-get" ]; then
	KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
	command -v debootstrap >/dev/null && [ -s $KEYRING ] || get_debootstrap
	debootstrap --arch=arm64 --variant=minbase --components=main,universe --keyring="$KEYRING" \
		"$SUITE" "$R" "$MIRROR"
fi

# before any package is installed: the archive, no kernel or boot loader ever, and the units that
# must not run here masked first, so no postinst enables them
rm -f "$R/etc/apt/sources.list"
cat > "$R/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: $SUITE $SUITE-updates $SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
cat > "$R/etc/apt/preferences.d/sunstone-no-kernel" <<'EOF'
# sunstone: the kernel, its modules and the boot chain come from the sunstone-linux build (boot_a),
# never from Ubuntu
Package: linux-image-* linux-headers-* linux-modules-* linux-generic* linux-raspi* grub-* grub2-* flash-kernel u-boot-* shim-signed
Pin: release *
Pin-Priority: -1
EOF
# rmtfs.service serves the modem's EFS partitions themselves (rmtfs -P): never; rmtfs-dir.service
# serves the copies in /var/lib/rmtfs instead. qrtr-ns: the kernel runs the QRTR name service.
ln -sf /dev/null "$R/etc/systemd/system/rmtfs.service"
ln -sf /dev/null "$R/etc/systemd/system/qrtr-ns.service"
# networkd and wpa_supplicant@wlan0 run the network; NetworkManager (a dependency of Lomiri's
# network indicator, for one) would take wlan0 over
ln -sf /dev/null "$R/etc/systemd/system/NetworkManager.service"
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"
chmod +x "$R/usr/sbin/policy-rc.d"

for m in proc sys dev dev/pts; do mountpoint -q "$R/$m" || mount --bind "/$m" "$R/$m"; done
[ -L "$R/etc/resolv.conf" ] && mv "$R/etc/resolv.conf" "$W/resolv.conf.link"
cp -L /etc/resolv.conf "$R/etc/resolv.conf"
chroot "$R" apt-get update -q
chroot "$R" env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $PKGS
chroot "$R" env DEBIAN_FRONTEND=noninteractive apt-get -y -q dist-upgrade
# a postinst still enables a masked unit's wants link; the mask wins, but leave no dead link
for u in rmtfs.service qrtr-ns.service; do rm -f "$R"/etc/systemd/system/*.wants/$u; done
rm -f "$R/etc/resolv.conf"
if [ -e "$W/resolv.conf.link" ]; then mv "$W/resolv.conf.link" "$R/etc/resolv.conf"; else
	ln -s ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"; fi

echo sunstone > "$R/etc/hostname"
cat > "$R/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	sunstone
::1		localhost ip6-localhost ip6-loopback
EOF
# x-systemd.growfs: the image is smaller than userdata, systemd grows the root at the first boot
echo 'PARTLABEL=userdata  /  ext4  rw,relatime,x-systemd.growfs  0 1' > "$R/etc/fstab"
ln -sf "/usr/share/zoneinfo/$TZ" "$R/etc/localtime"
echo "$TZ" > "$R/etc/timezone"
# C.UTF-8 needs no locales package; pam_env reads this on every login
echo LANG=C.UTF-8 > "$R/etc/default/locale"

# ssh: root with the test host's key (Ubuntu's sshd: PermitRootLogin prohibit-password), and only
# root (a desktop user, add-lomiri.sh, has no ssh login)
install -d -m 700 -o 0 -g 0 "$R/root/.ssh"
install -m 600 -o 0 -g 0 "$SRC/authorized_keys" "$R/root/.ssh/authorized_keys"
printf 'AllowUsers root\n' > "$R/etc/ssh/sshd_config.d/sunstone.conf"

# USB network: the initramfs already configured the NCM gadget; networkd gives the phone
# 192.168.7.2 and hands the host 192.168.7.1, no route, no DNS. Wi-Fi: 20-wlan0.network (overlay).
# networkd directly, no netplan.
cat > "$R/etc/systemd/network/10-usb0.network" <<'EOF'
[Match]
# the gadget's dev_addr (initramfs), whatever udev names the interface
MACAddress=02:53:4e:00:00:02

[Network]
Address=192.168.7.2/24
DHCPServer=yes
ConfigureWithoutCarrier=yes

[DHCPServer]
PoolOffset=1
PoolSize=1
EmitDNS=no
EmitRouter=no
EOF
chroot "$R" systemctl enable -q systemd-networkd.service
# don't hold the boot for a network that is not there yet; wpa_supplicant@wlan0 is started by udev
# (80-sunstone-wlan0.rules), not the D-Bus-only wpa_supplicant.service
chroot "$R" systemctl disable -q systemd-networkd-wait-online.service wpa_supplicant.service
# a root login on the ACM port too (host: /dev/ttyACM0)
chroot "$R" systemctl enable -q serial-getty@ttyGS0.service

# firewall: ssh in on any interface, DHCP from the USB host (networkd's DHCP server on usb0 gives it
# its address), nothing else in. While inactive, ufw only writes its rule files; ENABLED=yes loads
# them at boot. It needs the REJECT, hl and rt netfilter modules (kernel/sunstone.config).
chroot "$R" ufw --force reset >/dev/null
chroot "$R" ufw default deny incoming >/dev/null
chroot "$R" ufw default allow outgoing >/dev/null
chroot "$R" ufw allow 22/tcp comment ssh >/dev/null
chroot "$R" ufw allow in on usb0 to any port 67 proto udp comment 'DHCP for the USB host' >/dev/null
sed -i 's/^ENABLED=.*/ENABLED=yes/' "$R/etc/ufw/ufw.conf"
rm -f "$R"/etc/ufw/*.rules.[0-9]*

# journal into the kernel log, so it also reaches netconsole
install -d "$R/etc/systemd/journald.conf.d"
printf '[Journal]\nForwardToKMsg=yes\nMaxLevelKMsg=notice\n' > "$R/etc/systemd/journald.conf.d/kmsg.conf"

# repo-managed files (rootfs-overlay/), owned by root
cp -a "$SRC/rootfs-overlay/." "$R/"
(cd "$SRC/rootfs-overlay" && find . -mindepth 1) | sed "s|^\.|$R|" | xargs chown -h 0:0

# not a first boot (that would apply the presets to every unit)
[ -s "$R/etc/machine-id" ] || chroot "$R" systemd-machine-id-setup
rm -f "$R/usr/sbin/policy-rc.d"
chroot "$R" apt-get clean
echo "Ubuntu $SUITE in $R: $(chroot "$R" dpkg -l | grep -c '^ii') packages, $(du -sh "$R" | cut -f1)"
