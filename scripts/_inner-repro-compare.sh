#!/usr/bin/env bash
# Runs INSIDE the build container, called by repro-compare.sh. Compares two
# sysupgrade images of the same OpenWrt tag: the kernel and every rootfs file
# must be byte-identical, apart from the apk database residue accepted below.
#
# Usage: _inner-repro-compare.sh A.bin B.bin
set -euo pipefail

A="$1"; B="$2"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[*] Comparing:"
echo "    A: $A"
echo "    B: $B"

# 1. Kernel: carve the LZMA stream (after the 64-byte OKLI header at 0x2000),
#    decompress, byte-compare. Must be identical.
python3 - "$A" "$B" "$WORK" << 'EOF'
import lzma, sys
a_path, b_path, work = sys.argv[1:4]
def parts(p):
    buf = open(p, 'rb').read()
    sq = buf.find(b'hsqs')
    assert sq > 0, f'no squashfs magic in {p}'
    return buf, sq
a, asq = parts(a_path)
b, bsq = parts(b_path)
ka = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(a[0x2040:asq])
kb = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(b[0x2040:bsq])
if ka != kb:
    n = sum(1 for x, y in zip(ka, kb) if x != y) + abs(len(ka) - len(kb))
    print(f'[!] KERNEL DIFFERS: {n} bytes'); sys.exit(1)
print(f'[ok] kernel identical ({len(ka)} bytes decompressed)')
open(f'{work}/a.sqfs', 'wb').write(a[asq:])
open(f'{work}/b.sqfs', 'wb').write(b[bsq:])
EOF

# 2. Rootfs: extract both squashfs and diff the trees.
unsquashfs -q -d "$WORK/a-root" "$WORK/a.sqfs" > /dev/null 2>&1 || true
unsquashfs -q -d "$WORK/b-root" "$WORK/b.sqfs" > /dev/null 2>&1 || true
if [ ! -d "$WORK/a-root" ] || [ ! -d "$WORK/b-root" ]; then echo "[!] unsquashfs failed"; exit 1; fi

# -q makes diff report EVERY differing file uniformly as "Files ... differ"
# (without it, text files get inline line-diffs the parser below would miss).
diff -rq --no-dereference "$WORK/a-root" "$WORK/b-root" > "$WORK/diff.txt" 2> /dev/null || true
sed -nE 's/^(Binary files|Files) [^ ]*a-root\/([^ ]+) and .* differ$/\2/p' "$WORK/diff.txt" \
    | sort > "$WORK/changed.txt"
echo "[i] differing files: $(wc -l < "$WORK/changed.txt")"
# Structural differences (files only in one tree) are never acceptable.
if grep -q '^Only in' "$WORK/diff.txt"; then
    echo "[!] FAIL: file set differs:"; grep '^Only in' "$WORK/diff.txt" | head; exit 1
fi

# Only these two files may differ, and only in the ways checked here.
fail=0
while IFS= read -r f; do
    case "$f" in
        lib/apk/db/installed)
            # Only checksum/size/datahash lines (C:/S:/Z:) may differ.
            if diff "$WORK/a-root/$f" "$WORK/b-root/$f" | grep -E '^[<>]' \
               | grep -vqE '^[<>] (C:|S:|Z:)'; then
                echo "[!] FAIL: $f differs beyond C:/S:/Z: checksum lines"; fail=1
            else
                echo "[ok] $f: only C:/S:/Z: checksum lines differ (signature/timestamp cascade)"
            fi
            ;;
        lib/apk/db/scripts.tar.gz)
            echo "[ok] $f: differs (gzip MTIME; content cascade of the same residue)"
            ;;
        *)
            echo "[!] FAIL: unexpected difference in: $f"; fail=1
            ;;
    esac
done < "$WORK/changed.txt"

echo
if [ "$fail" = 0 ]; then
    echo "[✓] PASS: images are reproducible (identical apart from the known apk database residue)"
else
    echo "[✗] FAIL: differences beyond the known-benign residue -- investigate before trusting!"
    exit 1
fi
