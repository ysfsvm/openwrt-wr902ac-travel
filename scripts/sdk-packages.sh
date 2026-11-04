#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the feed packages (modeswitch, luci-app-modeswitch) with the OpenWrt
# SDK.  Runs inside ghcr.io/openwrt/sdk:ramips-mt76x8-<version> with this
# repository at /src; the packages are copied to /out.
set -euo pipefail
cd /builder
cp feeds.conf.default feeds.conf
echo "src-link wr902ac /src/feed" >> feeds.conf
./scripts/feeds update base packages luci wr902ac >/dev/null
./scripts/feeds install -p wr902ac -a >/dev/null
make defconfig >/dev/null
make -j"$(nproc)" package/modeswitch/compile package/luci-app-modeswitch/compile
mkdir -p /out
find bin/packages -name '*modeswitch*' -exec cp {} /out/ \;
ls -l /out
