#!/usr/bin/env bash
# CLIs added by the v2 phases (the v1 lab installs its own in automation/lab/bootstrap-root.sh),
# pinned in platform/versions.env, checked against the release's published SHA-256 sums,
# installed to /usr/local/bin (sudo). Idempotent: a CLI already at the pinned version is skipped.
#   bash v2/platform/tools/install-cli.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../versions.env"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; cd "$tmp"

fetch_verified() { # url-of-asset url-of-checksum-file
  local asset=${1##*/}
  curl -fsSLO "$1"
  curl -fsSL "$2" -o sums.txt
  grep " $asset\$" sums.txt | sha256sum -c - >/dev/null
  echo "$asset: sha256 ok ($(stat -c %s "$asset") bytes)"
}

# E7: kubectl-cnpg (CloudNativePG plugin: status, promote, backup, fencing), same version as the operator
if ! kubectl cnpg version 2>/dev/null | grep -q "Version:$CNPG_PLUGIN_VERSION\b"; then
  base=https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v$CNPG_PLUGIN_VERSION
  fetch_verified "$base/kubectl-cnpg_${CNPG_PLUGIN_VERSION}_linux_x86_64.tar.gz" "$base/cnpg-${CNPG_PLUGIN_VERSION}-checksums.txt"
  tar xzf "kubectl-cnpg_${CNPG_PLUGIN_VERSION}_linux_x86_64.tar.gz" kubectl-cnpg
  sudo install -m 0755 kubectl-cnpg /usr/local/bin/kubectl-cnpg
fi
kubectl cnpg version
