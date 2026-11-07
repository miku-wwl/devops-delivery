#!/usr/bin/env bash
# Send N requests to a Kubernetes Service through "kubectl port-forward" and count
# the HTTP status codes - a quick, honest health check for drills.
#   bash delivery/kind/probe.sh <namespace> <service> [path] [count]
#   bash delivery/kind/probe.sh prod demo-api-prod /api/v1/info 40
# Note: port-forward to a Service pins one backing pod for the whole session.
set -euo pipefail
ns=${1:?namespace} svc=${2:?service} path=${3:-/api/v1/info} n=${4:-20}
port=$((20000 + RANDOM % 10000))
kubectl -n "$ns" port-forward "svc/$svc" "$port:80" >/dev/null 2>&1 &
pf=$!
trap 'kill "$pf" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -s -o /dev/null "localhost:$port/healthz" && break; sleep 0.5; done
for _ in $(seq 1 "$n"); do
  curl -s -o /dev/null -w '%{http_code}\n' "localhost:$port$path"
done | sort | uniq -c | sed 's/^ */HTTP status count: /'
