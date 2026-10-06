#!/usr/bin/env bash
# Build the custom 16MB OpenWrt image for the TL-WR941ND v4, then assemble the
# FULL 16MB flash image (u-boot + firmware + art) ready to write to the new chip
# with flashrom. Uses the modern (bookworm) build container.
#
# Normally invoked by scripts/build.sh, which resolves the OpenWrt version from
# the pin file (ci/*.env) and passes it in via OPENWRT_SRC_24 + BUILD_TAG. The
# "24"/"24.10" names below are historical -- this flow started on 24.10; the
# current pin is 25.12.x and any series works.
#
# Prereqs:
#   - an OpenWrt source tree at $SRC24, checked out at the pinned tag
#     (build.sh clones it and checks out the tag for you).
#   - A router backup under firmware/router-backup/<ts>/ (mtd0_u-boot.bin,
#     mtd4_art.bin) -- provides the device-unique u-boot + WiFi calibration.
#
# Usage:  scripts/build.sh          (preferred -- pin-driven)
#         scripts/build-16m.sh      (direct; set OPENWRT_SRC_24 + SEED_FILE)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SRC24="${OPENWRT_SRC_24:-$HOME/.local/share/openwrt-wr941nd/openwrt-24.10}"
OUT_SUB="bin/targets/ath79/tiny"
# Output subfolder under firmware/built/ -- override per version so a 25.12 build
# doesn't clobber the 24.10 full image (e.g. BUILD_TAG=16m-25.12).
BUILD_TAG="${BUILD_TAG:-16m-24.10}"

[ -d "$SRC24/.git" ] || { echo "[!] 24.10 source not found at $SRC24" >&2; exit 1; }

# 1. Modern build image --------------------------------------------------------
ensure_modern_image

# 2. Firmware build inside the container ---------------------------------------
echo "[*] Building firmware in container ..."
podman_run run --rm \
    --userns=keep-id \
    -v "$SRC24:/work:Z" \
    -v "$PROJECT_DIR/config:/opt/config:ro,Z" \
    -v "$PROJECT_DIR/scripts:/opt/scripts:ro,Z" \
    -e "JOBS=${JOBS:-}" \
    -e "SEED_FILE=${SEED_FILE:-}" \
    -w /work \
    "$MODERN_IMAGE" \
    bash /opt/scripts/_inner-build-16m.sh

# 3. Locate the built firmware images -----------------------------------------
# The build tree is persistent and `make` does not remove images from earlier
# builds, so a glob can match several files -- e.g. after the switch to
# version-numbered filenames, when the old openwrt-ath79-tiny-*.bin is still
# lying around. Picking one of those silently would be the worst outcome here:
# a stale image can end up inside the FULLFLASH that gets written to the chip.
# So: refuse to guess, and say exactly what to delete.
PICKED=""
pick_one() { # pick_one <description> <matches...>
    local what="$1"; shift
    PICKED=""
    [ $# -eq 0 ] && return 0
    if [ $# -gt 1 ]; then
        echo "[!] Several $what images in the build tree -- refusing to guess:" >&2
        printf '      %s\n' "$@" >&2
        echo "    Delete the stale ones from $SRC24/$OUT_SUB and re-run." >&2
        exit 1
    fi
    PICKED="$1"
}

shopt -s nullglob
pick_one factory    "$SRC24/$OUT_SUB"/*tl-wr941-v4-16m*factory.bin;    factory="$PICKED"
pick_one sysupgrade "$SRC24/$OUT_SUB"/*tl-wr941-v4-16m*sysupgrade.bin; sysupgrade="$PICKED"
shopt -u nullglob

[ -z "$factory" ] && [ -z "$sysupgrade" ] && { echo "[!] No tl-wr941-v4-16m factory/sysupgrade image found." >&2; exit 1; }
dest="$PROJECT_DIR/firmware/built/$BUILD_TAG"
mkdir -p "$dest"
for img in "$factory" "$sysupgrade"; do
    [ -n "$img" ] || continue
    echo "[i] Firmware image: $(basename "$img") ($(stat -c%s "$img") bytes)"
    cp -f "$img" "$dest/"
done

# 4. FULLFLASH (u-boot + firmware + art) -- only when a router backup exists.
#    The dumps are device-unique (MAC in u-boot, WiFi calibration in art) and
#    are NOT in git, so a fresh clone simply skips this step; the factory/
#    sysupgrade images above are all that sysupgrade-based updates need.
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
    echo "Next (only when you decide): write to the new chip with"
    echo "  flashrom -p ch341a_spi -c XT25F128B -w \"$full\""
    echo "(verify u-boot @0x0, firmware @0x20000, art @0xFF0000 first)."
fi
