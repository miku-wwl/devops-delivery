#!/usr/bin/env bash
# Incident drill (E9, chapter 10; hypotheses S1-S6 in evidence/e9/incident-prediction.md).
#   bash v2/experiments/e9/incident-drill.sh baseline   # k6, 10 it/s for 100 min, in the background
#   bash v2/experiments/e9/incident-drill.sh break      # alice's change (PSP_ERROR_RATE "1"), merged
#   bash v2/experiments/e9/incident-drill.sh watch      # until the bridge has opened the incident
#   bash v2/experiments/e9/incident-drill.sh respond    # on-call: acknowledge, diagnose from GitLab, revert
#   bash v2/experiments/e9/incident-drill.sh recover    # until the incident is closed
#   bash v2/experiments/e9/incident-drill.sh report     # impact from Prometheus
# Every step appends to evidence/e9/incident/timeline.log ("<UTC> <step>: <what>").
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$ROOT/v2/evidence/e9/incident"; mkdir -p "$OUT"; TL="$OUT/timeline.log"
P="/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1"
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
GL=http://localhost:8929/api/v4/projects
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
mark() { echo "$(date -u +%FT%T.%3NZ) $1" | tee -a "$TL"; }
enc() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
val() { kubectl get --raw "$P/query?query=$(enc "$1")" | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(round(float(r[0]["value"][1]), 4) if r else "-")'; }
alert() { kubectl get --raw "$P/alerts" | python3 -c 'import json,sys; print(next((a["state"] for a in json.load(sys.stdin)["data"]["alerts"] if a["labels"]["alertname"] == sys.argv[1]), "inactive"))' "$1"; }
incident_iid() { docker logs alert-bridge 2>&1 | grep '"event": "opened"' | grep SLOBurnCheckout | tail -1 | grep -o '"iid": [0-9]*' | grep -o '[0-9]*'; }
status() { echo "checkout 5m $(val 'slo:error_ratio:5m{slo="checkout-availability"}') 1h $(val 'slo:error_ratio:1h{slo="checkout-availability"}') | browse 5m $(val 'slo:error_ratio:5m{slo="browse-availability"}') | page $(alert SLOBurnCheckoutAvailabilityPage) ticket $(alert SLOBurnCheckoutAvailabilityTicket)"; }
case ${1:?baseline|break|watch|respond|recover|report} in
baseline)
  IP=$(kubectl -n storefront get gateway storefront-ingress -o jsonpath='{.status.addresses[0].value}')
  nohup env BASE_URL="http://$IP:8080" RATE=10 DURATION=100m k6 run --quiet --summary-export "$OUT/k6-summary.json" \
    "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 &
  mark "baseline: k6 10 it/s for 100 min against the layer-7 entrance $IP:8080 (pid $!)" ;;
break)
  out=$(bash "$ROOT/v2/platform/gitops/mr.sh" propose 8ef5584 "payments: test the provider's error handling" --as alice \
        --edit "sed -i 's/^  PSP_DECLINE_RATE: \"0.02\"$/  PSP_DECLINE_RATE: \"0.02\"\n  PSP_ERROR_RATE: \"1\"            # error handling test/' envs/prod/storefront/services/payments.yaml" 2>&1)
  echo "$out" | sed 's/^/  /' >> "$TL"
  iid=$(echo "$out" | grep -o 'MR ![0-9]*' | head -1 | tr -d 'MR !')
  mark "change: alice's merge request !$iid, $(echo "$out" | grep -o 'pipeline [0-9]*: [a-z]* after [0-9]* s' | head -1)"
  bash "$ROOT/v2/platform/gitops/mr.sh" merge "$iid" 2>&1 | sed 's/^/  /' >> "$TL"
  mark "change: !$iid merged by a Maintainer (root)"
  kubectl -n argocd annotate app storefront-payments-prod argocd.argoproj.io/refresh=normal --overwrite >/dev/null ;;
