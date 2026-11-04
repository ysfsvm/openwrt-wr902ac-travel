#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Run tests/modectl.sh in an OpenWrt rootfs container (podman or docker).
set -e
IMAGE=${IMAGE:-docker.io/openwrt/rootfs:x86-64-v25.12.6}
R=$(cd "$(dirname "$0")/.." && pwd)
E=${ENGINE:-$(command -v podman || command -v docker)}
exec "$E" run --rm -v "$R:/src:ro" "$IMAGE" sh /src/tests/modectl.sh
