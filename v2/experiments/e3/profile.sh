#!/usr/bin/env bash
# Where does the CPU of a storefront service go? Sampling profiles under a fixed load.
#   bash v2/experiments/e3/profile.sh <label> <rate> <seconds> <service> [<service> ...]
# Starts the storefront mix at <rate> iterations/s (k6, open model), waits 30 s, then profiles
# one pod of every <service> at the same time for <seconds>, from the node, without touching
# the pod: py-spy (a sampling profiler for Python, downloaded once from PyPI and checked against
# the published SHA-256) runs inside the Kind node container that hosts the pod.
# Method (chapter 4): only samples in which a thread holds the GIL are kept (--gil). py-spy's
# own idle detection does not work here: it runs in the node's PID namespace while the
# interpreter reports thread ids of the pod's namespace, so an idle event loop counts as active.
# Next to the samples, the CPU time of every thread is read from /proc over the same window.
# Output per service in evidence/e3/profile/<label>-<service>.{collapsed.txt,svg,threads.txt}.
set -euo pipefail
LABEL=${1:?label}; RATE=${2:?rate}; SECS=${3:?seconds}; shift 3
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$ROOT/v2/evidence/e3/profile"; mkdir -p "$OUT"
VER=0.4.2
TOOLS="$HOME/ent-data/tools"; mkdir -p "$TOOLS"
if [ ! -x "$TOOLS/py-spy-$VER" ]; then
  meta=$(curl -fsSL "https://pypi.org/pypi/py-spy/$VER/json")
  url=$(jq -r '.urls[] | select(.filename | test("manylinux.*x86_64")) | .url' <<<"$meta" | head -1)
  sum=$(jq -r '.urls[] | select(.filename | test("manylinux.*x86_64")) | .digests.sha256' <<<"$meta" | head -1)
  curl -fsSL -o "$TOOLS/py-spy.whl" "$url"
  echo "$sum  $TOOLS/py-spy.whl" | sha256sum -c -
  python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); n=[m for m in z.namelist() if m.endswith('/py-spy')][0]; open(sys.argv[2],'wb').write(z.read(n))" \
    "$TOOLS/py-spy.whl" "$TOOLS/py-spy-$VER"
  chmod +x "$TOOLS/py-spy-$VER"
fi
bash "$ROOT/v2/platform/cluster/lb-limits.sh" > /dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
BASE_URL=$GW RATE=$RATE DURATION=$((SECS + 50))s SUMMARY="$OUT/$LABEL-k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/$LABEL-k6.txt" 2>&1 &
k6pid=$!
sleep 30
# per-thread CPU ticks (utime + stime) and the pod-namespace thread id, from the node's /proc
ticks() { docker exec "$1" sh -c "for t in /proc/$2/task/*; do
  echo \$(basename \$t) \$(grep NSpid \$t/status | awk '{print \$NF}') \$(sed 's/.*) //' \$t/stat | awk '{print \$12 + \$13}')
  done"; }
declare -A NODE PID
for svc in "$@"; do
  pod=$(kubectl -n storefront get pods -l app.kubernetes.io/name="$svc" -o jsonpath='{.items[0].metadata.name}')
  node=$(kubectl -n storefront get pod "$pod" -o jsonpath='{.spec.nodeName}')
  docker cp "$TOOLS/py-spy-$VER" "$node:/usr/local/bin/py-spy" >/dev/null
  pid=$(docker exec "$node" sh -c "for p in \$(pgrep -f 'storefront.$svc.main'); do
    grep -q $pod /proc/\$p/environ 2>/dev/null && echo \$p; done | head -1")
  NODE[$svc]=$node; PID[$svc]=$pid
  echo "$svc: $pod on $node, pid $pid in the node"
  docker exec "$node" py-spy dump --pid "$pid" --nonblocking 2>/dev/null |
    sed -nE 's/^Thread (0x[0-9a-f]+|[0-9]+) \((active|idle)\): "(.*)"$/\1 \3/p' > "$OUT/$LABEL-$svc.names" || true
  ticks "$node" "$pid" > "$OUT/$LABEL-$svc.t0"
  # two recorders on the same window: raw stacks for analysis, and a flame graph (SVG)
  docker exec "$node" py-spy record -p "$pid" -d "$SECS" -r 100 --nonblocking --gil --full-filenames \
    -f raw -o "/tmp/$LABEL-$svc.txt" > "$OUT/$LABEL-$svc.pyspy.log" 2>&1 &
  docker exec "$node" py-spy record -p "$pid" -d "$SECS" -r 100 --nonblocking --gil \
    -o "/tmp/$LABEL-$svc.svg" > /dev/null 2>&1 &
done
wait $(jobs -p | grep -v "^$k6pid\$") 2>/dev/null || true
for svc in "$@"; do
  node=${NODE[$svc]}; pid=${PID[$svc]}
  ticks "$node" "$pid" > "$OUT/$LABEL-$svc.t1"
  # /tmp in a Kind node is a tmpfs mount, which "docker cp" cannot see: stream the files out
  docker exec "$node" cat "/tmp/$LABEL-$svc.txt" > "$OUT/$LABEL-$svc.collapsed.txt"
  docker exec "$node" cat "/tmp/$LABEL-$svc.svg" > "$OUT/$LABEL-$svc.svg"
  hz=$(docker exec "$node" getconf CLK_TCK)
  {
    echo "CPU per thread over the ${SECS} s window (cores; py-spy thread names by pod-namespace id):"
    awk -v hz="$hz" -v s="$SECS" 'FILENAME ~ /names$/ {n[$1] = $2; for (i = 3; i <= NF; i++) n[$1] = n[$1] " " $i; next}
      FILENAME ~ /t0$/ {t0[$1] = $3; ns[$1] = $2; next}
      { c = ($3 - t0[$1]) / hz / s; tot += c; name = (ns[$1] in n) ? n[ns[$1]] : "(native thread)"
        printf "  %-34s tid %-6s %6.3f\n", name, ns[$1], c }
      END { printf "  %-45s %6.3f\n", "total", tot }' \
      "$OUT/$LABEL-$svc.names" "$OUT/$LABEL-$svc.t0" "$OUT/$LABEL-$svc.t1"
  } > "$OUT/$LABEL-$svc.threads.txt"
  rm -f "$OUT/$LABEL-$svc.names" "$OUT/$LABEL-$svc.t0" "$OUT/$LABEL-$svc.t1"
  echo "=== $svc"
  { grep -h 'Samples' "$OUT/$LABEL-$svc.pyspy.log" || cat "$OUT/$LABEL-$svc.pyspy.log"; } | sed 's/^/py-spy> /'; rm -f "$OUT/$LABEL-$svc.pyspy.log"
  cat "$OUT/$LABEL-$svc.threads.txt"
  python3 "$HERE/top_frames.py" "$OUT/$LABEL-$svc.collapsed.txt" --seconds "$SECS"
done
wait "$k6pid" || true
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/$LABEL-k6.txt" > /dev/null
echo "=== load during the profile"; cat "$OUT/$LABEL-k6.txt"
