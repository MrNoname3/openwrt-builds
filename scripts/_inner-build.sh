#!/usr/bin/env bash
# Runs INSIDE the container. Clones OpenWRT at the 18.06.9 tag, applies the
# seed config, and builds the TL-WR941ND v4 (ar71xx/tiny) factory image.
#
# Idempotent: re-running reuses the existing source tree, downloads and build
# artifacts under /work, so only changed parts are rebuilt.
#
# Mounts provided by fw-build.sh:
#   /work        -> project/src   (read-write, persistent)
#   /opt/config  -> project/config (read-only)
set -euo pipefail

OPENWRT_TAG="${OPENWRT_TAG:-v18.06.9}"
# Which seed .config to apply (filename under /opt/config). Defaults to the
# stock-equivalent build; set SEED_FILE to pick another (e.g. the AP-only one).
SEED_CONFIG="/opt/config/${SEED_FILE:-wr941nd-v4-18.06.seed.config}"
PROFILE_SYM="CONFIG_TARGET_ar71xx_tiny_DEVICE_tl-wr941nd-v4=y"
JOBS="${JOBS:-$(nproc)}"

cd /work

# refuse root (OpenWRT buildroot does this too, but fail early with a clear msg)
if [ "$(id -u)" = "0" ]; then
    echo "[!] Running as root; OpenWRT buildroot will refuse to build." >&2
    echo "    Start the container with --userns=keep-id (see fw-build.sh)." >&2
    exit 1
fi

# 1. Source tree --------------------------------------------------------------
if [ ! -d openwrt/.git ]; then
    echo "[*] Cloning OpenWRT ($OPENWRT_TAG) ..."
    git clone --branch "$OPENWRT_TAG" --depth 1 \
        https://git.openwrt.org/openwrt/openwrt.git openwrt \
    || git clone --branch "$OPENWRT_TAG" --depth 1 \
        https://github.com/openwrt/openwrt.git openwrt
fi
cd openwrt
echo "[i] OpenWRT checkout: $(git describe --tags --always 2>/dev/null || echo unknown)"

# 2. Feeds --------------------------------------------------------------------
echo "[*] Updating & installing feeds ..."
./scripts/feeds update -a
./scripts/feeds install -a

# 2b. Optional clean -----------------------------------------------------------
# Changing packages that pull/drop KERNEL MODULES changes the kernel VERMAGIC.
# In an already-built tree that desyncs the kernel package from opkg and breaks
# package/install ("Cannot satisfy ... kernel (= <hash>)"). When switching to a
# config that alters the kernel, pass CLEAN=kernel (rebuild kernel + kmods) or
# CLEAN=all (full clean, keeps toolchain) to keep everything consistent.
case "${CLEAN:-}" in
    kernel) echo "[*] CLEAN=kernel -> make target/linux/clean"; make target/linux/clean; rm -rf tmp ;;
    all)    echo "[*] CLEAN=all -> make clean"; make clean; rm -rf tmp ;;
    "")     : ;;
    *)      echo "[!] Unknown CLEAN='$CLEAN' (use kernel|all)"; exit 2 ;;
esac

# 3. Config -------------------------------------------------------------------
echo "[*] Applying seed config and running 'make defconfig' ..."
cp "$SEED_CONFIG" .config
make defconfig

if ! grep -q "$PROFILE_SYM" .config; then
    echo "[!] Expected profile symbol not set: $PROFILE_SYM" >&2
    echo "    The device symbol name may differ in this checkout. Open an" >&2
    echo "    interactive shell (scripts/shell.sh) and run 'make menuconfig':" >&2
    echo "      Target System  -> Atheros AR7xxx/AR9xxx" >&2
    echo "      Subtarget      -> Devices with small flash (tiny)" >&2
    echo "      Target Profile -> TP-LINK TL-WR941N/ND v4" >&2
    exit 1
fi
echo "[✓] Target profile selected: TL-WR941ND v4 (ar71xx/tiny)."

# 4. Download then build ------------------------------------------------------
echo "[*] Pre-fetching package sources (make download, -j$JOBS) ..."
make "-j$JOBS" download

echo "[*] Building firmware (make -j$JOBS). First build can take 20-60 min ..."
if ! make "-j$JOBS"; then
    echo "[!] Parallel build failed. Re-run verbosely to see the real error:" >&2
    echo "      scripts/shell.sh   then   cd openwrt && make -j1 V=s" >&2
    exit 1
fi

# 5. Results ------------------------------------------------------------------
OUT_DIR="bin/targets/ar71xx/tiny"
echo
echo "[✓] Build complete. Output in src/openwrt/$OUT_DIR :"
ls -lh "$OUT_DIR"/*tl-wr941nd-v4* 2>/dev/null || ls -lh "$OUT_DIR"
