#!/bin/bash
# Fetch the firmware built into the kernel image (CONFIG_EXTRA_FIRMWARE, tools/build-kernel.sh) into
# downloads/firmware/, pinned by version and sha256: regulatory.db, which cfg80211 reads when it
# registers, before the root is mounted. The phone-specific firmware (modem, WLAN, zap shader) comes
# from its own partitions at run time (rootfs-overlay sunstone-fw-install) and is never built in.
#   tools/fetch-firmware.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D=$ROOT/downloads/firmware
REGDB=2026.09.03
REGDB_SHA256=b22e0901227b820cd1c280abe681a15b773a5103a5e10dc442e94ebb34cbf58d
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$D"

curl -sfL -o "$tmp/regdb.tar.xz" \
	"https://mirrors.edge.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-$REGDB.tar.xz"
echo "$REGDB_SHA256  $tmp/regdb.tar.xz" | sha256sum -c --quiet
tar -xJf "$tmp/regdb.tar.xz" -C "$tmp"
cp "$tmp/wireless-regdb-$REGDB/regulatory.db" "$tmp/wireless-regdb-$REGDB/regulatory.db.p7s" "$D/"
find "$D" -type f | sort | sed "s|^$ROOT/||"
