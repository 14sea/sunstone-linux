#!/bin/bash
# Build the Arch Linux ARM root filesystem image for the userdata partition, without root:
# everything runs in one fakeroot session, so owners and device nodes survive into mke2fs -d.
#   tools/mkrootfs.sh [SIZE]      -> out/rootfs-arch.img (ext4, default 8G) + out/rootfs-arch.simg
# Input: downloads/alarm/ArchLinuxARM-aarch64-latest.tar.gz (md5 and GPG signature checked by hand,
# see LOG.md). The image is grown to the whole partition on the phone later (resize2fs).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIZE=${1:-8G}
TAR=$ROOT/downloads/alarm/ArchLinuxARM-aarch64-latest.tar.gz
WORK=$ROOT/out/rootfs
IMG=$ROOT/out/rootfs-arch.img
[ -f "$ROOT/tools/authorized_keys" ] || { echo "tools/authorized_keys missing" >&2; exit 1; }

rm -rf "$WORK" "$IMG"
mkdir -p "$WORK"
fakeroot -- bash -euo pipefail -s "$TAR" "$WORK" "$IMG" "$SIZE" "$ROOT" <<'EOF'
TAR=$1 R=$2 IMG=$3 SIZE=$4 ROOT=$5
tar -xpzf "$TAR" -C "$R" --numeric-owner 2>&1 | grep -v 'LIBARCHIVE.xattr' || true

# ssh: root with the test host's key (sshd's default PermitRootLogin is prohibit-password)
install -d -m 700 -o 0 -g 0 "$R/root/.ssh"
install -m 600 -o 0 -g 0 "$ROOT/tools/authorized_keys" "$R/root/.ssh/authorized_keys"

echo sunstone > "$R/etc/hostname"
echo 'PARTLABEL=userdata  /  ext4  rw,relatime  0 1' >> "$R/etc/fstab"

# USB network: the initramfs already configured the NCM gadget; networkd gives the phone
# 192.168.7.2 and hands the host 192.168.7.1 (as udhcpd did in M2), no route, no DNS
cat > "$R/etc/systemd/network/10-usb0.network" <<'NET'
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
NET
# don't hold the boot for a network that is not there yet
rm -f "$R/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

# a root login on the ACM port too (host: /dev/ttyACM0)
ln -sf /usr/lib/systemd/system/serial-getty@.service \
	"$R/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"

# journal into the kernel log, so it also reaches pstore
install -d "$R/etc/systemd/journald.conf.d"
printf '[Journal]\nForwardToKMsg=yes\nMaxLevelKMsg=info\n' > "$R/etc/systemd/journald.conf.d/kmsg.conf"

mke2fs -q -t ext4 -L sunstone-root -E lazy_itable_init=0,lazy_journal_init=0 -d "$R" "$IMG" "$SIZE"
EOF
e2fsck -fn "$IMG" >/dev/null
python3 "$ROOT/tools/img2simg.py" "$IMG" "${IMG%.img}.simg"
ls -l "$IMG" "${IMG%.img}.simg"