watch)
  for i in $(seq 1 120); do
    s=$(status); echo "$(date -u +%T) $s" >> "$OUT/watch.log"
    case "$s" in *"page pending"*) grep -q "page pending" "$TL" || mark "detection: page alert pending ($s)";; esac
    case "$s" in *"page firing"*) grep -q "page firing" "$TL" || mark "detection: page alert firing ($s)";; esac
    if [ -n "$(incident_iid)" ]; then mark "escalation: the bridge opened GitLab incident #$(incident_iid) in root/incidents"; break; fi
    sleep 15
  done ;;
respond)
  N=$(incident_iid)
  api -X POST "$GL/root%2Fincidents/issues/$N/notes" --data-urlencode "body=Acknowledged by the on-call engineer (root). Investigating: checkout failing, browse fine." >/dev/null
  mark "response: incident #$N acknowledged (note in GitLab)"
  since=$(date -u -d '-30 min' +%FT%TZ)
  deps=$(api "$GL/root%2Fplatform-gitops/deployments?updated_after=$since&order_by=updated_at&sort=desc&per_page=10" |
         jq -r '.[] | "\(.environment.name) \(.status) \(.sha[0:8]) \(.created_at)"')
  echo "$deps" | sed 's/^/  deployments: /' >> "$TL"
  d=$(api "$GL/root%2Fplatform-gitops/deployments?updated_after=$since&order_by=updated_at&sort=desc&per_page=10" | jq -r '[.[] | select(.environment.name == "prod/payments")][0].id')
  mrs=$(api "$GL/root%2Fplatform-gitops/deployments/$d/merge_requests" | jq -r '[.[] | "!\(.iid) \(.title) (\(.author.username))"] | join("; ")')
  api -X POST "$GL/root%2Fincidents/issues/$N/notes" --data-urlencode "body=Diagnosis: deployment of prod/payments shortly before the failures, merge requests: $mrs. Mitigation: revert through the gate." >/dev/null
  mark "diagnosis: prod/payments deployment #$d contains $mrs - revert"
  bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" 8ef5584 "Revert: payments PSP_ERROR_RATE (incident #$N)" 2>&1 | tail -2 | sed 's/^/  /' >> "$TL"
  mark "mitigation: revert merged (publish of v2/gitops, which never had the line)"
  kubectl -n argocd annotate app storefront-payments-prod argocd.argoproj.io/refresh=normal --overwrite >/dev/null ;;
recover)
  for i in $(seq 1 80); do
    s=$(status); echo "$(date -u +%T) $s" >> "$OUT/watch.log"
    r=$(val 'slo:error_ratio:5m{slo="checkout-availability"}')
    python3 -c "import sys; sys.exit(0 if '$r' != '-' and float('$r') < 0.01 else 1)" && { grep -q "recovered" "$TL" || mark "recovery: checkout 5-minute error ratio below 1 % ($r)"; }
    if docker logs alert-bridge 2>&1 | grep '"event": "closed"' | grep -q SLOBurnCheckout; then mark "resolution: the bridge closed the incident (alert resolved)"; break; fi
    sleep 15
  done ;;
report)
  T1=$(grep " change: .* merged" "$TL" | tail -1 | cut -d' ' -f1); T2=$(grep " resolution:" "$TL" | tail -1 | cut -d' ' -f1)
  d=$(( $(date -d "$T2" +%s) - $(date -d "$T1" +%s) ))
  q() { val "sum(increase(http_server_requests_total{namespace=\"storefront\",service=\"gateway\",route=\"/api/orders\"$1}[${d}s] @ $(date -d "$T2" +%s)))"; }
  mark "report: from the merge to the resolution ($d s): orders at the gateway $(q ''), 5xx $(q ',code=~"5.."'); browse 5xx $(val "sum(increase(http_server_requests_total{namespace=\"storefront\",service=\"gateway\",route=~\"/api/products.*\",code=~\"5..\"}[${d}s] @ $(date -d "$T2" +%s)))")" ;;
esac
