#!/usr/bin/env bash
# Pin-driven build entry point -- builds EXACTLY what the GitHub CI builds.
#
# The single source of truth for "what to build" is the per-device pin file
# ci/<device>.env (OPENWRT_TAG + SEED_FILE + DEVICE_NAME) -- the same file the
# CI reads. A fresh machine reproduces the CI build with:
#
#   git clone <this repo> && cd <repo> && ./scripts/build.sh
#
# It selects the device pin, ensures the OpenWrt source tree exists at the
# pinned tag (blobless clone: full commit graph, so getver.sh derives the
# correct rXXXXX revision), then delegates to build-16m.sh.
#
# Knobs (env vars -- no TTY needed):
#   DEVICE=<name>          device pin to use when several ci/*.env exist
#   TAG=vX.Y.Z             override the pinned OpenWrt tag
#   JOBS=N                 parallel build jobs (lower it if the build OOMs)
#   OPENWRT_SRC_ROOT=dir   where source trees live
#                          (default ~/.local/share/openwrt-wr941nd)
#   DRY_RUN=1              print the resolved plan and exit, changing nothing
#
# An interactive menu appears ONLY when several device pins exist, DEVICE is
# unset and stdin is a TTY; non-interactive callers get a fast failure that
# lists the exact DEVICE=... values instead.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# --- 1. Select the device pin -------------------------------------------------
shopt -s nullglob
envs=("$PROJECT_DIR"/ci/*.env)
[ ${#envs[@]} -gt 0 ] || { echo "[!] No device pin found under ci/." >&2; exit 1; }
if [ -n "${DEVICE:-}" ]; then
    ENV_FILE="$PROJECT_DIR/ci/$DEVICE.env"
    [ -f "$ENV_FILE" ] || { echo "[!] ci/$DEVICE.env not found." >&2; exit 1; }
elif [ ${#envs[@]} -eq 1 ]; then
    ENV_FILE="${envs[0]}"
elif [ -t 0 ]; then
    echo "Select a device to build:"
    names=(); for f in "${envs[@]}"; do names+=("$(basename "$f" .env)"); done
    select n in "${names[@]}"; do ENV_FILE="$PROJECT_DIR/ci/$n.env"; break; done
else
    echo "[!] Several device pins exist; pick one with DEVICE=<name>:" >&2
    for f in "${envs[@]}"; do echo "      DEVICE=$(basename "$f" .env) $0" >&2; done
    exit 2
fi

# --- 2. Load the pins ----------------------------------------------------------
OPENWRT_TAG=""; SEED_FILE=""; DEVICE_NAME=""
# shellcheck source=/dev/null
source "$ENV_FILE"
OPENWRT_TAG="${TAG:-$OPENWRT_TAG}"
[ -n "$OPENWRT_TAG" ] && [ -n "$SEED_FILE" ] || {
    echo "[!] $ENV_FILE must set OPENWRT_TAG and SEED_FILE." >&2; exit 1; }

series="${OPENWRT_TAG#v}"; series="${series%.*}" # v25.12.5 -> 25.12
SRC_ROOT="${OPENWRT_SRC_ROOT:-$HOME/.local/share/openwrt-wr941nd}"
TREE="$SRC_ROOT/openwrt-$series"

echo "[i] Device pin : ci/$(basename "$ENV_FILE") ($DEVICE_NAME)"
echo "[i] OpenWrt tag: $OPENWRT_TAG"
echo "[i] Seed       : $SEED_FILE"
echo "[i] Source tree: $TREE"
[ -n "${DRY_RUN:-}" ] && { echo "[i] DRY_RUN set -- stopping before any change."; exit 0; }

# --- 3. Ensure the source tree sits at the pinned tag ---------------------------
if [ ! -d "$TREE/.git" ]; then
    echo "[*] Cloning OpenWrt $OPENWRT_TAG (blobless) ..."
    mkdir -p "$SRC_ROOT"
    git clone --filter=blob:none --branch "$OPENWRT_TAG" \
        https://github.com/openwrt/openwrt.git "$TREE"
else
    git -C "$TREE" rev-parse -q --verify "refs/tags/$OPENWRT_TAG" >/dev/null 2>&1 \
        || git -C "$TREE" fetch --tags --quiet origin
    # Drop the injected device block; _inner-build-16m.sh re-adds it fresh.
    git -C "$TREE" checkout -q -- target/linux/ath79/image/tiny-tp-link.mk 2>/dev/null || true
    if [ -n "$(git -C "$TREE" status --porcelain --untracked-files=no)" ]; then
        echo "[!] $TREE has local modifications; refusing to switch tags over them:" >&2
        git -C "$TREE" status --porcelain --untracked-files=no >&2
        exit 1
    fi
    git -C "$TREE" checkout -q "$OPENWRT_TAG"
fi
echo "[i] Tree now at: $(git -C "$TREE" describe --tags --always)"

# --- 4. Delegate to the container build -----------------------------------------
export OPENWRT_SRC_24="$TREE" SEED_FILE BUILD_TAG="16m-${OPENWRT_TAG#v}"
exec "$PROJECT_DIR/scripts/build-16m.sh"
