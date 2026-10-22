#!/bin/bash
# On the test host: send the phone's Linux into fastboot (reboot reason "bootloader"), e.g. so a
# staged image gets flashed by wait-flash.sh.
HERE=$(cd "$(dirname "$0")" && pwd)
bash "$HERE/phone.sh" "sync; systemctl reboot bootloader >/dev/null 2>&1 &" || true
