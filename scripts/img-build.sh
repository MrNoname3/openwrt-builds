#!/usr/bin/env bash
# Build the 'openwrt-builder' container image from the Containerfile.
# Run this once (and again only when the Containerfile changes).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

echo "[*] Building image '$IMAGE_NAME' from $PROJECT_DIR/Containerfile ..."
podman_run build -t "$IMAGE_NAME" -f "$PROJECT_DIR/Containerfile" "$PROJECT_DIR"
echo "[✓] Image '$IMAGE_NAME' ready. List with: podman images | grep $IMAGE_NAME"
