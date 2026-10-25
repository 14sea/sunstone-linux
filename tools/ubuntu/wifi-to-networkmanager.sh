#!/bin/bash
# Hand wlan0 from systemd-networkd + wpa_supplicant@wlan0 to NetworkManager (so that a desktop's
# network settings work), on the running phone, as root. usb0 stays with networkd. The networks
# in wpa_supplicant-wlan0.conf become NetworkManager keyfiles (the derived PSKs move over; nothing
# is printed). Wi-Fi power save off, the DT's fixed MAC address, no random MAC while scanning.
#   wifi-to-networkmanager.sh            (back: wifi-to-networkmanager.sh --revert)
set -euo pipefail
NM=/etc/NetworkManager
CONF=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# networkd: the first .network file that matches an interface wins; this one keeps networkd off
# wlan0 and leaves rootfs-overlay's 20-wlan0.network in place
OFF=/etc/systemd/network/10-wlan0-networkmanager.network

if [ "${1:-}" = --revert ]; then
	systemctl disable -q --now NetworkManager.service wpa_supplicant.service
	systemctl mask -q NetworkManager.service
	rm -f "$OFF"
	systemctl unmask -q wpa_supplicant@wlan0.service
	networkctl reload
	systemctl start wpa_supplicant@wlan0.service
	echo "wlan0 back with networkd and wpa_supplicant@wlan0"
	exit 0
fi

install -d -m 755 $NM/conf.d $NM/system-connections
cat > $NM/conf.d/sunstone.conf <<'EOF'
# sunstone: NetworkManager runs wlan0 only; usb0 (the USB link to the test host) stays with
# systemd-networkd. The MAC address is the DT's fixed one, also while scanning; power save off
# (the phone is a server on permanent power).
[keyfile]
unmanaged-devices=interface-name:usb0

[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.cloned-mac-address=permanent
wifi.powersave=2
# the DHCP client ID is the (fixed) MAC address, so the router knows the phone whatever its system
# or network manager; a reservation for 02:53:4e:00:00:10 there keeps its address
ipv4.dhcp-client-id=mac
EOF

# networkd: wpa_supplicant-wlan0.conf -> one keyfile per network
python3 - "$CONF" "$NM/system-connections" <<'EOF'
import os, re, sys, uuid
conf, out = sys.argv[1], sys.argv[2]
text = open(conf).read()
for block in re.findall(r'network=\{(.*?)\}', text, re.S):
	kv = dict(re.findall(r'^\s*(\w+)=(.*?)\s*$', block, re.M))
	ssid = kv.get('ssid', '').strip('"')
	psk = kv.get('psk', '')
	if not ssid or not psk:
		continue
	name = re.sub(r'[^A-Za-z0-9._-]', '_', ssid)
	path = os.path.join(out, name + '.nmconnection')
	fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
	with os.fdopen(fd, 'w') as f:
		f.write(f"[connection]\nid={ssid}\nuuid={uuid.uuid4()}\ntype=wifi\ninterface-name=wlan0\nautoconnect=true\n\n"
			f"[wifi]\nmode=infrastructure\nssid={ssid}\n\n"
			f"[wifi-security]\nkey-mgmt=wpa-psk\npsk={psk.strip(chr(34))}\n\n"
			f"[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n")
	print('network -> keyfile written')
EOF

# wlan0 away from networkd and wpa_supplicant@wlan0 (masked: the udev rule wants it)
systemctl mask -q --now wpa_supplicant@wlan0.service
printf '# sunstone: NetworkManager runs wlan0 (tools/ubuntu/wifi-to-networkmanager.sh)\n[Match]\nName=wlan0\n\n[Link]\nUnmanaged=yes\n' > "$OFF"
networkctl reload
ip addr flush dev wlan0
# NetworkManager drives the D-Bus wpa_supplicant.service
systemctl unmask -q NetworkManager.service
systemctl enable -q wpa_supplicant.service NetworkManager.service
systemctl disable -q NetworkManager-wait-online.service 2>/dev/null || true
systemctl restart wpa_supplicant.service NetworkManager.service
for i in $(seq 40); do
	sleep 1
	ip -4 -o addr show wlan0 | grep -q inet && break
done
nmcli -t -f DEVICE,STATE,CONNECTION dev | grep -E '^(wlan0|usb0):' | sed -E 's/:[^:]*$/:…/'
