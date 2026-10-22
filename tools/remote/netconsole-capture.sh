#!/bin/bash
# On the test host, as root: append the phone's netconsole (UDP 6666 on the USB link) to
# logs/netconsole.log next to this script, across USB reconnects (the interface comes and goes
# with every phone reboot). tcpdump sees the packets even while the interface has no address yet.
IF=enx02534e000001
OUT=$(cd "$(dirname "$0")" && pwd)/logs/netconsole.log
while :; do
	if ip link show "$IF" >/dev/null 2>&1; then
		echo "=== $(date +%T) capture on $IF" >> "$OUT"
		tcpdump -i "$IF" -l -n -q -A 'udp port 6666' 2>/dev/null | grep --line-buffered -vE '^[0-9:.]+ IP |^E\.\.' >> "$OUT"
	fi
	sleep 1
done
