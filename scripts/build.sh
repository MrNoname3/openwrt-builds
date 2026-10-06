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
# correct rXXXXX revision), builds the firmware in the container and collects
# the images into firmware/built/16m-<version>/. When a router backup exists
# under firmware/router-backup/, it also assembles the full-chip FULLFLASH image
# (u-boot + firmware + art) for writing the new chip with flashrom.
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
    # Drop the injected device block; _inner-build.sh re-adds it fresh.
    git -C "$TREE" checkout -q -- target/linux/ath79/image/tiny-tp-link.mk 2>/dev/null || true
    if [ -n "$(git -C "$TREE" status --porcelain --untracked-files=no)" ]; then
        echo "[!] $TREE has local modifications; refusing to switch tags over them:" >&2
        git -C "$TREE" status --porcelain --untracked-files=no >&2
        exit 1
    fi
    git -C "$TREE" checkout -q "$OPENWRT_TAG"
fi
echo "[i] Tree now at: $(git -C "$TREE" describe --tags --always)"

# --- 4. Build in the container ------------------------------------------------
ensure_image
echo "[*] Building firmware in container ..."
podman_run run --rm \
    --userns=keep-id \
    -v "$TREE:/work:Z" \
    -v "$PROJECT_DIR/config:/opt/config:ro,Z" \
    -v "$PROJECT_DIR/scripts:/opt/scripts:ro,Z" \
    -e "JOBS=${JOBS:-}" \
    -e "SEED_FILE=$SEED_FILE" \
    -w /work \
    "$IMAGE" \
    bash /opt/scripts/_inner-build.sh

# --- 5. Collect the images -------------------------------------------------------
# The inner build clears this device's old images first, so exactly one of each
# must exist; anything else means the build did not produce what it should.
OUT="$TREE/bin/targets/ath79/tiny"
shopt -s nullglob
factories=("$OUT"/*tl-wr941-v4-16m*factory.bin)
sysupgrades=("$OUT"/*tl-wr941-v4-16m*sysupgrade.bin)
shopt -u nullglob
if [ ${#factories[@]} -ne 1 ] || [ ${#sysupgrades[@]} -ne 1 ]; then
    echo "[!] Expected one factory and one sysupgrade image in $OUT, found:" >&2
    printf '      %s\n' "${factories[@]}" "${sysupgrades[@]}" >&2
    exit 1
fi
factory="${factories[0]}"; sysupgrade="${sysupgrades[0]}"

# Rebuilding a version replaces its whole output, so no stale image or checksum
# from an earlier build of it is left next to the new ones.
dest="$PROJECT_DIR/firmware/built/16m-${OPENWRT_TAG#v}"
mkdir -p "$dest"
rm -f "$dest"/*.bin "$dest"/SHA256SUMS
for img in "$factory" "$sysupgrade"; do
    echo "[i] Firmware image: $(basename "$img") ($(stat -c%s "$img") bytes)"
    cp -f "$img" "$dest/"
done

# --- 6. FULLFLASH (u-boot + firmware + art), only when a router backup exists ----
# The dumps are device-unique (MAC in u-boot, WiFi calibration in art) and are
# not in git, so a fresh clone skips this; sysupgrade-based updates need only the
# images above.
bkdir="$(ls -d "$PROJECT_DIR"/firmware/router-backup/*/ 2>/dev/null | sort | tail -1 || true)"
if [ -n "$bkdir" ] && [ -f "$bkdir/mtd0_u-boot.bin" ] && ls "$bkdir"/mtd*art*.bin >/dev/null 2>&1; then
    uboot="$bkdir/mtd0_u-boot.bin"
    art="$(ls "$bkdir"/mtd*art*.bin 2>/dev/null | head -1)"
    echo "[i] Using backup: $bkdir"
    #   0x000000 u-boot | 0x020000 firmware | 0xFF0000 art ; gaps = 0xFF (erased).
    full="$dest/full16-wr941nd-v4.bin"
    echo "[*] Assembling $full (16 MB, 0xFF-filled) ..."
    head -c 16777216 /dev/zero | tr '\000' '\377' > "$full"
    dd if="$uboot"   of="$full" bs=64k seek=0        oflag=seek_bytes conv=notrunc status=none
    dd if="$factory" of="$full" bs=64k seek=131072   oflag=seek_bytes conv=notrunc status=none
    dd if="$art"     of="$full" bs=64k seek=16711680 oflag=seek_bytes conv=notrunc status=none
else
    full=""
    echo "[i] No router backup under firmware/router-backup/ -> skipping the"
    echo "    FULLFLASH image (only needed for flashrom chip writes; run"
    echo "    scripts/router-backup.sh on the machine that reaches the router)."
fi

( cd "$dest" && sha256sum ./*.bin > SHA256SUMS )

echo
echo "[✓] Build output in $dest:"
ls -lh "$dest"
if [ -n "$full" ]; then
    echo
    echo "To write the new chip (only when you decide):"
    echo "  flashrom -p ch341a_spi -c <chip> -w \"$full\""
    echo "(verify u-boot @0x0, firmware @0x20000, art @0xFF0000 first)."
fi
