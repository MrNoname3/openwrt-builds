#!/usr/bin/env bash
# Open an interactive shell inside the build container with the source tree
# mounted at /work. Use this for `make menuconfig` (phase 2: stripping packages)
# or manual debugging (`cd openwrt && make -j1 V=s`).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if ! podman_run image exists "$IMAGE_NAME"; then
    echo "[!] Image '$IMAGE_NAME' not found. Build it first: scripts/img-build.sh" >&2
    exit 1
fi

mkdir -p "$SRC_DIR"

podman_run run --rm -it \
    --userns=keep-id \
    -v "$SRC_DIR:/work:Z" \
    -v "$PROJECT_DIR/scripts:/opt/scripts:ro,Z" \
    -v "$PROJECT_DIR/config:/opt/config:ro,Z" \
    -w /work \
    "$IMAGE_NAME" \
    bash
