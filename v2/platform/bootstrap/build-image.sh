#!/usr/bin/env bash
# Build the storefront image and push it to the local registry (localhost:5001).
#   TAG=$(bash v2/platform/bootstrap/build-image.sh)      # prints the tag on stdout
# The tag is the last commit that changed v2/apps/storefront, so the same source always gives
# the same tag; uncommitted changes are refused (an image must be traceable to a commit).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
APP="$ROOT/v2/apps/storefront"
if [ -n "$(git -C "$ROOT" status --porcelain -- v2/apps/storefront)" ]; then
  echo "v2/apps/storefront has uncommitted changes; commit first" >&2
  exit 1
fi
TAG="$(git -C "$ROOT" log -1 --format=%h -- v2/apps/storefront)"
IMAGE="localhost:5001/storefront:$TAG"
if ! docker manifest inspect --insecure "$IMAGE" >/dev/null 2>&1; then
  docker build -q --target runtime --build-arg "APP_VERSION=$TAG" \
    --build-arg "GIT_SHA=$(git -C "$ROOT" log -1 --format=%H -- v2/apps/storefront)" \
    -t "$IMAGE" "$APP" >&2
  docker push -q "$IMAGE" >&2
fi
echo "$TAG"
