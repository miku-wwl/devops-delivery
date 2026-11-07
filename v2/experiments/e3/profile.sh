#!/usr/bin/env bash
# Profile one storefront pod under load with py-spy, from the node, without touching the pod.
#   bash v2/experiments/e3/profile.sh <service> <seconds> <label>
# py-spy (a sampling profiler for Python) is downloaded once from PyPI and checked against the
# SHA-256 that PyPI publishes. It runs inside the Kind node container that hosts the pod: the
# node container is privileged and sees the pod's processes, so the pod itself needs no extra
# capability, no restart and no code change. Output: a flame graph (SVG) and collapsed stacks.
set -euo pipefail
SVC=${1:?service}; SECS=${2:-30}; LABEL=${3:?label}
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
POD=$(kubectl -n storefront get pods -l app.kubernetes.io/name="$SVC" -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl -n storefront get pod "$POD" -o jsonpath='{.spec.nodeName}')
docker cp "$TOOLS/py-spy-$VER" "$NODE:/usr/local/bin/py-spy" >/dev/null
PID=$(docker exec "$NODE" sh -c "for p in \$(pgrep -f 'storefront.$SVC.main'); do
  grep -q $POD /proc/\$p/environ 2>/dev/null && echo \$p; done | head -1")
echo "profiling $POD on $NODE, pid $PID in the node, ${SECS}s at 100 Hz"
docker exec "$NODE" py-spy record -p "$PID" -d "$SECS" -r 100 --nonblocking -f raw -o "/tmp/$LABEL.txt" 2>&1 | tail -2
docker exec "$NODE" py-spy record -p "$PID" -d "$SECS" -r 100 --nonblocking -o "/tmp/$LABEL.svg" 2>&1 | tail -1
# /tmp in a Kind node is a tmpfs mount, which "docker cp" cannot see: stream the files out
docker exec "$NODE" cat "/tmp/$LABEL.txt" > "$OUT/$LABEL.collapsed.txt"
docker exec "$NODE" cat "/tmp/$LABEL.svg" > "$OUT/$LABEL.svg"
python3 "$HERE/top_frames.py" "$OUT/$LABEL.collapsed.txt"
