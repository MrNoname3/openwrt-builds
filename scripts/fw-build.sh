#!/usr/bin/env bash
# Host-side wrapper: launches the 'openwrt-builder' container and runs the full
# firmware build inside it, with the source tree bind-mounted to project/src so
# it persists between runs.
#
# Usage:
#   scripts/fw-build.sh                # build with all CPU cores
#   JOBS=4 scripts/fw-build.sh         # limit parallelism
#   OPENWRT_TAG=v19.07.10 scripts/fw-build.sh   # try a different tag (phase 3)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Make sure the image exists.
if ! podman_run image exists "$IMAGE_NAME"; then
    echo "[!] Image '$IMAGE_NAME' not found. Build it first: scripts/img-build.sh" >&2
    exit 1
fi

mkdir -p "$SRC_DIR"

echo "[*] Starting build container (rootless, --userns=keep-id) ..."
podman_run run --rm -it \
    --userns=keep-id \
    -v "$SRC_DIR:/work:Z" \
    -v "$PROJECT_DIR/scripts:/opt/scripts:ro,Z" \
    -v "$PROJECT_DIR/config:/opt/config:ro,Z" \
    -e "JOBS=${JOBS:-}" \
    -e "OPENWRT_TAG=${OPENWRT_TAG:-}" \
    -w /work \
    "$IMAGE_NAME" \
    bash /opt/scripts/_inner-build.sh
