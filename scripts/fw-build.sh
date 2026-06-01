#!/usr/bin/env bash
# Host-side wrapper: launches the 'openwrt-builder' container and runs the full
# firmware build inside it, with the source tree bind-mounted to project/src so
# it persists between runs.
#
# After a successful build the output images are collected into a per-build,
# LABELLED subfolder under firmware/built/ so a new build never overwrites an
# older one. Default label is "<version>-<timestamp>"; override with BUILD_LABEL.
#
# Usage:
#   scripts/fw-build.sh                # build with all CPU cores
#   JOBS=4 scripts/fw-build.sh         # limit parallelism
#   OPENWRT_TAG=v19.07.10 scripts/fw-build.sh        # try a different tag (phase 3)
#   BUILD_LABEL=ap-only scripts/fw-build.sh          # name the output folder
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

# --- Collect outputs into a labelled, non-overwriting subfolder ----------------
tag="${OPENWRT_TAG:-v18.06.9}"; tag="${tag#v}"
label="${BUILD_LABEL:-${tag}-$(date +%Y%m%d-%H%M%S)}"
dest="$PROJECT_DIR/firmware/built/$label"

mapfile -t artifacts < <(find "$SRC_DIR/openwrt/bin/targets" -type f \
    \( -name '*tl-wr941nd-v4*.bin' -o -name '*tl-wr941nd-v4*.manifest' \) 2>/dev/null)

if [ "${#artifacts[@]}" -eq 0 ]; then
    echo "[!] No tl-wr941nd-v4 artifacts found under bin/targets — did the build produce an image?" >&2
    exit 1
fi

mkdir -p "$dest"
cp -f "${artifacts[@]}" "$dest"/
echo
echo "[✓] Collected $(printf '%s\n' "${artifacts[@]}" | wc -l) artifact(s) into:"
echo "    firmware/built/$label/"
ls -lh "$dest"
