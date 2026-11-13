#!/usr/bin/env bash
# Which hop is slow when readiness probes time out during the load-balancer crash loop?
#   bash v2/experiments/e3/storm-probe.sh <label> [rate] [seconds]
# For one database-backed pod on each worker node, while lb-storm.sh runs:
#   * from the pod's node (the kubelet's network namespace): /healthz (no dependencies) and
#     /readyz (pool + SELECT 1) every 0.5 s, with their latency;
#   * from inside the pod (the service's own path, through the node's ztunnel): SELECT 1 on an
#     open connection every 0.5 s and a new connection every 2 s (probe_db.py).
# Then the maximum latency of each probe in 5-second buckets.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; RATE=${2:-180}; SECS=${3:-60}
OUT="$ROOT/v2/evidence/e3/$LABEL"; mkdir -p "$OUT"
DUR=$((SECS + 45))
pids=()
for n in ent-worker ent-worker2 ent-worker3; do
  read -r pod ip < <(kubectl -n storefront get pods --no-headers     -o custom-columns=N:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName |
    awk -v n="$n" '$3 == n && $1 ~ /^(catalog|inventory|orders)-/ {print $1, $2; exit}')
  [ -n "${pod:-}" ] || continue
  echo "$n: probing $pod ($ip)"
  docker exec "$n" timeout "$DUR" sh -c "while true; do
      h=\$(curl -s -o /dev/null -m 3 -w '%{http_code}/%{time_total}' http://$ip:8080/healthz)
      r=\$(curl -s -o /dev/null -m 3 -w '%{http_code}/%{time_total}' http://$ip:8080/readyz)
      echo \"\$(date -u +%T) healthz=\$h readyz=\$r\"; sleep 0.5; done" > "$OUT/http-$n.log" 2>&1 &
  pids+=($!)
  kubectl -n storefront exec -i "$pod" -c app -- python - "$DUR" < "$HERE/probe_db.py" \
    > "$OUT/db-$n.log" 2>&1 &
  pids+=($!)
done
sleep 10   # a baseline before the load starts
bash "$HERE/lb-storm.sh" "$LABEL" "$RATE" "$SECS"
wait "${pids[@]}" 2>/dev/null
echo
echo "max latency (ms) per 5 s: node -> pod /healthz | node -> pod /readyz | pod -> db SELECT 1 | new db connection"
for n in ent-worker ent-worker2 ent-worker3; do
  [ -s "$OUT/http-$n.log" ] || continue
  echo "== $n"
  cat "$OUT/http-$n.log" "$OUT/db-$n.log" | awk '
    { split($1, t, ":"); b = sprintf("%s:%s:%02d", t[1], t[2], int(t[3] / 5) * 5) ; seen[b] = 1
      for (i = 2; i <= NF; i++) { split($i, kv, "="); k = kv[1]; v = kv[2]
        if (k == "healthz" || k == "readyz") { split(v, cv, "/"); ms = cv[2] * 1000
          if (cv[1] != "200") bad[b, k]++ } else if (k ~ /_ms$/) ms = v + 0; else { bad[b, k]++; continue }
        if (ms > mx[b, k]) mx[b, k] = ms } }
    END { for (b in seen) {
        printf "%s  %7.0f %7.0f%s %7.0f %7.0f%s\n", b, mx[b, "healthz"], mx[b, "readyz"],
          (bad[b, "readyz"] ? " (" bad[b, "readyz"] " not 200)" : ""), mx[b, "query_ms"], mx[b, "connect_ms"],
          (bad[b, "query_failed"] + bad[b, "connect_failed"] ? " (" bad[b, "query_failed"] + bad[b, "connect_failed"] " failed)" : "") } }' | sort
done
