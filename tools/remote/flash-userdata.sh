#!/bin/bash
# One-shot on the test host: wait for fastboot, flash a sparse rootfs to userdata, wait until ABL
# answers again (the write is done), then hand over to wait-flash.sh for boot_a and the reboot.
#   flash-userdata.sh SIMG SHA256-PREFIX BOOTIMG BOOT-HASH TAG
P=${PLATFORM_TOOLS:?}
S=${1:?simg}; SH=${2:?hash}; B=${3:?boot image}; BH=${4:?boot hash}; TAG=${5:?tag}
[ "$(sha256sum "$S" | cut -c1-${#SH})" = "$SH" ] || { echo "STOP: rootfs hash mismatch"; exit 1; }
echo "$(date +%T) waiting for fastboot ($TAG)"
until timeout 15 $P/fastboot getvar current-slot 2>&1 | grep -q current-slot; do sleep 5; done
echo "$(date +%T) fastboot up, flashing userdata"
out=$($P/fastboot flash userdata "$S" 2>&1); echo "$out"
echo "$out" | grep -q "Finished" || { echo "STOP: userdata flash failed"; exit 1; }
for i in $(seq 120); do
	timeout 15 $P/fastboot getvar current-slot 2>&1 | grep -q current-slot && break
	sleep 5
done
timeout 15 $P/fastboot getvar current-slot 2>&1 | grep -q current-slot || { echo "$(date +%T) STOP: ABL not answering after the userdata flash"; exit 1; }
echo "$(date +%T) USERDATA-DONE, ABL answering"
exec bash "$(dirname "$0")/wait-flash.sh" "$B" "$BH" "$TAG"
