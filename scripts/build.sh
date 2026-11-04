#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the TL-WR902AC v3 image: OpenWrt v25.12.6 + patches/openwrt,
# files/, the local feed (feed/) and config/diffconfig.
#
#   scripts/build.sh [openwrt-dir]       (default: ./openwrt)
#
# Environment: OPENWRT_REF (default v25.12.6), JOBS (default: nproc),
# DOWNLOAD_ONLY=1 to stop after "make download".
set -euo pipefail

R=$(cd "$(dirname "$0")/.." && pwd)
B=${1:-$R/openwrt}
REF=${OPENWRT_REF:-$(cat "$R/config/openwrt-version")}
JOBS=${JOBS:-$(nproc)}
log() { echo "[$(date +%T)] $*"; }

if [ ! -d "$B/.git" ]; then
	log "clone openwrt $REF"
	git clone -q --depth 1 --branch "$REF" https://github.com/openwrt/openwrt.git "$B"
fi
cd "$B"

if ! git rev-parse -q --verify refs/heads/wr902ac >/dev/null; then
	log "apply patches/openwrt on $REF"
	git checkout -q -B wr902ac "$REF"
	git -c user.name=build -c user.email=build@localhost am -q --committer-date-is-author-date \
		"$R"/patches/openwrt/*.patch
fi

rm -rf files
cp -a "$R/files" files

log "feeds"
cp feeds.conf.default feeds.conf
echo "src-link wr902ac $R/feed" >> feeds.conf
./scripts/feeds update -a >/dev/null
./scripts/feeds install -a >/dev/null

log "config"
cp "$R/config/diffconfig" .config
make defconfig >/dev/null
for p in luci-app-modeswitch wpad-mbedtls px5g-mbedtls; do
	grep -q "^CONFIG_PACKAGE_$p=y" .config || { echo "config: $p is not selected" >&2; exit 1; }
done
for p in apk-mbedtls luci-app-package-manager odhcpd-ipv6only zram-swap; do
	! grep -q "^CONFIG_PACKAGE_$p=y" .config || { echo "config: $p must not be selected" >&2; exit 1; }
done

log "download"
make -j"$JOBS" download >/dev/null
[ -z "${DOWNLOAD_ONLY:-}" ] || exit 0

log "build"
make -j"$JOBS" || { log "parallel build failed, retrying with -j1 V=s"; make -j1 V=s; }
log "done"
ls -l bin/targets/ramips/mt76x8/*tl-wr902ac-v3*
