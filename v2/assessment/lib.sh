#!/usr/bin/env bash
# Shared by the assessment scripts of E12 (chapter 13). Sourced, not run.
# Graders print one PASS/FAIL line per check and a verdict; exit 0 only when every check passed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ST="$HOME/.lab-secrets/v2/assessment"; mkdir -p "$ST"; chmod 700 "$ST"
now() { date -u +%T; }
pass=0; fail=0
check() {   # "description" command... - the command decides
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  PASS  $d"; pass=$((pass + 1)); else echo "  FAIL  $d"; fail=$((fail + 1)); fi
}
verdict() { echo "== $(now) result: $pass passed, $fail failed -> $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; [ "$fail" = 0 ]; }
wait_for() {   # seconds command... - true as soon as the command succeeds; NOWAIT=1: do not wait (a run
               # that is expected to fail right after an injection)
  local s=$1; shift; local t0; t0=$(date +%s)
  [ -n "${NOWAIT:-}" ] && s=0
  until "$@" >/dev/null 2>&1; do [ $(( $(date +%s) - t0 )) -ge "$s" ] && return 1; sleep 5; done
}
apps_healthy() { [ "$(kubectl -n argocd get applications --no-headers | grep -vc 'Synced *Healthy')" = 0 ]; }
gateway() { echo "http://$(kubectl -n storefront get gateway storefront-ingress -o jsonpath='{.status.addresses[0].value}'):8080"; }
checkout_ok() {   # n checkouts in a row answered 2xx or 402 (a declined card is a working shop)
  local base c i; base=$(gateway)
  for i in $(seq 1 "${1:-5}"); do
    c=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST "$base/api/orders" -H 'Content-Type: application/json' \
      -H "Idempotency-Key: e12-$(date +%s%N)-$i" -d '{"customer_id":"e12-grader","items":[{"product_id":"sku-001","qty":1}]}')
    case $c in 2??|402) ;; *) return 1 ;; esac
  done
}
browse_ok() { [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$(gateway)/api/products?limit=1")" = 200 ]; }
# objects in a namespace that Argo CD does not track (no tracking annotation): changes made outside Git
untracked() {   # namespace kind
  kubectl -n "$1" get "$2" -o json 2>/dev/null |
    jq -r '.items[] | select(.metadata.annotations["argocd.argoproj.io/tracking-id"] == null) | .metadata.name'
}
