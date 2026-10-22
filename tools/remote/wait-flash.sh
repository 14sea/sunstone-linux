#!/bin/bash
# One-shot on the test host: wait (up to 14 h) for the phone in fastboot, flash IMG to boot_a, slot a, reboot.
#   wait-flash.sh IMG SHA256-PREFIX TAG
P=${PLATFORM_TOOLS:?}
I=${1:?image}; WANT=${2:?hash prefix}; TAG=${3:?tag}
echo "$(date +%T) waiting for fastboot ($TAG)"
[ "$(sha256sum "$I" | cut -c1-${#WANT})" = "$WANT" ] || { echo "STOP: image hash mismatch"; exit 1; }
for i in $(seq 1 10080); do
	if $P/fastboot devices 2>/dev/null | grep -q fastboot; then
		sleep 3
		if timeout 15 $P/fastboot getvar current-slot 2>&1 | grep -q "current-slot"; then
			echo "$(date +%T) fastboot up"
			out=$($P/fastboot flash boot_a "$I" 2>&1); echo "$out"
			echo "$out" | grep -q "Writing 'boot_a'.*OKAY" || { echo "STOP: flash failed, not rebooting"; exit 1; }
			$P/fastboot set_active a 2>&1 | head -1
			$P/fastboot reboot 2>&1 | head -1
			echo "$(date +%T) FLASHED-AND-REBOOTED $TAG"
			exit 0
		fi
	fi
	sleep 5
done
echo "$(date +%T) gave up"
