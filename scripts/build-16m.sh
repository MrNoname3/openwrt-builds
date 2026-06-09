#!/usr/bin/env bash
# Phase 3: build a custom 16MB OpenWRT 24.10 image for the TL-WR941ND v4, then
# assemble the FULL 16MB flash image (u-boot + firmware + art) ready to write to
# the new chip with flashrom. Uses the modern (bookworm) build container.
#
# Prereqs:
#   - OpenWRT 24.10 source at $SRC24 (cloned separately).
#   - A router backup under firmware/router-backup/<ts>/ (mtd0_u-boot.bin,
#     mtd4_art.bin) -- provides the device-unique u-boot + WiFi calibration.
#
# Usage:  scripts/build-16m.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

MODERN_IMAGE="openwrt-builder-modern"
SRC24="${OPENWRT_SRC_24:-$HOME/.local/share/openwrt-wr941nd/openwrt-24.10}"
OUT_SUB="bin/targets/ath79/tiny"
# Output subfolder under firmware/built/ -- override per version so a 25.12 build
# doesn't clobber the 24.10 full image (e.g. BUILD_TAG=16m-25.12).
BUILD_TAG="${BUILD_TAG:-16m-24.10}"

[ -d "$SRC24/.git" ] || { echo "[!] 24.10 source not found at $SRC24" >&2; exit 1; }

# 1. Modern build image --------------------------------------------------------
if ! podman_run image exists "$MODERN_IMAGE"; then
    echo "[*] Building modern container image '$MODERN_IMAGE' ..."
    podman_run build -t "$MODERN_IMAGE" -f "$PROJECT_DIR/Containerfile.modern" "$PROJECT_DIR"
fi

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

# 3. Locate the built firmware image ------------------------------------------
factory="$(ls "$SRC24/$OUT_SUB"/*tl-wr941-v4-16m*factory.bin 2>/dev/null | head -1 || true)"
[ -z "$factory" ] && factory="$(ls "$SRC24/$OUT_SUB"/*tl-wr941-v4-16m*sysupgrade.bin 2>/dev/null | head -1 || true)"
[ -z "$factory" ] && { echo "[!] No tl-wr941-v4-16m factory/sysupgrade image found." >&2; exit 1; }
echo "[i] Firmware image: $(basename "$factory") ($(stat -c%s "$factory") bytes)"

# 4. Backup parts (u-boot + art) ----------------------------------------------
bkdir="$(ls -d "$PROJECT_DIR"/firmware/router-backup/*/ 2>/dev/null | sort | tail -1 || true)"
[ -z "$bkdir" ] && { echo "[!] No router backup found (run scripts/router-backup.sh first)." >&2; exit 1; }
uboot="$bkdir/mtd0_u-boot.bin"
art="$(ls "$bkdir"/mtd*art*.bin 2>/dev/null | head -1)"
[ -f "$uboot" ] && [ -f "$art" ] || { echo "[!] u-boot/art dump missing in $bkdir" >&2; exit 1; }
echo "[i] Using backup: $bkdir"

# 5. Assemble the full 16MB flash image ---------------------------------------
#   0x000000 u-boot | 0x020000 firmware | 0xFF0000 art ; gaps = 0xFF (erased).
dest="$PROJECT_DIR/firmware/built/$BUILD_TAG"
mkdir -p "$dest"
full="$dest/full16-wr941nd-v4.bin"
echo "[*] Assembling $full (16 MB, 0xFF-filled) ..."
head -c 16777216 /dev/zero | tr '\000' '\377' > "$full"
dd if="$uboot"   of="$full" bs=64k seek=0        oflag=seek_bytes conv=notrunc status=none
dd if="$factory" of="$full" bs=64k seek=131072   oflag=seek_bytes conv=notrunc status=none
dd if="$art"     of="$full" bs=64k seek=16711680 oflag=seek_bytes conv=notrunc status=none
cp -f "$factory" "$dest/"
( cd "$dest" && sha256sum ./*.bin > SHA256SUMS )

echo
echo "[✓] Full 16MB image: $full ($(stat -c%s "$full") bytes)"
ls -lh "$dest"
echo
echo "Next (only when you decide): write to the new chip with"
echo "  flashrom -p ch341a_spi -c XT25F128B -w \"$full\""
echo "(verify u-boot @0x0, firmware @0x20000, art @0xFF0000 first)."
