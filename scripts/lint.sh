#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Static checks: shellcheck (busybox ash for device scripts, bash for host
# scripts), LuCI JavaScript syntax and JSON.  shellcheck runs from its
# container image unless SHELLCHECK points to a local binary (>= 0.10).
set -eu
cd "$(dirname "$0")/.."

ENGINE=${ENGINE:-$(command -v podman || command -v docker || true)}
if [ -n "${SHELLCHECK:-}" ]; then
	sc() { "$SHELLCHECK" "$@"; }
else
	sc() { "$ENGINE" run --rm -v "$PWD:/mnt:ro" -w /mnt docker.io/koalaman/shellcheck:v0.11.0 "$@"; }
fi

rc=0
echo "shellcheck: device scripts (busybox)"
sc -s busybox -f gcc \
	feed/modeswitch/files/modectl feed/modeswitch/files/lib.sh \
	feed/modeswitch/files/defaults/*.sh feed/modeswitch/files/modeswitch.init \
	feed/modeswitch/files/60-modeswitch feed/modeswitch/files/modeswitch.uci-defaults \
	files/etc/uci-defaults/* files/etc/hotplug.d/ieee80211/* tests/*.sh || rc=1
echo "shellcheck: host scripts (bash)"
sc -s bash -f gcc scripts/build.sh scripts/sdk-packages.sh || rc=1
sc -s sh -f gcc scripts/lint.sh || rc=1

echo "javascript"
tmp=$(mktemp)
for f in feed/luci-app-modeswitch/files/*.js feed/luci-app-modeswitch/files/preload/*.js; do
	# LuCI modules are function bodies (top-level "return")
	{ echo '(function() {'; cat "$f"; echo '});'; } > "$tmp.js"
	node --check "$tmp.js" || { echo "$f: syntax error"; rc=1; }
done
rm -f "$tmp" "$tmp.js"

echo "json"
for f in feed/luci-app-modeswitch/files/*.json tests/fixture/*.json; do
	python3 -m json.tool "$f" >/dev/null || { echo "$f: invalid JSON"; rc=1; }
done

[ $rc -eq 0 ] && echo "lint: ok"
exit $rc
