#!/bin/bash
# On the test host: reboot the phone's Linux and wait until it is back in Linux. With the PON
# mode-normal (M5) a plain reboot comes straight back; if the phone still ends up in fastboot
# (older images, or the reason was not written), `fastboot reboot` gets it out.
#   reboot-cycle.sh
P=${PLATFORM_TOOLS:?}
HERE=$(cd "$(dirname "$0")" && pwd)
bash "$HERE/phone.sh" "sync; systemctl reboot >/dev/null 2>&1 &" || true
sleep 15
for i in $(seq 60); do
	if $P/fastboot devices 2>/dev/null | grep -q fastboot; then
		sleep 2; $P/fastboot reboot 2>&1 | tail -1; echo "(was in fastboot)"
	fi
	up=$(bash "$HERE/phone.sh" "cut -d. -f1 /proc/uptime" 2>/dev/null)
	if [ -n "$up" ] && [ "$up" -lt 300 ]; then echo "$(date +%T) REBOOTED (uptime ${up}s)"; exit 0; fi
	sleep 5
done
echo "STOP: phone not back"; exit 1
