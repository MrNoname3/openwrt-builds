#!/usr/bin/env bash
# Shared helpers for the OpenWRT build scripts.
#
# Resolves how to invoke Podman so the scripts work both from a normal host
# terminal (plain `podman`) and from inside the VS Code Flatpak sandbox, where
# the host binary is only reachable via `flatpak-spawn --host`.
set -euo pipefail

# Project root = parent of this scripts/ directory.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/src"
IMAGE_NAME="openwrt-builder"

# PODMAN is an array so we can transparently prepend `flatpak-spawn --host`.
if command -v podman >/dev/null 2>&1; then
    PODMAN=(podman)
elif command -v flatpak-spawn >/dev/null 2>&1 && \
     flatpak-spawn --host podman --version >/dev/null 2>&1; then
    echo "[i] Running inside a Flatpak sandbox -> using 'flatpak-spawn --host podman'."
    PODMAN=(flatpak-spawn --host podman)
else
    echo "[!] Podman not found (neither directly nor via flatpak-spawn --host)." >&2
    echo "    Install/enable Podman on the host and retry." >&2
    exit 1
fi

podman_run() { "${PODMAN[@]}" "$@"; }
