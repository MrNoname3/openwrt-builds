#!/bin/sh
# Create and push the release tag for the currently pinned OpenWrt version.
#
# Run it on master after a bump PR is merged (and pulled). The tag lands on
# origin (the Gitea source of truth); the push mirror forwards it to GitHub,
# where the tag push triggers the release build (.github/workflows/build.yml).
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

OPENWRT_TAG=$(sed -n 's/^OPENWRT_TAG=//p' "$ENV_FILE")
DEVICE_NAME=$(sed -n 's/^DEVICE_NAME=//p' "$ENV_FILE")
[ -n "$OPENWRT_TAG" ] && [ -n "$DEVICE_NAME" ] || {
	echo "OPENWRT_TAG/DEVICE_NAME missing from $ENV_FILE" >&2
	exit 1
}
TAG="${OPENWRT_TAG}-${DEVICE_NAME}"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	echo "tag $TAG already exists (on $(git rev-parse --short "$TAG")) -- nothing to do" >&2
	exit 1
fi

# Sanity: tag what origin considers master, not a stale/diverged local HEAD.
git fetch -q origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/master)" ]; then
	echo "HEAD is not origin/master -- pull/checkout first" >&2
	exit 1
fi

git tag -a "$TAG" -m "OpenWrt $OPENWRT_TAG for $DEVICE_NAME"
git push origin "$TAG"
echo "pushed $TAG -- the mirror will forward it to GitHub, which builds + releases"
