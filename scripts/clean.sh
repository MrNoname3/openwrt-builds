#!/usr/bin/env bash
# Wipe the OpenWRT build tree (the big, regenerable working dir that lives
# OUTSIDE the synced Documents folder). Does NOT touch the project files or the
# final binaries under firmware/. Optionally also removes the container image.
#
# After a full wipe the next ./scripts/fw-build.sh re-clones OpenWRT and rebuilds
# from scratch (re-download + full toolchain build, ~30-60 min).
#
# Usage:
#   scripts/clean.sh            # ask for confirmation, then remove the build tree
#   scripts/clean.sh -y         # no prompt (for scripts / "I'm sure")
#   scripts/clean.sh --image    # also remove the 'openwrt-builder' container image
#   scripts/clean.sh -y --image # both, no prompt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

ASSUME_YES=0
DROP_IMAGE=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)   ASSUME_YES=1 ;;
        --image)    DROP_IMAGE=1 ;;
        -h|--help)
            cat <<'USAGE'
clean.sh — wipe the regenerable OpenWRT build tree (outside Documents).
Keeps the project files and the final binaries under firmware/.

Usage:
  scripts/clean.sh             ask for confirmation, then remove the build tree
  scripts/clean.sh -y          no prompt
  scripts/clean.sh --image     also remove the 'openwrt-builder' container image
  scripts/clean.sh -y --image  both, no prompt
USAGE
            exit 0 ;;
        *) echo "[!] Unknown argument: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# --- Safety guards: never rm something dangerous ------------------------------
case "$SRC_DIR" in
    ""|"/"|"$HOME"|"$HOME/")
        echo "[!] Refusing to remove SRC_DIR='$SRC_DIR' (looks unsafe)." >&2
        exit 1 ;;
esac
if [ "$SRC_DIR" = "$PROJECT_DIR" ] || [ "$SRC_DIR" = "$PROJECT_DIR/" ]; then
    echo "[!] Refusing: SRC_DIR equals the project folder ('$PROJECT_DIR')." >&2
    exit 1
fi

if [ ! -e "$SRC_DIR" ]; then
    echo "[i] Build tree already gone: $SRC_DIR"
else
    size=$(du -sh "$SRC_DIR" 2>/dev/null | cut -f1)
    files=$(find "$SRC_DIR" -type f 2>/dev/null | wc -l)
    echo "About to PERMANENTLY remove the OpenWRT build tree:"
    echo "    path : $SRC_DIR"
    echo "    size : ${size:-?}   (${files} files)"
    echo "Kept untouched: project files + firmware/ binaries under $PROJECT_DIR"
    echo

    if [ "$ASSUME_YES" -ne 1 ]; then
        printf "Remove it? Type 'yes' to confirm: "
        read -r reply
        if [ "$reply" != "yes" ]; then
            echo "[i] Aborted, nothing removed."
            exit 0
        fi
    fi

    echo "[*] Removing $SRC_DIR ..."
    rm -rf "$SRC_DIR"
    echo "[✓] Build tree removed."
fi

# --- Optionally drop the container image --------------------------------------
if [ "$DROP_IMAGE" -eq 1 ]; then
    if podman_run image exists "$IMAGE_NAME"; then
        echo "[*] Removing container image '$IMAGE_NAME' ..."
        podman_run image rm "$IMAGE_NAME" >/dev/null
        echo "[✓] Image removed (rebuild it with ./scripts/img-build.sh)."
    else
        echo "[i] Container image '$IMAGE_NAME' not present."
    fi
fi

echo "[i] Done. Next build: ./scripts/img-build.sh (if image removed) then ./scripts/fw-build.sh"
