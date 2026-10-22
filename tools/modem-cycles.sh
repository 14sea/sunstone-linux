#!/bin/bash
# Debug loop for the M5 modem stall: N reboot cycles; after each boot wait for the boot trace
# (sunstone-modem-trace) to finish and copy it to out/logs/modem-cycles/.
#   tools/modem-cycles.sh N
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
N=${1:-3}
OUT=$ROOT/out/logs/modem-cycles; mkdir -p "$OUT"
SSH="ssh -o BatchMode=yes $HOST"
PH="bash ~/$REMOTE_DIR/phone.sh"
for c in $(seq "$N"); do
	before=$($SSH "$PH 'ls /var/log/modem-trace | wc -l'" 2>/dev/null)
	$SSH "cd ~/$REMOTE_DIR && PLATFORM_TOOLS=~/$REMOTE_TOOLS bash reboot-cycle.sh" || { echo "cycle $c: reboot failed"; exit 1; }
	for i in $(seq 60); do
		sleep 10
		f=$($SSH "$PH 'n=\$(ls /var/log/modem-trace | wc -l); [ \$n -gt $before ] && f=\$(ls /var/log/modem-trace/*.log | tail -1) && grep -q \"^# tqftpserv\" \$f && echo \$f'" 2>/dev/null)
		[ -n "$f" ] && break
	done
	[ -z "$f" ] && { echo "cycle $c: no trace"; continue; }
	name=$(basename "$f")
	$SSH "$PH 'cat $f'" > "$OUT/$name"
	stalls=$(grep -c 'stalled initialization' "$OUT/$name")
	echo "cycle $c: $name stalls=$stalls"
done
