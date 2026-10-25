#!/bin/bash
# Carry this phone's own state from the running sunstone system (FROM, normally /) into a new root
# filesystem (TO), so the new system comes up as the same machine. None of it is in the repository:
#  - the modem's EFS copies (/var/lib/rmtfs, served by rmtfs-dir; the modem has written to them since
#    they were first taken from modemst1/2, fsg, fsc)
#  - the Wi-Fi networks (wpa_supplicant-wlan0.conf, derived PSKs) and the ssh host keys
#  - the RTC offset (/var/lib/rtc-offset)
#  - the machine ID: networkd's DHCP client identifier comes from it, so the router keeps the
#    phone's address (a new one got a new lease on the first Ubuntu boot)
# Firmware is not copied: run sunstone-fw-install in the new root afterwards, it reads the phone's
# partitions (and keeps the EFS copies already there).
#   migrate-state.sh FROM TO
set -euo pipefail
FROM=${1:?usage: migrate-state.sh FROM TO}
TO=${2:?usage: migrate-state.sh FROM TO}
[ -d "$FROM/var/lib/rmtfs" ] || { echo "no $FROM/var/lib/rmtfs" >&2; exit 1; }

mkdir -p "$TO/var/lib"
rm -rf "$TO/var/lib/rmtfs"
cp -a "$FROM/var/lib/rmtfs" "$TO/var/lib/rmtfs"
echo "efs: $(ls "$TO/var/lib/rmtfs" | tr '\n' ' ')"

# without the device identity key lines (dik, dik_cipher) a newer wpa_supplicant (Arch's 2.12) adds:
# an older one (Ubuntu's) rejects the whole file; the key is made again where it is supported
install -d -m 755 "$TO/etc/wpa_supplicant"
(umask 077; grep -v '^dik' "$FROM/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" > "$TO/etc/wpa_supplicant/wpa_supplicant-wlan0.conf")
echo "wifi: $(grep -c 'network={' "$TO/etc/wpa_supplicant/wpa_supplicant-wlan0.conf") network(s)"

for k in "$FROM"/etc/ssh/ssh_host_*_key; do
	install -m 600 "$k" "$TO/etc/ssh/"
	install -m 644 "$k.pub" "$TO/etc/ssh/"
done
echo "ssh host keys: $(cd "$TO/etc/ssh" && ls ssh_host_*_key | tr '\n' ' ')"

install -m 444 "$FROM/etc/machine-id" "$TO/etc/machine-id"
ln -sf /etc/machine-id "$TO/var/lib/dbus/machine-id"
echo "machine id: $(cut -c1-8 "$TO/etc/machine-id")..."

[ -s "$FROM/var/lib/rtc-offset" ] && cp -a "$FROM/var/lib/rtc-offset" "$TO/var/lib/rtc-offset" &&
	echo "rtc offset: $(cat "$TO/var/lib/rtc-offset") s"
true
