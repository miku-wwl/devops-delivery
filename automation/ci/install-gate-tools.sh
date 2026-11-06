#!/usr/bin/env bash
# Install the synthetic-gate toolchain on a CI runner (Linux amd64): kind, kubectl, helm, k6.
# Versions come from automation/lab/versions.env (the same pins as the lab) and every
# download is verified against the publisher's SHA256 before it is installed.
#   bash automation/ci/install-gate-tools.sh [install-dir]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lab/versions.env
source <(tr -d '\r' < "$HERE/../lab/versions.env")
DEST="${1:-$HOME/.local/bin}"
mkdir -p "$DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
gh_dl() { printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$3"; }
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
check() { grep -E "[ *]$1\$" | sha256sum -c -; }

fetch "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" kubectl
echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  kubectl" | sha256sum -c -
install -m 0755 kubectl "$DEST/kubectl"

fetch "$(gh_dl kubernetes-sigs/kind "$KIND_VERSION" kind-linux-amd64)" kind-linux-amd64
curl -fsSL "$(gh_dl kubernetes-sigs/kind "$KIND_VERSION" kind-linux-amd64.sha256sum)" | check kind-linux-amd64
install -m 0755 kind-linux-amd64 "$DEST/kind"

f="helm-${HELM_VERSION}-linux-amd64.tar.gz"
fetch "https://get.helm.sh/$f" "$f"
curl -fsSL "https://get.helm.sh/$f.sha256sum" | check "$f"
tar -xzf "$f" linux-amd64/helm
install -m 0755 linux-amd64/helm "$DEST/helm"

f="k6-${K6_VERSION}-linux-amd64.tar.gz"
fetch "$(gh_dl grafana/k6 "$K6_VERSION" "$f")" "$f"
curl -fsSL "$(gh_dl grafana/k6 "$K6_VERSION" "k6-${K6_VERSION}-checksums.txt")" | check "$f"
tar -xzf "$f" --strip-components=1 "k6-${K6_VERSION}-linux-amd64/k6"
install -m 0755 k6 "$DEST/k6"

echo "KIND_NODE_IMAGE=${KIND_NODE_IMAGE}"
"$DEST/kind" version
"$DEST/kubectl" version --client | head -1
"$DEST/helm" version --short
"$DEST/k6" version | head -1
