#!/bin/sh
# Tag the pinned OpenWrt version for release and push the tag to origin, from
# where the mirror forwards it to the GitHub release build. Run on master after
# a bump PR is merged; it fast-forwards to origin/master itself.
#
# Usage: scripts/tag-release.sh [ci/<device>.env]   (default: the only *.env)
set -eu
cd "$(dirname "$0")/.."

ENV_FILE=${1:-}
if [ -z "$ENV_FILE" ]; then
    set -- ci/*.env
    if [ $# -ne 1 ]; then
        echo "multiple pin files, pick one: $*" >&2
        exit 1
    fi
    ENV_FILE=$1
fi

# --- sync with origin first -------------------------------------------------
BRANCH=$(git symbolic-ref --quiet --short HEAD || echo "(detached)")
if [ "$BRANCH" != "master" ]; then
    echo "on '$BRANCH', not master -- checkout master first" >&2
    exit 1
fi

git fetch -q origin
HEAD_SHA=$(git rev-parse HEAD)
ORIGIN_SHA=$(git rev-parse origin/master)

if [ "$HEAD_SHA" != "$ORIGIN_SHA" ]; then
    if ! git merge-base --is-ancestor HEAD origin/master; then
        echo "local master has diverged from origin/master -- resolve manually" >&2
        exit 1
    fi
    if [ -n "$(git status --porcelain)" ]; then
        echo "master is behind origin/master but the working tree is dirty" >&2
        echo "-- commit/stash first, then re-run" >&2
        exit 1
    fi
    echo "[*] fast-forwarding master to origin/master ..."
    git merge --ff-only -q origin/master
fi

# --- read the pin only now: before the fast-forward it is the previous one ---
OPENWRT_TAG=$(sed -n 's/^OPENWRT_TAG=//p' "$ENV_FILE")
DEVICE_NAME=$(sed -n 's/^DEVICE_NAME=//p' "$ENV_FILE")
if [ -z "$OPENWRT_TAG" ] || [ -z "$DEVICE_NAME" ]; then
    echo "OPENWRT_TAG/DEVICE_NAME missing from $ENV_FILE" >&2
    exit 1
fi
TAG="${OPENWRT_TAG}-${DEVICE_NAME}"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "tag $TAG already exists (on $(git rev-parse --short "$TAG")) -- nothing to do" >&2
    exit 1
fi

# --- tag + push -------------------------------------------------------------
echo "[*] tagging $(git rev-parse --short HEAD) as $TAG"
git tag -a "$TAG" -m "OpenWrt $OPENWRT_TAG for $DEVICE_NAME"
git push origin "$TAG"
echo "pushed $TAG -- the mirror will forward it to GitHub, which builds + releases"
