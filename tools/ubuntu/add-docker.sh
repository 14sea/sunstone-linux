#!/bin/bash
# Add Docker (docker.io with Compose v2 and Buildx) to an Ubuntu root built by build-rootfs.sh (DIR, or /
# on the running phone). The kernel options it needs are in kernel/sunstone.config (boot-193 on);
# tools/ubuntu/docker-selftest.sh checks the result on the phone.
# Published ports bind to 127.0.0.1 unless a -p names an address: Docker's own rules come before ufw's,
# so with the default 0.0.0.0 a -p 8080:80 was open on Wi-Fi and USB although ufw denies incoming
# (2026-10-29). To publish to the network, say so: -p 0.0.0.0:8080:80 (Compose: "0.0.0.0:8080:80").
#   add-docker.sh DIR
set -euo pipefail
R=${1:?usage: add-docker.sh DIR}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
in_root() { if [ "$R" = / ]; then "$@"; else chroot "$R" "$@"; fi; }

in_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker.io docker-compose-v2 docker-buildx
J=$R/etc/docker/daemon.json
if [ ! -e "$J" ]; then
	install -d "$R/etc/docker"
	printf '{\n\t"ip": "127.0.0.1"\n}\n' > "$J"
elif ! grep -q '"ip": *"127.0.0.1"' "$J"; then
	echo "$J exists without \"ip\": \"127.0.0.1\": add it by hand" >&2
	exit 1
fi
[ "$R" = / ] && systemctl restart docker
echo "Docker added; published ports default to 127.0.0.1"
