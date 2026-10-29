#!/bin/bash
# sunstone: Docker self-test, run on the phone as root (after M1892's m1892-docker-selftest list): bridge,
# DNS, custom network, published port, volume, bind mount, memory/cpu/io/pids limits, Compose, Buildx.
# Pulls alpine and busybox from Docker Hub; everything it makes is removed again, the two images too.
#   tools/ubuntu/docker-selftest.sh   (after tools/ubuntu/add-docker.sh; needs curl)
set -u
# alpine's busybox has no httpd: the servers use the busybox image
I=alpine:3.22; W=busybox:1.37; P=sunstone-dt; pass=0; fail=0
ok() { if [ "$2" = 0 ]; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1 ${3:-}"; fail=$((fail+1)); fi; }
cleanup() {
	docker rm -f $P-web $P-pub >/dev/null 2>&1; docker network rm $P-net >/dev/null 2>&1
	docker volume rm $P-vol >/dev/null 2>&1; rm -rf /tmp/$P
	(cd /tmp/$P-compose 2>/dev/null && docker compose down -v >/dev/null 2>&1); rm -rf /tmp/$P-compose /tmp/$P-build
	docker rmi -f $P-built:1 >/dev/null 2>&1; [ "${FINAL:-}" ] && docker rmi -f $I $W >/dev/null 2>&1; docker buildx prune -af >/dev/null 2>&1
}
cleanup
FINAL=1; trap cleanup EXIT
docker pull -q $I >/dev/null && docker pull -q $W >/dev/null; ok "pull $I, $W" $?
a=$(docker run --rm $I uname -m); [ "$a" = aarch64 ]; ok "run ($a)" $?
docker run --rm $I ping -c 2 -W 2 1.1.1.1 >/dev/null; ok "default bridge, outbound ping" $?
docker run --rm $I nslookup -timeout=3 deb.debian.org >/dev/null 2>&1; ok "default bridge, DNS" $?
docker network create $P-net >/dev/null && docker run -d --name $P-web --network $P-net $W \
	sh -c 'mkdir /w && echo hello-net > /w/index.html && httpd -f -p 80 -h /w' >/dev/null; sleep 1
r=$(docker run --rm --network $P-net $I wget -qO- http://$P-web/); [ "$r" = hello-net ]; ok "custom network, name resolution" $? "($r)"
# add-docker.sh makes 127.0.0.1 the default for published ports: -p PORT stays local, -p 0.0.0.0:PORT is open
docker run -d --name $P-pub -p 18080:80 -p 0.0.0.0:18081:80 $W sh -c 'mkdir /w && echo hello-port > /w/index.html && httpd -f -p 80 -h /w' >/dev/null; sleep 1
r=$(curl -s -m 3 http://127.0.0.1:18080/); [ "$r" = hello-port ]; ok "published port, from the host" $? "($r)"
wip=$(ip -4 -o addr show wlan0 | awk '{ split($4, a, "/"); print a[1]; exit }')
if grep -qs '"ip": *"127.0.0.1"' /etc/docker/daemon.json; then
	r=$(curl -s -m 3 http://$wip:18080/); [ -z "$r" ]; ok "published port without an address stays local (not on $wip)" $? "($r)"
fi
r=$(curl -s -m 3 http://$wip:18081/); [ "$r" = hello-port ]; ok "published port on 0.0.0.0, via the Wi-Fi address ($wip)" $? "($r)"
docker volume create $P-vol >/dev/null && docker run --rm -v $P-vol:/v $I sh -c 'echo vol-data > /v/f' &&
	r=$(docker run --rm -v $P-vol:/v $I cat /v/f); [ "$r" = vol-data ]; ok "named volume" $?
mkdir -p /tmp/$P && echo bind-data > /tmp/$P/f && r=$(docker run --rm -v /tmp/$P:/b $I sh -c 'cat /b/f; echo w > /b/g') &&
	[ "$r" = bind-data ] && [ -f /tmp/$P/g ]; ok "bind mount (read and write)" $?
r=$(docker run --rm --memory 32m $I cat /sys/fs/cgroup/memory.max); [ "$r" = 33554432 ]; ok "memory limit set ($r)" $?
docker run --rm --memory 32m --memory-swap 32m $I sh -c 'head -c 64m /dev/zero | tail >/dev/null'; rc=$?
[ $rc = 137 ]; ok "memory limit enforced (OOM kill, exit $rc)" $?
r=$(docker run --rm --cpus 0.5 $I cat /sys/fs/cgroup/cpu.max); [ "$r" = "50000 100000" ]; ok "cpu limit set ($r)" $?
r=$(docker run --rm --cpus 0.5 $I sh -c 'timeout 3 sh -c "while :; do :; done"; grep nr_throttled /sys/fs/cgroup/cpu.stat' | awk '{print $2}')
[ "${r:-0}" -gt 0 ]; ok "cpu limit enforced (nr_throttled $r)" $?
r=$(docker run --rm --device-read-bps /dev/sda:1mb $I cat /sys/fs/cgroup/io.max); case $r in *rbps=1048576*) true;; *) false;; esac
ok "io limit set ($r)" $?
r=$(docker run --rm --pids-limit 20 $I cat /sys/fs/cgroup/pids.max); [ "$r" = 20 ]; ok "pids limit ($r)" $?
mkdir -p /tmp/$P-compose && cat > /tmp/$P-compose/compose.yaml <<EOC
services:
  web:
    image: $W
    command: sh -c 'mkdir /w && echo hello-compose > /w/index.html && httpd -f -p 80 -h /w'
  client:
    image: $I
    depends_on: [web]
    command: sh -c 'sleep 1; wget -qO- http://web/'
EOC
r=$(cd /tmp/$P-compose && docker compose up --abort-on-container-exit --exit-code-from client 2>/dev/null | grep -o hello-compose)
[ "$r" = hello-compose ]; ok "compose (two services, service DNS)" $?
mkdir -p /tmp/$P-build && printf 'FROM %s\nRUN echo built > /built\nCMD ["cat", "/built"]\n' $I > /tmp/$P-build/Dockerfile
docker buildx build -q -t $P-built:1 --load /tmp/$P-build >/dev/null 2>&1 && r=$(docker run --rm $P-built:1); [ "${r:-}" = built ]
ok "buildx build + run" $?
echo "== $pass passed, $fail failed"
