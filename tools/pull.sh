#!/bin/bash
# Arm the pstore pull on the test host for boot BOOTNUM and wait for it; copies to out/logs/boot-N/.
#   tools/pull.sh BOOTNUM
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
N=${1:?boot number}
SSH="ssh -o BatchMode=yes $HOST"
scp -q "$HERE/remote/pull-pstore.sh" "$HOST:$REMOTE_DIR/"
$SSH "cd ~/$REMOTE_DIR && PLATFORM_TOOLS=~/$REMOTE_TOOLS nohup bash pull-pstore.sh logs/boot-$N > logs/pull-$N.log 2>&1 < /dev/null &"
until $SSH "grep -q 'PULLED\|gave up' ~/$REMOTE_DIR/logs/pull-$N.log" 2>/dev/null; do sleep 10; done
$SSH "cat ~/$REMOTE_DIR/logs/pull-$N.log"
mkdir -p "$ROOT/out/logs"
scp -q -r "$HOST:$REMOTE_DIR/logs/boot-$N" "$ROOT/out/logs/"
ls -la "$ROOT/out/logs/boot-$N"
