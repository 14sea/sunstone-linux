#!/bin/bash
# On the test host: give the phone internet through this host without root. Sets the phone's
# clock (no RTC driver yet) and keeps a reverse SOCKS proxy open: phone 127.0.0.1:1080 -> here.
#   tunnel.sh            (foreground; run with nohup ... & to keep it)
# On the phone: all_proxy=socks5h://127.0.0.1:1080 pacman -Syu
HERE=$(cd "$(dirname "$0")" && pwd)
bash "$HERE/phone.sh" "date -s @$(date +%s) >/dev/null && date"
exec ssh -i ~/.ssh/sunstone_linux_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o LogLevel=error -o ExitOnForwardFailure=yes \
	-o ServerAliveInterval=15 -N -R 127.0.0.1:1080 root@192.168.7.2
