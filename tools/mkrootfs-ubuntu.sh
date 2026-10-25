#!/bin/bash
# Build the Ubuntu Server root filesystem on the phone itself (it runs Linux from this repository,
# arm64, with network), through the test host, and pack it here:
#   1. tools/ubuntu/build-rootfs.sh in /srv/ubuntu (debootstrap, packages, configuration, overlay)
#   2. the kernel modules of the m6 build (out/modules-m6)
#   3. MIGRATE=1 (default): this phone's state from the running system (tools/ubuntu/migrate-state.sh)
#   4. sunstone-fw-install inside the new root (firmware from the phone's own partitions)
#   5. an ext4 image of it (SIZE, default 8G) -> out/ubuntu-rootfs.img.zst and the test host's
#      ~/REMOTE_DIR/backup/ (private with MIGRATE=1: Wi-Fi PSKs, ssh host keys, EFS copies)
# The running system is not changed apart from /srv/ubuntu*, /root/sunstone-mkubuntu; installing
# the result on userdata is tools/install-rootfs.sh.
#   tools/mkrootfs-ubuntu.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
MIGRATE=${MIGRATE:-1}
SIZE=${SIZE:-8G}
R=/srv/ubuntu
D=/root/sunstone-mkubuntu
SSH="ssh -o BatchMode=yes $HOST"
PH="bash ~/$REMOTE_DIR/phone.sh"
[ -f "$HERE/authorized_keys" ] || { echo "tools/authorized_keys missing" >&2; exit 1; }
MODS=$ROOT/out/modules-m6/lib/modules
REL=$(ls "$MODS")

# the inputs, then the build as a transient unit (it outlives this ssh session)
tar -C "$ROOT" --owner=0 --group=0 --numeric-owner -cf - rootfs-overlay tools/ubuntu tools/authorized_keys |
	$SSH "$PH 'rm -rf $D && mkdir -p $D && tar -xf - -C $D && mv $D/tools/authorized_keys $D/'"
$SSH "$PH 'systemd-run --unit=sunstone-mkubuntu --collect sh -c \"bash $D/tools/ubuntu/build-rootfs.sh $R $D > $D/build.log 2>&1; echo EXIT \\\$? >> $D/build.log\"'"
echo "building in $R on the phone (log $D/build.log)"
until $SSH "$PH 'grep -q ^EXIT $D/build.log'" 2>/dev/null; do sleep 30; done
$SSH "$PH 'tail -3 $D/build.log'"
$SSH "$PH 'grep -qx \"EXIT 0\" $D/build.log'"

tar -C "$MODS" --owner=0 --group=0 --numeric-owner --exclude="$REL/build" --exclude="$REL/source" -cf - "$REL" |
	$SSH "$PH 'rm -rf $R/usr/lib/modules && mkdir -p $R/usr/lib/modules && tar -xf - -C $R/usr/lib/modules && echo modules $REL'"

[ "$MIGRATE" = 1 ] && $SSH "$PH 'bash $D/tools/ubuntu/migrate-state.sh / $R'"

$SSH "$PH 'for m in proc sys dev dev/pts run; do mount --bind /\$m $R/\$m; done
	chroot $R env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin sunstone-fw-install > $D/fw-install.log 2>&1; rc=\$?
	grep -v ^efs $D/fw-install.log; for m in run dev/pts dev sys proc; do umount $R/\$m; done; exit \$rc'"

# an ext4 image of it (mke2fs -d keeps owners, modes, xattrs and hard links), checked, compressed
# from the file (so zstd records its size) to the test host, and a copy here
I=/srv/ubuntu-rootfs.img
$SSH "$PH 'rm -f $I && mke2fs -q -t ext4 -L sunstone-root -E lazy_itable_init=0,lazy_journal_init=0 -d $R $I $SIZE &&
	e2fsck -fn $I >/dev/null && zstd -T8 -3 -q -c $I'" > "$ROOT/out/ubuntu-rootfs.img.zst"
zstd -tq "$ROOT/out/ubuntu-rootfs.img.zst"
$SSH "mkdir -p ~/$REMOTE_DIR/backup"
scp -q "$ROOT/out/ubuntu-rootfs.img.zst" "$HOST:$REMOTE_DIR/backup/ubuntu-rootfs.img.zst"
ls -l "$ROOT/out/ubuntu-rootfs.img.zst"
sha256sum "$ROOT/out/ubuntu-rootfs.img.zst"
