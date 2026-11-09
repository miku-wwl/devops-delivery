#!/usr/bin/env bash
# Build and push the pipeline image (helm + kyverno) to the local registry.
#   bash v2/platform/gitops/ci-tools/build.sh      # prints the image reference
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=localhost:5001/ci-tools:helm4.3.1-kyverno1.19.2
if ! docker manifest inspect --insecure "$IMAGE" >/dev/null 2>&1; then
  docker build -q -t "$IMAGE" "$HERE" >&2
  docker push -q "$IMAGE" >&2
fi
echo "$IMAGE"
