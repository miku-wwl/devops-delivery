#!/usr/bin/env bash
# kwokctl (kubernetes-sigs/kwok), E10 / chapter 11: a Kubernetes control plane whose nodes and pods
# are simulated by the kwok controller - no kubelet, no containers. Installs a pinned release into
# ~/.local/bin after checking the SHA-256 that GitHub reports for the release asset (the release
# publishes no checksum file).   bash v2/platform/kwok/install.sh
set -euo pipefail
V=v0.8.0   # released 2026-06-23
SHA=d5743166c657283d6e827c7c4c20cacfd9009fd94830f06718ca7b2c7099461f
DEST=$HOME/.local/bin/kwokctl
mkdir -p "$(dirname "$DEST")"
if [ -x "$DEST" ] && echo "$SHA  $DEST" | sha256sum -c --quiet 2>/dev/null; then
  echo "kwokctl $V already installed"; exit 0
fi
tmp=$(mktemp)
curl -fsSL -o "$tmp" "https://github.com/kubernetes-sigs/kwok/releases/download/$V/kwokctl-linux-amd64"
echo "$SHA  $tmp" | sha256sum -c --quiet
install -m 0755 "$tmp" "$DEST"
rm -f "$tmp"
echo "kwokctl $V installed: $("$DEST" --version 2>&1 | head -1)"
