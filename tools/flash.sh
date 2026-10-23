#!/bin/bash
# Stage out/boot-STAGE.img on the test host and arm a one-shot flasher (boot_a, slot a) for it.
#   tools/flash.sh STAGE BOOTNUM      e.g. tools/flash.sh m1 1
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
STAGE=${1:?stage}; N=${2:?boot number}
IMG=$ROOT/out/boot-$STAGE.img; NAME=sunstone-linux-$N-$STAGE.img
H=$(sha256sum "$IMG" | cut -c1-16)
SSH="ssh -o BatchMode=yes $HOST"
$SSH "mkdir -p ~/$REMOTE_DIR/images ~/$REMOTE_DIR/logs"
scp -q "$HERE/remote/wait-flash.sh" "$HERE/remote/pull-pstore.sh" "$HOST:$REMOTE_DIR/"
scp -q "$IMG" "$HOST:$REMOTE_DIR/images/$NAME"
[ "$($SSH "sha256sum ~/$REMOTE_DIR/images/$NAME" | cut -c1-16)" = "$H" ]
# cd first, in the foreground (a cd inside `cd && cmd &` would run in the background subshell
# under bash), then the watcher in the background; absolute log path, the watcher's PID reported
$SSH "cd ~/$REMOTE_DIR || exit 1; PLATFORM_TOOLS=~/$REMOTE_TOOLS nohup bash wait-flash.sh images/$NAME $H boot-$N > ~/$REMOTE_DIR/logs/flash-$N.log 2>&1 < /dev/null & echo \"watcher pid \$!\"; sleep 2; cat ~/$REMOTE_DIR/logs/flash-$N.log"
echo "staged $NAME $H; the watcher flashes it when the phone shows up in fastboot"
