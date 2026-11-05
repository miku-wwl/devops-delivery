#!/usr/bin/env bash
# Bootstrap the "devops-lab" WSL2 distro (Ubuntu 24.04). Run as root; idempotent.
#
#   wsl.exe -d devops-lab -u root -- bash /mnt/d/workshop/nov/devops-delivery/automation/lab/bootstrap-root.sh
#
# What it does
#   1. base packages
#   2. /etc/wsl.conf: systemd on, default user, keep Windows PATH out of Linux PATH
#   3. a non-root lab user with passwordless sudo (lab only!)
#   4. Docker Engine from the official download.docker.com apt repository
#   5. kernel parameters recommended by kind
#   6. pinned CLIs (versions.env), each verified against the publisher's SHA256
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source <(tr -d '\r' < "$HERE/versions.env")
LAB_USER="${LAB_USER:-devops}"
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n==> %s\n' "$*"; }

log "1/6 base packages"
apt-get update -y -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl gnupg jq git make unzip tar sudo less vim-tiny \
  iproute2 iputils-ping dnsutils bash-completion python3 python3-venv python3-pip >/dev/null
echo "base packages installed"

log "2/6 /etc/wsl.conf"
cat > /etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=${LAB_USER}

[interop]
appendWindowsPath=false
EOF
cat /etc/wsl.conf

log "3/6 lab user '${LAB_USER}'"
id "$LAB_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$LAB_USER"
echo "${LAB_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-${LAB_USER}"
chmod 0440 "/etc/sudoers.d/90-${LAB_USER}"
id "$LAB_USER"

log "4/6 Docker Engine (official apt repository)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck disable=SC1091
. /etc/os-release
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update -y -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
usermod -aG docker "$LAB_USER"
docker --version

log "5/6 kernel parameters for kind (inotify limits)"
cat > /etc/sysctl.d/99-kind.conf <<'EOF'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sysctl -q --system || true

log "6/6 pinned CLIs -> /usr/local/bin (sha256-verified)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
gh_dl() { printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$3"; }
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
# check <file> <checksum-list-on-stdin>: keep only the line for <file>, then sha256sum -c
check() { grep -E "[ *]$1\$" | sha256sum -c -; }

# kubectl (dl.k8s.io publishes a bare hash)
fetch "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" kubectl
echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  kubectl" | sha256sum -c -
install -m 0755 kubectl /usr/local/bin/kubectl

# kind
fetch "$(gh_dl kubernetes-sigs/kind "$KIND_VERSION" kind-linux-amd64)" kind-linux-amd64
curl -fsSL "$(gh_dl kubernetes-sigs/kind "$KIND_VERSION" kind-linux-amd64.sha256sum)" | check kind-linux-amd64
install -m 0755 kind-linux-amd64 /usr/local/bin/kind

# helm
f="helm-${HELM_VERSION}-linux-amd64.tar.gz"
fetch "https://get.helm.sh/$f" "$f"
curl -fsSL "https://get.helm.sh/$f.sha256sum" | check "$f"
tar -xzf "$f" linux-amd64/helm
install -m 0755 linux-amd64/helm /usr/local/bin/helm

# argocd CLI
fetch "$(gh_dl argoproj/argo-cd "$ARGOCD_VERSION" argocd-linux-amd64)" argocd-linux-amd64
curl -fsSL "$(gh_dl argoproj/argo-cd "$ARGOCD_VERSION" cli_checksums.txt)" | check argocd-linux-amd64
install -m 0755 argocd-linux-amd64 /usr/local/bin/argocd

# Argo Rollouts kubectl plugin
fetch "$(gh_dl argoproj/argo-rollouts "$ARGO_ROLLOUTS_VERSION" kubectl-argo-rollouts-linux-amd64)" kubectl-argo-rollouts-linux-amd64
curl -fsSL "$(gh_dl argoproj/argo-rollouts "$ARGO_ROLLOUTS_VERSION" argo-rollouts-checksums.txt)" | check kubectl-argo-rollouts-linux-amd64
install -m 0755 kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# trivy
f="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
fetch "$(gh_dl aquasecurity/trivy "v${TRIVY_VERSION}" "$f")" "$f"
curl -fsSL "$(gh_dl aquasecurity/trivy "v${TRIVY_VERSION}" "trivy_${TRIVY_VERSION}_checksums.txt")" | check "$f"
tar -xzf "$f" trivy
install -m 0755 trivy /usr/local/bin/trivy

# syft
f="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
fetch "$(gh_dl anchore/syft "v${SYFT_VERSION}" "$f")" "$f"
curl -fsSL "$(gh_dl anchore/syft "v${SYFT_VERSION}" "syft_${SYFT_VERSION}_checksums.txt")" | check "$f"
tar -xzf "$f" syft
install -m 0755 syft /usr/local/bin/syft

# cosign
fetch "$(gh_dl sigstore/cosign "$COSIGN_VERSION" cosign-linux-amd64)" cosign-linux-amd64
curl -fsSL "$(gh_dl sigstore/cosign "$COSIGN_VERSION" cosign_checksums.txt)" | check cosign-linux-amd64
install -m 0755 cosign-linux-amd64 /usr/local/bin/cosign

# k6
f="k6-${K6_VERSION}-linux-amd64.tar.gz"
fetch "$(gh_dl grafana/k6 "$K6_VERSION" "$f")" "$f"
curl -fsSL "$(gh_dl grafana/k6 "$K6_VERSION" "k6-${K6_VERSION}-checksums.txt")" | check "$f"
tar -xzf "$f" --strip-components=1 "k6-${K6_VERSION}-linux-amd64/k6"
install -m 0755 k6 /usr/local/bin/k6

# yq (publishes BSD-style "SHA256 (file) = hash" lines)
fetch "$(gh_dl mikefarah/yq "$YQ_VERSION" yq_linux_amd64)" yq_linux_amd64
sum="$(curl -fsSL "$(gh_dl mikefarah/yq "$YQ_VERSION" checksums-bsd)" | sed -n 's/^SHA256 (yq_linux_amd64) = //p')"
[ -n "$sum" ] || { echo "yq checksum not found" >&2; exit 1; }
echo "$sum  yq_linux_amd64" | sha256sum -c -
install -m 0755 yq_linux_amd64 /usr/local/bin/yq

log "bootstrap finished - restart the distro to activate systemd: wsl.exe --terminate devops-lab"
