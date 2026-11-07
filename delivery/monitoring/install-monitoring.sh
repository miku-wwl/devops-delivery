#!/usr/bin/env bash
# Install kube-prometheus-stack (pinned chart version) into namespace "monitoring".
# The Grafana admin password is generated into ~/.lab-secrets and handed to the chart
# through an existing Secret - it never appears in a values file or on the command line.
#   bash delivery/monitoring/install-monitoring.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_VERSION="${KPS_CHART_VERSION:-92.21.1}"
SECRETS="$HOME/.lab-secrets"
mkdir -p "$SECRETS"
if [ ! -s "$SECRETS/grafana-admin-password" ]; then
  python3 -c 'import secrets, string; a = string.ascii_letters + string.digits; print("".join(secrets.choice(a) for _ in range(20)), end="")' \
    > "$SECRETS/grafana-admin-password"
  chmod 600 "$SECRETS/grafana-admin-password"
fi
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-file=admin-password="$SECRETS/grafana-admin-password" \
  --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" -n monitoring -f "$HERE/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m
kubectl -n monitoring get pods
