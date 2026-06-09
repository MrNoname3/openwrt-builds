#!/usr/bin/env bash
# Runs INSIDE the modern container, with the OpenWRT 24.10 tree mounted at /work.
# Injects the custom 16MB DTS + device definition, applies the seed config, and
# builds the firmware for the custom tplink_tl-wr941-v4-16m device.
#
# Mounts (provided by build-16m.sh):
#   /work        -> openwrt-24.10 source tree (read-write, persistent)
#   /opt/config  -> project config/ (read-only)
#   /opt/scripts -> project scripts/ (read-only)
set -euo pipefail

# Seed is overridable via SEED_FILE (e.g. wr941nd-v4-25.12-16m.seed.config for the
# 25.12/64MB build); defaults to the 24.10 seed.
SEED="/opt/config/${SEED_FILE:-wr941nd-v4-24.10-16m.seed.config}"
DTS_SRC="/opt/config/ath79-24.10/ar7240_tplink_tl-wr941-v4-16m.dts"
DEV_SRC="/opt/config/ath79-24.10/tplink_tl-wr941-v4-16m.device.mk"
PROFILE_SYM="CONFIG_TARGET_ath79_tiny_DEVICE_tplink_tl-wr941-v4-16m=y"
JOBS="${JOBS:-$(nproc)}"

cd /work
[ "$(id -u)" = "0" ] && { echo "[!] Running as root; OpenWRT won't build. Use --userns=keep-id." >&2; exit 1; }
echo "[i] OpenWRT: $(git describe --tags --always 2>/dev/null || echo unknown)"

# 1. Feeds --------------------------------------------------------------------
echo "[*] feeds update/install ..."
./scripts/feeds update -a
./scripts/feeds install -a

# 2. Inject custom DTS + device definition ------------------------------------
echo "[*] Injecting 16M DTS and device definition ..."
cp -f "$DTS_SRC" target/linux/ath79/dts/
mk=target/linux/ath79/image/tiny-tp-link.mk
# Refresh: drop any previously injected block, then append the current one, so
# edits to the device definition always take effect on rebuild.
sed -i '/# --- injected by build-16m.sh ---/,$d' "$mk"
{ echo; echo "# --- injected by build-16m.sh ---"; cat "$DEV_SRC"; } >> "$mk"

# 3. Config -------------------------------------------------------------------
echo "[*] Applying seed config + defconfig ..."
cp "$SEED" .config
make defconfig
if ! grep -q "$PROFILE_SYM" .config; then
    echo "[!] Device symbol not set: $PROFILE_SYM" >&2
    echo "    Check the device definition / DTS name." >&2
    exit 1
fi
echo "[✓] Device selected: tplink_tl-wr941-v4-16m"

# 4. Build --------------------------------------------------------------------
echo "[*] make download ..."; make "-j$JOBS" download
echo "[*] Building (first build is slow) ..."
if ! make "-j$JOBS"; then
    echo "[!] Parallel build failed; re-run verbosely: make -j1 V=s" >&2
    exit 1
fi

OUT=bin/targets/ath79/tiny
echo; echo "[✓] Build complete. Artifacts:"
ls -lh "$OUT"/*tl-wr941-v4-16m* 2>/dev/null || ls -lh "$OUT"
