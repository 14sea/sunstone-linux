#!/bin/bash
# Put a root filesystem image on the phone's userdata partition, replacing what is there:
#   1. flash the rescue image (out/boot-rescue.img, tools/mkboot.sh rescue) as boot N and boot it
#      (USB ssh, userdata not mounted), unless the rescue system is running already
#   2. write the image to the partition named userdata (checked by its GPT name) and read it back
#   3. write the boot image BOOT (default out/boot-saved.img) to boot_a and reboot into it
# The image lives on the test host (IMG there, zstd-compressed); the root grows to the whole partition
# at the first boot (x-systemd.growfs in its fstab).
#   tools/install-rootfs.sh N IMG.zst [BOOT]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
N=${1:?usage: install-rootfs.sh N IMG.zst [BOOT]}
IMG=${2:?usage: install-rootfs.sh N IMG.zst [BOOT]}
BOOT=${3:-$ROOT/out/boot-saved.img}
SSH="ssh -o BatchMode=yes $HOST"
PH="bash ~/$REMOTE_DIR/phone.sh"
$SSH "test -s $IMG" || { echo "no $IMG on the test host" >&2; exit 1; }
size=$($SSH "zstd -lv $IMG 2>/dev/null | awk '/Decompressed Size/ {gsub(/[(),]/, \"\"); print \$(NF-1)}'")
want=$($SSH "zstd -dc $IMG | sha256sum | cut -c1-64")
echo "image: $size bytes, sha256 ${want:0:16}"

rescue() { $SSH "timeout 10 $PH 'grep -qw sunstone.rescue /proc/cmdline' </dev/null" 2>/dev/null; }
if rescue; then
	echo "rescue system already running"
else
	"$HERE/flash.sh" rescue "$N" | tail -1
	$SSH "timeout 30 bash ~/$REMOTE_DIR/to-fastboot.sh </dev/null >/dev/null 2>&1; \
		for i in \$(seq 72); do sleep 5; grep -qE 'FLASHED-AND-REBOOTED|STOP|ERROR' ~/$REMOTE_DIR/logs/flash-$N.log && break; done; \
		tail -1 ~/$REMOTE_DIR/logs/flash-$N.log" | grep FLASHED-AND-REBOOTED
fi
for i in $(seq 60); do
	sleep 5
	rescue && break
done
rescue || { echo "rescue system not up" >&2; exit 1; }
echo "rescue system up"

# the target: the partition whose GPT name is userdata, not mounted
dev=$($SSH "$PH 'for p in /sys/class/block/sd*[0-9]; do grep -qx PARTNAME=userdata \$p/uevent && echo /dev/\${p##*/}; done; true'")
[ -n "$dev" ] && ! $SSH "$PH 'grep -q \"^$dev \" /proc/mounts'" || { echo "userdata not found or mounted" >&2; exit 1; }
echo "writing to $dev"
$SSH "zstd -dc $IMG | $PH 'dd of=$dev bs=4M conv=fsync 2>&1 | tail -1'"
got=$($SSH "$PH 'echo 3 > /proc/sys/vm/drop_caches; head -c $size $dev | sha256sum | cut -c1-64'")
[ "$got" = "$want" ] || { echo "read-back mismatch: $got" >&2; exit 1; }
echo "read back ok"

# the system's boot image to boot_a, then into it
bn=$(stat -c%s "$BOOT"); bh=$(sha256sum "$BOOT" | cut -c1-64)
scp -q "$BOOT" "$HOST:$REMOTE_DIR/images/sunstone-linux-$((N + 1))-boot.img"
$SSH "cat ~/$REMOTE_DIR/images/sunstone-linux-$((N + 1))-boot.img | $PH 'for p in /sys/class/block/sd*[0-9]; do \
	grep -qx PARTNAME=boot_a \$p/uevent && B=/dev/\${p##*/}; done; cat > /tmp/boot.img; \
	[ \$(stat -c%s /tmp/boot.img) = $bn ] && dd if=/tmp/boot.img of=\$B bs=1M conv=fsync 2>/dev/null && \
	echo 3 > /proc/sys/vm/drop_caches && [ \$(head -c $bn \$B | sha256sum | cut -c1-64) = $bh ] && echo boot_a written'"
$SSH "$PH 'sync; (sleep 1; reboot -f) >/dev/null 2>&1 &'"
echo "rebooting into the new root"
