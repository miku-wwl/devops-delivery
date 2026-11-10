#!/usr/bin/env bash
# X1/X2 (E9, chapter 10; evidence/e9/exemplars-prediction.md): exemplars that lead to kept traces.
#   bash v2/experiments/e9/exemplars.sh > v2/evidence/e9/exemplars.log
set -uo pipefail
P="/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1"
now() { date -u +%T; }
enc() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
exemplars() {  # $1 $2: start end (epoch); prints bucket -> count and the trace IDs
  kubectl get --raw "$P/query_exemplars?query=$(enc 'http_server_request_duration_seconds_bucket{namespace="storefront",service="gateway"}')&start=$1&end=$2" | python3 -c '
import json, sys, collections
c, ids = collections.Counter(), []
for s in json.load(sys.stdin)["data"]:
    for e in s["exemplars"]:
        c[s["seriesLabels"].get("le")] += 1; ids.append(e["labels"]["trace_id"])
print(" ".join(f"le={k}:{v}" for k, v in sorted(c.items(), key=lambda x: float(x[0]) if x[0] != "+Inf" else 1e9)) or "none")
print(" ".join(ids))'
}
faults() {
  for p in $(kubectl -n storefront get pods -l app.kubernetes.io/name=catalog -o jsonpath='{.items[*].metadata.name}'); do
    printf '%s' "$1" | kubectl -n storefront exec -i "$p" -c app -- python -c "import sys, urllib.request; r = urllib.request.Request('http://127.0.0.1:8080/admin/faults', data=sys.stdin.buffer.read(), method='PUT', headers={'Content-Type': 'application/json'}); urllib.request.urlopen(r, timeout=5).read()"
  done
}
trap 'faults "{}" >/dev/null 2>&1' EXIT
T0=$(date +%s)
echo "== $(now) X1 before: exemplars of the last 10 minutes (only fast, successful requests since the rollout)"
exemplars $((T0 - 600)) "$T0" | head -1 | sed 's/^/  /'
echo "== $(now) catalog: 1200 ms of injected latency for 45 s"
faults '{"latency_ms": 1200}'; sleep 45; faults '{}'
echo "== $(now) faults removed; waiting 60 s for scrapes and the collector's decisions"
sleep 60
T1=$(date +%s)
out=$(exemplars "$T0" "$T1")
echo "== $(now) X1 after: exemplars per bucket: $(echo "$out" | head -1)"
ids=$(echo "$out" | sed -n 2p | tr ' ' '\n' | sort -u | head -5)
echo "== $(now) X2: the first five distinct trace IDs in Tempo"
for id in $ids; do
  kubectl get --raw "/api/v1/namespaces/observability/services/tempo:3200/proxy/api/traces/$id" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin); spans = []
for b in d.get("batches", d.get("resourceSpans", [])):
    svc = next((a["value"].get("stringValue") for a in b["resource"]["attributes"] if a["key"] == "service.name"), "?")
    for ss in b.get("scopeSpans", b.get("instrumentationLibrarySpans", [])):
        for s in ss["spans"]:
            spans.append((svc, s["name"], (int(s["endTimeUnixNano"]) - int(s["startTimeUnixNano"])) / 1e6))
slow = max(spans, key=lambda x: x[2]) if spans else None
print(f"  {sys.argv[1]}: {len(spans)} spans, longest {slow[0]} {slow[1]!r} {slow[2]:.0f} ms" if slow else f"  {sys.argv[1]}: not found")' "$id" || echo "  $id: not found"
done
echo "== $(now) tail sampling over the incident (08:23:30-08:35:00), traces by policy and decision:"
kubectl get --raw "$P/query?query=$(enc 'sum by (policy, sampled) (increase(otelcol_processor_tail_sampling_count_traces_sampled[690s]))')&time=$(date -d 2026-11-10T08:35:00Z +%s)" | python3 -c '
import json, sys
for r in sorted(json.load(sys.stdin)["data"]["result"], key=lambda r: (r["metric"]["policy"], r["metric"]["sampled"])):
    print("  ", r["metric"]["policy"], "sampled" if r["metric"]["sampled"] == "true" else "not sampled", round(float(r["value"][1])))'
