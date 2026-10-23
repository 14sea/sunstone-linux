#!/bin/bash
# One experiment boot: flash out/boot-STAGE.img as boot N, stage RESTORE (default saved58) as
# boot N+1 for the next time the phone shows up in fastboot, then report whether Linux came up
# (ssh within WAIT seconds) and, if it did, the lines matching GREP from the kernel log.
#   tools/run-exp.sh STAGE N [RESTORE]      WAIT=60 GREP='...' tools/run-exp.sh e1a 59
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
STAGE=${1:?stage}; N=${2:?boot number}; RESTORE=${3:-saved58}
WAIT=${WAIT:-60}
GREP=${GREP:-'sunstone|probe: |prepare|dsi_err|tx failed|Initialized msm|fb[0-9]:|Run /init|latch'}
SSH="ssh -o BatchMode=yes $HOST"
# a restore staged by an earlier run would race this flash: stop any waiting flasher first
$SSH 'for p in $(ps -eo pid,args | awk "/[w]ait-flash.sh images/{print \$1}"); do kill $p && echo "stopped a waiting flasher ($p)"; done'
"$HERE/flash.sh" "$STAGE" "$N" | tail -1
$SSH "bash ~/$REMOTE_DIR/to-fastboot.sh </dev/null >/dev/null 2>&1; for i in \$(seq 60); do sleep 5; grep -qE 'FLASHED|ERROR|STOP' ~/$REMOTE_DIR/logs/flash-$N.log 2>/dev/null && break; done; tail -1 ~/$REMOTE_DIR/logs/flash-$N.log"
"$HERE/flash.sh" "$RESTORE" $((N + 1)) | tail -1
up=$($SSH "end=\$((SECONDS + $WAIT)); while [ \$SECONDS -lt \$end ]; do u=\$(timeout 8 bash ~/$REMOTE_DIR/phone.sh 'cut -d. -f1 /proc/uptime' </dev/null 2>/dev/null) && [ -n \"\$u\" ] && { echo \$u; exit 0; }; sleep 2; done; echo none")
if [ "$up" = none ]; then
	echo "boot-$N: NO LINUX after ${WAIT}s (restore boot-$((N + 1)) is staged)"
	exit 2
fi
echo "boot-$N: up ${up}s"
$SSH "bash ~/$REMOTE_DIR/phone.sh 'dmesg | grep -E \"$GREP\" | grep -v \"Machine model\" | cut -c1-200' </dev/null"
