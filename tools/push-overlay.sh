#!/bin/bash
# Copy rootfs-overlay/ onto the running phone (as root:root) through the test host, then reload
# systemd and logind. mkrootfs.sh puts the same files into a fresh image.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
tar -C "$ROOT/rootfs-overlay" --owner=0 --group=0 --numeric-owner -cf - . |
	ssh -o BatchMode=yes "$HOST" "bash ~/$REMOTE_DIR/phone.sh 'tar -xf - -C / --numeric-owner --no-overwrite-dir && systemctl daemon-reload && systemctl kill -s HUP systemd-logind && echo overlay installed'"
