#!/usr/bin/env bash
# Reproducibility / supply-chain cross-check: compare two sysupgrade images of
# the SAME OpenWrt tag (e.g. a local podman build vs the GitHub CI release
# artifact). PASSes only when the images are byte-identical apart from the
# known-benign build-timestamp residue -- see _inner-repro-compare.sh for the
# exact whitelist and how it was established.
#
# Usage:  scripts/repro-compare.sh imageA-sysupgrade.bin imageB-sysupgrade.bin
set -euo pipefail
# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[ $# -eq 2 ] || { echo "usage: $0 <A-sysupgrade.bin> <B-sysupgrade.bin>" >&2; exit 1; }
A="$(realpath "$1")"; B="$(realpath "$2")"
if [ ! -f "$A" ] || [ ! -f "$B" ]; then echo "[!] input image not found" >&2; exit 1; fi

ensure_image

podman_run run --rm \
    --userns=keep-id \
    -v "$A:/cmp/A.bin:ro,Z" \
    -v "$B:/cmp/B.bin:ro,Z" \
    -v "$PROJECT_DIR/scripts:/opt/scripts:ro,Z" \
    "$IMAGE" \
    bash /opt/scripts/_inner-repro-compare.sh /cmp/A.bin /cmp/B.bin
