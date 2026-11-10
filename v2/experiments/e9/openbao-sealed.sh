#!/usr/bin/env bash
# A2 (E9, chapter 10; evidence/e9/alerting-prediction.md): OpenBao restarted -> sealed -> alert ->
# GitLab incident -> unseal -> incident closed.
#   bash v2/experiments/e9/openbao-sealed.sh > v2/evidence/e9/a2-openbao.log
# The restart also loads the telemetry configuration (the chart's update strategy is OnDelete).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
P="/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1"
now() { date -u +%T; }
unsealed() { kubectl get --raw "$P/query?query=vault_core_unsealed" | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "absent")'; }
alert() { kubectl get --raw "$P/alerts" | python3 -c 'import json,sys; print(next((a["state"] for a in json.load(sys.stdin)["data"]["alerts"] if a["labels"]["alertname"] == "OpenBaoSealed"), "inactive"))'; }
bridge() { docker logs --since "$1" alert-bridge 2>&1 | grep -v heartbeat | grep -o '"event": "[a-z_]*".*"alertname": "OpenBaoSealed"[^,]*, "iid": [0-9]*' ; }
T0=$(date -u +%FT%TZ)
echo "== $(now) delete pod secrets/openbao-0"
kubectl -n secrets delete pod openbao-0 --wait=true | sed 's/^/  /'
kubectl -n secrets wait --for=jsonpath='{.status.phase}'=Running pod/openbao-0 --timeout=180s >/dev/null
T_UP=$(date +%s); echo "== $(now) openbao-0 Running; status: $(kubectl -n secrets exec openbao-0 -- bao status -format=json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("sealed" if d["sealed"] else "unsealed")')"
opened=
for i in $(seq 1 40); do
  sleep 10
  line=$(bridge "$T0" | grep opened)
  echo "  $(now) +$(( $(date +%s) - T_UP ))s vault_core_unsealed=$(unsealed) alert=$(alert) ${line:+bridge: $line}"
  [ -n "$line" ] && { opened=1; break; }
done
echo "== $(now) unseal (platform/secrets/openbao-init.sh)"
T_UNSEAL=$(date +%s)
bash "$ROOT/v2/platform/secrets/openbao-init.sh" 2>&1 | tail -2 | sed 's/^/  /'
for i in $(seq 1 30); do
  sleep 10
  line=$(bridge "$T0" | grep closed)
  echo "  $(now) +$(( $(date +%s) - T_UNSEAL ))s after the unseal: vault_core_unsealed=$(unsealed) alert=$(alert) ${line:+bridge: $line}"
  [ -n "$line" ] && break
done
echo "== $(now) bridge events since $T0:"
docker logs --since "$T0" alert-bridge 2>&1 | grep -v heartbeat | cut -c1-260 | sed 's/^/  /'
