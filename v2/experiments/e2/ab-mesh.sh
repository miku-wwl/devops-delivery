#!/usr/bin/env bash
# Interleaved A/B: the same load with and without the ambient mesh, alternating, so slow drift
# of the host (other processes, thermal state) affects both sides equally.
#   bash v2/experiments/e2/ab-mesh.sh [reps=3] [seconds=90]
# Ambient enrolment is a namespace label and takes effect without restarting pods. Argo CD would
# put the label back, so automated sync of platform-root and namespaces is paused for the
# experiment and restored at the end (also on Ctrl-C).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
REPS=${1:-3}; SECS=${2:-90}
OUT="$ROOT/v2/evidence/e2/ab"; mkdir -p "$OUT"
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
pause() { for a in platform-root namespaces; do
            kubectl -n argocd patch application "$a" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null; done; }
resume() { for a in namespaces platform-root; do
             kubectl -n argocd patch application "$a" --type merge \
               -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":true}}}}' >/dev/null; done
           # platform-root originally prunes; restore exactly
           kubectl -n argocd patch application platform-root --type merge \
             -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
           kubectl label ns storefront istio.io/dataplane-mode=ambient --overwrite >/dev/null
           echo "argo cd automated sync restored; namespace label back to ambient"; }
trap resume EXIT
pause
mode() { if [ "$1" = ambient ]; then kubectl label ns storefront istio.io/dataplane-mode=ambient --overwrite >/dev/null
         else kubectl label ns storefront istio.io/dataplane-mode- >/dev/null; fi; sleep 20; }
printf '%-4s %-8s %8s %8s %8s %8s %8s %7s\n' rep mode br_p50 br_p95 or_p50 or_p95 req/s failed
for rep in $(seq "$REPS"); do
  for m in none ambient; do
    mode "$m"
    BASE_URL=$GW RATE=20 DURATION=${SECS}s SUMMARY="$OUT/$rep-$m.json" taskset -c 0-3 \
      k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" >/dev/null 2>&1
    jq -r --arg rep "$rep" --arg m "$m" '.metrics as $x | [$rep, $m,
        $x["http_req_duration{kind:browse}"].values.med, $x["http_req_duration{kind:browse}"].values["p(95)"],
        $x["http_req_duration{kind:order}"].values.med, $x["http_req_duration{kind:order}"].values["p(95)"],
        $x.http_reqs.values.rate, ($x.http_req_failed.values.rate * 100)] |
        "\(.[0])    \(.[1])\t\(.[2]|.*10|round/10)\t\(.[3]|.*10|round/10)\t\(.[4]|.*10|round/10)\t\(.[5]|.*10|round/10)\t\(.[6]|.*10|round/10)\t\(.[7]|.*100|round/100)%"' \
      "$OUT/$rep-$m.json" | awk -F'\t' '{printf "%-13s %8s %8s %8s %8s %8s %7s\n", $1, $2, $3, $4, $5, $6, $7}'
  done
done
