#!/usr/bin/env bash
# Shared helpers for the OpenWRT build scripts.
#
# Resolves how to invoke Podman so the scripts work both from a normal host
# terminal (plain `podman`) and from inside the VS Code Flatpak sandbox, where
# the host binary is only reachable via `flatpak-spawn --host`.
set -euo pipefail

# Project root = parent of this scripts/ directory.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Build container, from Containerfile.modern.
MODERN_IMAGE="openwrt-builder-modern"

# Build MODERN_IMAGE, or rebuild it when Containerfile.modern differs from the
# one it was built from, whose sha256 is recorded in an image label.
ensure_modern_image() {
    local file="$PROJECT_DIR/Containerfile.modern" want have old
    want="$(sha256sum "$file" | cut -d' ' -f1)"
    have="$(podman_run image inspect --format '{{index .Labels "containerfile.sha256"}}' \
        "$MODERN_IMAGE" 2>/dev/null || true)"
    [ "$have" = "$want" ] && return 0

    old="$(podman_run image inspect --format '{{.Id}}' "$MODERN_IMAGE" 2>/dev/null || true)"
    echo "[*] Building container image '$MODERN_IMAGE' from Containerfile.modern ..."
    podman_run build --label "containerfile.sha256=$want" \
        -t "$MODERN_IMAGE" -f "$file" "$PROJECT_DIR"
    # The previous build is left untagged; remove it unless a container uses it.
    if [ -n "$old" ]; then podman_run rmi "$old" >/dev/null 2>&1 || true; fi
}
