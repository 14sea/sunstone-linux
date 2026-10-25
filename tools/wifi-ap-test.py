#!/usr/bin/env python3
"""Wi-Fi reconnect test: the phone joins a test AP (tools/esp8266-ap on this host's serial port), the
AP goes away for a while and comes back, and the time until the phone pings the AP again is measured.
The phone uses only the test AP during the test (wpa_cli, nothing written to its config) and goes back
to its normal network at the end (wpa_supplicant restart).
  AP_SSID=... AP_PASS=... [ESP_PORT=/dev/ttyUSBn] tools/wifi-ap-test.py [OFF_SECONDS ...]   default: 10 60 300
"""
import os, subprocess, sys, threading, time
import serial

HERE = os.path.dirname(os.path.abspath(__file__))
conf = dict(l.strip().split('=', 1) for l in open(os.path.join(HERE, 'host.conf'))
            if '=' in l and not l.startswith('#'))
HOST, RDIR = conf['HOST'].strip('"'), conf['REMOTE_DIR'].strip('"')
SSID, PASS = os.environ['AP_SSID'], os.environ['AP_PASS']
AP_IP = '192.168.4.1'
OFFS = [int(a) for a in sys.argv[1:]] or [10, 60, 300]

def phone(cmd, timeout=30):
	r = subprocess.run(['ssh', '-o', 'BatchMode=yes', HOST, f'bash ~/{RDIR}/phone.sh {q(cmd)}'],
			   capture_output=True, text=True, timeout=timeout)
	return r.stdout.strip()

def q(s):
	return "'" + s.replace("'", "'\\''") + "'"

def log(msg):
	print(time.strftime('%H:%M:%S'), msg, flush=True)

# the ESP: open without toggling DTR/RTS (that would reset it), print what it says
esp = serial.Serial()
esp.port, esp.baudrate, esp.timeout = os.environ.get('ESP_PORT', '/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0'), 115200, 0.2
esp.dtr = esp.rts = False
esp.open()
def reader():
	buf = b''
	while True:
		buf += esp.read(256)
		while b'\n' in buf:
			line, buf = buf.split(b'\n', 1)
			if line.strip():
				log('esp: ' + line.decode(errors='replace').strip())
threading.Thread(target=reader, daemon=True).start()
def ap(cmd):
	esp.write(cmd.encode() + b'\n')
	time.sleep(0.5)

def wait_ping(limit):
	"""seconds until the phone pings the AP, or None"""
	t0 = time.monotonic()
	while time.monotonic() - t0 < limit:
		if phone(f'ping -c 1 -W 1 -I wlan0 {AP_IP} >/dev/null 2>&1 && echo ok', 15) == 'ok':
			return time.monotonic() - t0
		time.sleep(1)
	return None

results = []
try:
	ap('on')
	ap('status')
	log('phone: use only the test AP')
	print(phone(f'n=$(wpa_cli -i wlan0 add_network) && wpa_cli -i wlan0 set_network $n ssid {q(chr(34) + SSID + chr(34))} >/dev/null && '
		    f'wpa_cli -i wlan0 set_network $n psk {q(chr(34) + PASS + chr(34))} >/dev/null && wpa_cli -i wlan0 select_network $n && echo network $n'))
	t = wait_ping(120)
	log(f'phone on the test AP after {t:.0f} s' if t is not None else 'phone did not join the test AP')
	if t is None:
		sys.exit(1)
	ap('status')
	for off in OFFS:
		log(f'--- AP off for {off} s')
		ap('off')
		time.sleep(off)
		ap('on')
		t = wait_ping(600)
		log(f'reconnect after {off} s off: ' + (f'{t:.0f} s' if t is not None else 'NO (600 s)'))
		results.append((off, t))
		print(phone('wpa_cli -i wlan0 status | grep -E "^(wpa_state|ssid|ip_address)="; ip -4 -o addr show wlan0 | awk "{print \\$4}"'))
		time.sleep(20)
finally:
	log('phone: back to the normal network')
	phone('journalctl -b -u wpa_supplicant@wlan0 -u systemd-networkd --since -40min --no-pager -o short-monotonic > /root/wifi-ap-test.journal; '
	      'systemctl restart wpa_supplicant@wlan0', 60)
	ap('off')
	gw = None
	for i in range(60):
		time.sleep(2)
		gw = phone('ip route | awk "/^default .*wlan0/ { print \\$3; exit }"')
		if gw and not gw.startswith('192.168.4.') and phone(f'ping -c 1 -W 1 {gw} >/dev/null && echo ok') == 'ok':
			break
		gw = None
	log('phone back on its network' if gw else 'phone NOT back on its network after 120 s')
	for off, t in results:
		print(f'off {off:4d} s -> ' + (f'reconnected in {t:.0f} s' if t is not None else 'no reconnect'))
