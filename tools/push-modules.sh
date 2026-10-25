#!/bin/bash
# Copy the kernel modules of a build (out/modules-STAGE, tools/build-kernel.sh) to the running phone
# through the test host, into /usr/lib/modules/RELEASE (a merged /usr: /lib is a symlink there, so the
# archive holds usr/lib/modules and never touches /lib itself). Other releases on the phone are
# removed except the running kernel's.
#   tools/push-modules.sh [STAGE]      (default m6)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
. "$HERE/host.conf"
STAGE=${1:-m6}
D=$ROOT/out/modules-$STAGE/lib/modules
REL=$(ls "$D")
[ "$(echo "$REL" | wc -l)" = 1 ] || { echo "expected one release in $D: $REL" >&2; exit 1; }
# without build/source: they point into this host's build tree
tar -C "$D" --owner=0 --group=0 --numeric-owner --exclude="$REL/build" --exclude="$REL/source" --transform 's|^|usr/lib/modules/|' -cf - "$REL" |
	ssh -o BatchMode=yes "$HOST" "bash ~/$REMOTE_DIR/phone.sh 'run=\$(uname -r); cd /usr/lib/modules 2>/dev/null &&
		for r in *; do [ \"\$r\" = \"\$run\" ] || [ \"\$r\" = \"$REL\" ] || rm -rf \"\$r\"; done;
		tar -xf - -C / --numeric-owner --no-overwrite-dir && echo \"modules $REL installed (running \$run)\"'"
