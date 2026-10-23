#!/bin/bash
# On the test host, for a soak test: once a minute ping the phone over Wi-Fi and run a command on
# it over ssh (Wi-Fi), one line per probe in logs/reach.log next to this script.
#   nohup bash reach-log.sh PHONE_WIFI_IP >/dev/null 2>&1 &
IP=${1:?phone Wi-Fi address}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/logs/reach.log
while :; do
	p=$(ping -c 1 -W 3 "$IP" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\) ms.*/\1/p')
	s=$(timeout 15 ssh -i ~/.ssh/sunstone_linux_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null -o LogLevel=error -o ConnectTimeout=10 "root@$IP" \
		'echo $(cut -c1-8 /proc/sys/kernel/random/boot_id) $(cut -d. -f1 /proc/uptime)' 2>/dev/null)
	echo "$(date -Is) ping=${p:-fail} ssh=${s:-fail}" >> "$OUT"
	sleep 60
done
