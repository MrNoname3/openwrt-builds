#!/usr/bin/env bash
# Reproducibility / supply-chain cross-check of two sysupgrade images of the
# same OpenWrt tag (e.g. a local build and the Release asset). Passes only when
# they are byte-identical apart from the residue whitelisted in
# _inner-repro-compare.sh.
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
