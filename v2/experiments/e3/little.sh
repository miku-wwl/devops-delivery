#!/usr/bin/env bash
# Little's law per pod, from the pod's own /metrics sampled 20 times a second (little_check.py),
# while the storefront mix runs at <rate> iterations/s.
#   bash v2/experiments/e3/little.sh <rate> <seconds> <service> [<service> ...]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RATE=${1:?rate}; SECS=${2:?seconds}; shift 2
bash "$ROOT/v2/platform/cluster/lb-limits.sh" > /dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
BASE_URL=$GW RATE=$RATE DURATION=$((SECS + 40))s taskset -c 0-3 k6 run --quiet \
  "$ROOT/v2/experiments/load/storefront.js" > /dev/null 2>&1 &
k6pid=$!
sleep 20
tmp=$(mktemp -d)
for svc in "$@"; do
  pod=$(kubectl -n storefront get pods -l app.kubernetes.io/name="$svc" -o jsonpath='{.items[0].metadata.name}')
  kubectl -n storefront exec -i "$pod" -c app -- python - "$SECS" 20 < "$HERE/little_check.py" > "$tmp/$svc" 2>&1 &
done
wait $(jobs -p | grep -v "^$k6pid\$") || true
for svc in "$@"; do echo "=== $svc"; cat "$tmp/$svc"; done
wait "$k6pid" || true
rm -rf "$tmp"
