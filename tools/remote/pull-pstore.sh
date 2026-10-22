#!/bin/bash
# One-shot on the test host: wait for the phone in fastboot (or already in the recovery), boot the slot-b
# recovery, copy /sys/fs/pstore into DIR, then leave the phone in fastboot with slot a active.
#   pull-pstore.sh DIR
P=${PLATFORM_TOOLS:?}
D=${1:?dir}; mkdir -p "$D"
echo "$(date +%T) waiting for fastboot or adb recovery"
for i in $(seq 1 10080); do
	if $P/fastboot devices 2>/dev/null | grep -q fastboot && timeout 15 $P/fastboot getvar current-slot 2>&1 | grep -q current-slot; then
		$P/fastboot set_active b 2>&1 | head -1
		$P/fastboot reboot recovery 2>&1 | head -1
		echo "$(date +%T) fastboot -> slot b recovery"
		sleep 20
	fi
	if $P/adb devices 2>/dev/null | grep -q "recovery$"; then
		$P/adb root >/dev/null 2>&1; sleep 4; $P/adb wait-for-recovery
		$P/adb shell 'mountpoint -q /sys/fs/pstore || mount -t pstore pstore /sys/fs/pstore; ls -la /sys/fs/pstore' > "$D/ls.txt" 2>&1
		for f in $($P/adb shell 'ls /sys/fs/pstore' | tr -d '\r'); do
			$P/adb exec-out "cat /sys/fs/pstore/$f" > "$D/$f"
		done
		echo "$(date +%T) PULLED $(ls "$D" | tr '\n' ' ')"
		$P/adb reboot bootloader >/dev/null 2>&1
		for i in $(seq 1 30); do sleep 2; $P/fastboot devices 2>/dev/null | grep -q fastboot && break; done
		sleep 2
		$P/fastboot set_active a 2>&1 | head -1
		echo "$(date +%T) phone left in fastboot, slot a active"
		exit 0
	fi
	sleep 5
done
echo "$(date +%T) gave up"
