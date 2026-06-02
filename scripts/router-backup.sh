#!/usr/bin/env bash
# Back up the running router's flash (mtd partitions) over SSH -- no chip readout
# needed. Reading /dev/mtdN is non-destructive. Captures u-boot, ART/calibration,
# firmware, config etc. plus the partition map -- exactly what phase 3 (16MB flash
# transplant) needs (ART is device-unique!).
#
# Does RUNS (default 3) independent dump passes and cross-checks them by sha256.
# NOR flash reads are deterministic, so all passes must match; if they do, only
# ONE canonical set is kept. A concatenated full-flash.bin is also produced.
#
# Usage:
#   scripts/router-backup.sh [HOST_ALIAS] [OUTBASE]
#     HOST_ALIAS  ssh host/alias       (default: tplink-router)
#     OUTBASE     output base dir      (default: <project>/firmware/router-backup)
#   RUNS=3 scripts/router-backup.sh           # number of cross-check passes
set -euo pipefail

HOST="${1:-tplink-router}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTBASE="${2:-$PROJECT_DIR/firmware/router-backup}"
RUNS="${RUNS:-3}"

# Old Dropbear (<=2017.75) only has an ssh-rsa/SHA-1 host key; on modern OpenSSL
# (e.g. Fedora) that needs SHA-1 signatures re-enabled. Use the scoped config if
# present (harmless on newer firmware that doesn't need it).
SHA1CONF="$HOME/.ssh/openssl-allow-sha1.cnf"
[ -f "$SHA1CONF" ] && export OPENSSL_CONF="$SHA1CONF"

SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10
     -o HostkeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa)

ts="$(date +%Y%m%d-%H%M%S)"
dest="$OUTBASE/$ts"
mkdir -p "$dest"

echo "[*] Target: $HOST   ->   $dest   (RUNS=$RUNS)"

# --- Connectivity + metadata --------------------------------------------------
echo "[*] Reading partition map and device info ..."
"${SSH[@]}" "$HOST" '
    echo "### /proc/mtd"; cat /proc/mtd
    echo "### /etc/openwrt_release"; cat /etc/openwrt_release 2>/dev/null
    echo "### uname"; uname -a
    echo "### /proc/cpuinfo"; cat /proc/cpuinfo
    echo "### df"; df -h
    echo "### dmesg-flash"; dmesg | grep -iE "spi|flash|mtd|m25p|w25q|nor" | head -40
    echo "### mtd-geom"
    for d in /sys/class/mtd/mtd*; do
        if [ -e "$d/offset" ]; then echo "$(basename "$d") $(cat "$d/offset") $(cat "$d/size")"; fi
    done
    true
' > "$dest/device-info.txt" 2>"$dest/ssh-err.txt" || true

if ! grep -q '^mtd[0-9]' "$dest/device-info.txt" 2>/dev/null; then
    echo "[!] Could not read /proc/mtd over SSH. ssh stderr:"; cat "$dest/ssh-err.txt" 2>/dev/null
    echo "    Hint: does 'ssh-legacy $HOST uptime' work?"; exit 1
fi
rm -f "$dest/ssh-err.txt"

# Parse "mtdN: <hexsize> <hexerase> \"name\""
mapfile -t MTDS < <(grep -E '^mtd[0-9]+:' "$dest/device-info.txt")
if [ "${#MTDS[@]}" -eq 0 ]; then
    echo "[!] No mtd partitions found in /proc/mtd." >&2; exit 1
fi
echo "[i] Partitions found:"; printf '    %s\n' "${MTDS[@]}"

idxs=(); names=()
for line in "${MTDS[@]}"; do
    idx="$(echo "$line" | sed -E 's/^mtd([0-9]+):.*/\1/')"
    name="$(echo "$line" | sed -E 's/.*"([^"]*)".*/\1/')"
    idxs+=("$idx"); names+=("$name")
done

# --- Dump passes --------------------------------------------------------------
for r in $(seq 1 "$RUNS"); do
    rd="$dest/run$r"; mkdir -p "$rd"
    echo "[*] Pass $r/$RUNS ..."
    for k in "${!idxs[@]}"; do
        i="${idxs[$k]}"; n="${names[$k]}"
        out="$rd/mtd${i}_${n//[^A-Za-z0-9._-]/_}.bin"
        "${SSH[@]}" "$HOST" "cat /dev/mtd$i" > "$out"
        printf '      mtd%s %-12s %8s bytes\n' "$i" "$n" "$(stat -c%s "$out")"
    done
    ( cd "$rd" && sha256sum *.bin > SHA256SUMS )
done

# --- Cross-check passes -------------------------------------------------------
echo "[*] Comparing the $RUNS passes ..."
consistent=1
if [ "$RUNS" -gt 1 ]; then
    for r in $(seq 2 "$RUNS"); do
        if ! diff -q "$dest/run1/SHA256SUMS" "$dest/run$r/SHA256SUMS" >/dev/null; then
            echo "[!] Pass $r differs from pass 1 — flash read NOT stable!"; consistent=0
        fi
    done
fi

if [ "$consistent" -eq 1 ]; then
    echo "[✓] All $RUNS passes identical. Keeping ONE canonical set."
    mv "$dest"/run1/*.bin "$dest"/run1/SHA256SUMS "$dest"/
    rm -rf "$dest"/run*

    # Rebuild the TRUE full-chip image from sysfs offsets/sizes. Partitions can
    # overlap (e.g. "firmware" == kernel+rootfs), so we place each partition at
    # its real offset into a chip-sized image; overlaps write identical bytes.
    chip=0
    declare -A OFF
    while read -r m off sz; do
        [ -z "${m:-}" ] && continue
        OFF["$m"]="$off"
        end=$(( off + sz )); [ "$end" -gt "$chip" ] && chip="$end"
    done < <(sed -n '/^### mtd-geom/,$p' "$dest/device-info.txt" | grep -E '^mtd[0-9]+ ')

    if [ "$chip" -gt 0 ]; then
        echo "[*] Reconstructing full-flash.bin ($chip bytes) from partition offsets ..."
        truncate -s "$chip" "$dest/full-flash.bin"
        for k in "${!idxs[@]}"; do
            i="${idxs[$k]}"; n="${names[$k]}"
            off="${OFF[mtd$i]:-}"; [ -z "$off" ] && continue
            f="$dest/mtd${i}_${n//[^A-Za-z0-9._-]/_}.bin"
            dd if="$f" of="$dest/full-flash.bin" bs=64k seek="$off" oflag=seek_bytes conv=notrunc status=none
        done
        echo "[i] full-flash.bin: $(stat -c%s "$dest/full-flash.bin") bytes ($(( chip/1024/1024 )) MB)"
    else
        echo "[!] No sysfs offsets — skipping full-flash.bin (per-partition dumps are complete)."
    fi
    ( cd "$dest" && sha256sum *.bin > SHA256SUMS )
else
    echo "[!] Passes NOT identical — keeping all runs for inspection (nothing deleted)."
fi

echo
echo "[✓] Backup at: $dest"
ls -lh "$dest"
echo
echo "IMPORTANT: the ART/calibration partition is device-unique (WiFi radio cal)."
echo "Keep this backup safe — it is needed for the 16MB flash transplant (phase 3)."
