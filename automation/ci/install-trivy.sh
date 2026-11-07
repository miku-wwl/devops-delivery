#!/usr/bin/env bash
# Install the pinned Trivy release (automation/lab/versions.env) on a CI runner,
# verifying the archive against the checksums published with the same release.
# Used instead of a third-party wrapper action: fewer moving parts to trust.
#   bash automation/ci/install-trivy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source <(grep -E '^TRIVY_VERSION=' "$ROOT/automation/lab/versions.env" | tr -d '\r')
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
f="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
curl -fsSLO --retry 3 "$base/$f"
curl -fsSL --retry 3 "$base/trivy_${TRIVY_VERSION}_checksums.txt" | grep -E " ${f}\$" | sha256sum -c -
tar -xzf "$f" trivy
sudo install -m 0755 trivy /usr/local/bin/trivy
trivy --version | head -1
