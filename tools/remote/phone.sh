#!/bin/bash
# On the test host: run a command on the phone over the USB network (key from M2).
#   phone.sh 'uname -a'
exec ssh -i ~/.ssh/sunstone_linux_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o LogLevel=error -o ConnectTimeout=10 root@192.168.7.2 "$@"
