#!/usr/bin/env bash
# OpenTofu, E11 / chapter 12: infrastructure as code for what Argo CD does not manage (the GitLab
# governance of the configuration repository). Installs a pinned release into ~/.local/bin after
# checking its SHA-256 - the same value in the release's tofu_<v>_SHA256SUMS and in the digest GitHub
# reports for the asset.   bash v2/platform/iac/install.sh
set -euo pipefail
V=1.13.9   # released 2026-11-05
SHA=b34b327cc1ef07178207b6f2cd1f5276537d3e5b7be316500f6dac50d4c0a857
DEST=$HOME/.local/bin/tofu
mkdir -p "$(dirname "$DEST")"
if [ -x "$DEST" ] && "$DEST" version 2>/dev/null | head -1 | grep -q "v$V\$"; then
  echo "tofu $V already installed"; exit 0
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/tofu.tgz" "https://github.com/opentofu/opentofu/releases/download/v$V/tofu_${V}_linux_amd64.tar.gz"
echo "$SHA  $tmp/tofu.tgz" | sha256sum -c --quiet
tar -xzf "$tmp/tofu.tgz" -C "$tmp" tofu
install -m 0755 "$tmp/tofu" "$DEST"
echo "tofu installed: $("$DEST" version | head -1)"
