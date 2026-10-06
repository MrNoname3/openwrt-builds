#!/usr/bin/env bash
# Shared helpers for the build scripts. Podman is called directly, or through
# `flatpak-spawn --host` from the VS Code Flatpak sandbox.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

IMAGE="openwrt-builder"

# Build IMAGE, or rebuild it when the Containerfile differs from the one it was
# built from (its sha256 is recorded in an image label).
ensure_image() {
    local file="$PROJECT_DIR/Containerfile" want have old
    want="$(sha256sum "$file" | cut -d' ' -f1)"
    have="$(podman_run image inspect --format '{{index .Labels "containerfile.sha256"}}' \
        "$IMAGE" 2>/dev/null || true)"
    [ "$have" = "$want" ] && return 0

    old="$(podman_run image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || true)"
    echo "[*] Building container image '$IMAGE' from Containerfile ..."
    podman_run build --label "containerfile.sha256=$want" \
        -t "$IMAGE" -f "$file" "$PROJECT_DIR"
    # The previous build is left untagged; remove it unless a container uses it.
    if [ -n "$old" ]; then podman_run rmi "$old" >/dev/null 2>&1 || true; fi
}
