#!/bin/bash
# One experiment boot: flash out/boot-STAGE.img as boot N, stage RESTORE (default saved58) as
# boot N+1 for the next time the phone shows up in fastboot, then report whether the new kernel came
# up (ssh within WAIT seconds) and, if it did, the lines matching GREP from the kernel log.
#   tools/run-exp.sh STAGE N [RESTORE]      WAIT=60 GREP='...' tools/run-exp.sh e1a 59
# Exit status: 0 the new kernel runs (the restore is withdrawn again); 1 the flash did not happen
# (nothing staged); 2 no new kernel within WAIT (the restore stays staged). "New kernel" means a changed boot_id and a
# /proc/version equal to the version string in the image's kernel.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
STAGE=${1:?stage}; N=${2:?boot number}; RESTORE=${3:-saved58}
WAIT=${WAIT:-60}
GREP=${GREP:-'sunstone|probe: |prepare|dsi_err|tx failed|Initialized msm|fb[0-9]:|Run /init|latch'}
SSH="ssh -o BatchMode=yes $HOST"
PHONE="bash ~/$REMOTE_DIR/phone.sh"
LOG="~/$REMOTE_DIR/logs/flash-$N.log"

# the kernel version string the image carries (its SWEETLNX payload's Image)
want=$(python3 - "$ROOT/out/boot-$STAGE.img" <<'EOF'
import re, struct, sys
d = open(sys.argv[1], 'rb').read()
i = -1
while True:
    i = d.find(b'SWEETLNX', i + 1)
    if i < 0:
        sys.exit('no SWEETLNX payload')
    ver, hs = struct.unpack_from('<II', d, i + 8)
    if ver == 1 and hs < 4096:
        break
io, isz = struct.unpack_from('<QQ', d, i + 16)
# the full banner (with the build number and date); a placeholder without them comes first
full = [m for m in re.findall(rb'Linux version [^\n\0]+', d[i + io:i + io + isz]) if re.search(rb'#\d+ ', m)]
if not full:
    sys.exit('no kernel banner with a build number in the image')
print(full[0].decode().strip())
EOF
)

# a restore staged by an earlier run would race this flash: stop any waiting flasher first
$SSH 'for p in $(ps -eo pid,args | awk "/[w]ait-flash.sh images/{print \$1}"); do kill $p && echo "stopped a waiting flasher ($p)"; done'
old_boot=$($SSH "timeout 15 $PHONE 'cat /proc/sys/kernel/random/boot_id' </dev/null 2>/dev/null" || true)

"$HERE/flash.sh" "$STAGE" "$N" | tail -1
res=$($SSH "timeout 30 bash ~/$REMOTE_DIR/to-fastboot.sh </dev/null >/dev/null 2>&1; \
	for i in \$(seq 72); do sleep 5; grep -qE 'FLASHED-AND-REBOOTED|STOP|ERROR' $LOG 2>/dev/null && break; done; \
	tail -1 $LOG")
echo "$res"
case $res in
*FLASHED-AND-REBOOTED*) ;;
*)
	echo "boot-$N: the flash did not complete; the watcher, if still waiting, is stopped" >&2
	$SSH 'for p in $(ps -eo pid,args | awk "/[w]ait-flash.sh images/{print \$1}"); do kill $p; done' || true
	exit 1 ;;
esac

"$HERE/flash.sh" "$RESTORE" $((N + 1)) | tail -1
got=$($SSH "end=\$((SECONDS + $WAIT)); while [ \$SECONDS -lt \$end ]; do \
	b=\$(timeout 8 $PHONE 'cat /proc/sys/kernel/random/boot_id' </dev/null 2>/dev/null) && [ -n \"\$b\" ] && [ \"\$b\" != '$old_boot' ] && \
	{ timeout 8 $PHONE 'cut -d. -f1 /proc/uptime; cat /proc/version' </dev/null; exit 0; }; sleep 2; done; echo none")
if [ "$got" = none ]; then
	echo "boot-$N: NO NEW KERNEL after ${WAIT}s (restore boot-$((N + 1)) is staged)"
	exit 2
fi
up=$(head -1 <<<"$got"); version=$(sed -n 2p <<<"$got")
if [ "$version" != "$want" ]; then
	echo "boot-$N: a new boot, but not this image's kernel:" >&2
	echo "  running: $version" >&2
	echo "  image:   $want" >&2
	exit 2
fi
echo "boot-$N: up ${up}s, kernel as in the image"
# the restore is only for a boot that does not come up: withdraw it, or a later fastboot would flash it
$SSH 'for p in $(ps -eo pid,args | awk "/[w]ait-flash.sh images/{print \$1}"); do kill $p && echo "restore withdrawn ($p)"; done' 
$SSH "$PHONE 'dmesg | grep -E \"$GREP\" | grep -v \"Machine model\" | cut -c1-200' </dev/null"
