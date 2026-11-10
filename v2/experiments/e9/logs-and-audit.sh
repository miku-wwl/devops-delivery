#!/usr/bin/env bash
# E9 (chapter 10): node-level logs and service accounts' Secret reads (hypotheses L1, U1 in
# evidence/e9/logs-audit-prediction.md).   bash v2/experiments/e9/logs-and-audit.sh > v2/evidence/e9/logs-audit.log
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STATE=${ENT_STATE_DIR:-$HOME/ent-data}
now() { date -u +%T; }
loki() { kubectl get --raw "/api/v1/namespaces/observability/services/loki:3100/proxy/loki/api/v1/query_range?query=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1")&since=15m&limit=20"; }
echo "== $(now) L1: a pod writes a marker to stdout and is deleted"
M="E9-MARKER-$(date +%s)"
kubectl -n default run e9-logprobe --image=busybox:1.37 --restart=Never --command -- sh -c "echo $M; echo last line before deletion; sleep 3600" >/dev/null
kubectl -n default wait --for=condition=Ready pod/e9-logprobe --timeout=120s >/dev/null
sleep 5
kubectl -n default delete pod e9-logprobe --wait=true --grace-period=1 | sed 's/^/  /'
echo "  $(now) kubectl logs after the deletion: $(kubectl -n default logs e9-logprobe 2>&1 | head -1)"
sleep 20
echo "  $(now) Loki {job=\"node-logs\", pod=\"e9-logprobe\"}:"
loki '{job="node-logs", pod="e9-logprobe"}' | python3 -c '
import json, sys
for s in json.load(sys.stdin)["data"]["result"]:
    for t, line in s["values"]:
        print("   ", s["stream"].get("node"), s["stream"].get("container"), line)'
echo "== $(now) U1: the audit policy records service accounts reading Secrets"
cp "$ROOT/v2/platform/cluster/audit-policy.yaml" "$STATE/audit-policy/policy.yaml"
docker exec ent-control-plane sh -c 'grep -c "secrets" /etc/kubernetes/audit/policy.yaml' | sed 's/^/  policy lines naming secrets in the node: /'
T0=$(date -u +%FT%TZ)
docker exec ent-control-plane sh -c 'crictl stop $(crictl ps --name kube-apiserver -q)' >/dev/null
echo "  $(now) kube-apiserver container stopped; the kubelet restarts it"
for i in $(seq 1 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 2; done
echo "  $(now) API server ready again"
sleep 60
echo "  $(now) Secret reads by service accounts since $T0 (audit log, user: count by verb):"
docker exec ent-control-plane cat /var/log/kubernetes/audit/audit.log | python3 -c '
import collections, json, sys
since = sys.argv[1]; c = collections.Counter(); names = collections.defaultdict(set)
for l in sys.stdin:
    try: e = json.loads(l)
    except ValueError: continue
    o = e.get("objectRef") or {}
    if e.get("requestReceivedTimestamp", "") < since or o.get("resource") != "secrets" or e["verb"] not in ("get", "list", "watch"): continue
    u = e["user"]["username"]
    if not u.startswith("system:serviceaccount:"): continue
    c[(u.split(":", 2)[2], e["verb"])] += 1
    if o.get("name"): names[u.split(":", 2)[2]].add(f"{o.get(\"namespace\")}/{o[\"name\"]}")
for (u, v), n in sorted(c.items()): print(f"    {u:55} {v:5} {n}")
for u, ns in sorted(names.items()): print(f"    {u} read by name: {sorted(ns)[:4]}")' "$T0"
