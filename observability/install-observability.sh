#!/usr/bin/env bash
# Install the lab telemetry pipeline (idempotent):
#   observability/lgtm      grafana/otel-lgtm backend (Tempo, Loki, Prometheus, Grafana)
#   otel-collector          official OpenTelemetry Collector chart (contrib image)
#   alerts                  PrometheusRule for kube-prometheus-stack
#   bash observability/install-observability.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_CHART_VERSION="${COLLECTOR_CHART_VERSION:-0.178.2}"

kubectl apply -f "$HERE/lgtm/lgtm.yaml"
kubectl -n observability rollout status deploy/lgtm --timeout=300s

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --version "$COLLECTOR_CHART_VERSION" -n observability \
  -f "$HERE/otel-collector/values.yaml" --wait --timeout 5m >/dev/null
kubectl -n observability rollout status deploy/otel-collector --timeout=300s

kubectl apply -f "$HERE/alerts/demo-api-rules.yaml"
kubectl -n observability get pods -o wide
