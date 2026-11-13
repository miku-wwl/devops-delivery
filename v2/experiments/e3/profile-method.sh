#!/usr/bin/env bash
# The facts behind the profiling method of chapter 4, recorded on one gateway pod (no load):
#   bash v2/experiments/e3/profile-method.sh
# 1. thread ids: the node sees the pod's threads under the node's PID namespace; the interpreter
#    (and so py-spy dump) reports the ids of the pod's namespace - py-spy cannot match them;
# 2. idle samples: 5 s of py-spy in default mode against 5 s with --gil, both on the idle pod;
# 3. the listen sockets in the pod's network namespace: ztunnel's (backlog 128) and uvicorn's;
# 4. FastAPI's own telemetry wrapper: the lines that pass a request through untouched.
set -euo pipefail
POD=$(kubectl -n storefront get pods -l app.kubernetes.io/name=gateway -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl -n storefront get pod "$POD" -o jsonpath='{.spec.nodeName}')
PID=$(docker exec "$NODE" sh -c "for p in \$(pgrep -f 'storefront.gateway.main'); do
  grep -q $POD /proc/\$p/environ 2>/dev/null && echo \$p; done | head -1")
docker cp "$HOME/ent-data/tools/py-spy-0.4.2" "$NODE:/usr/local/bin/py-spy" > /dev/null   # see profile.sh
echo "== $POD on $NODE, pid $PID in the node"
echo "-- threads: id in the node, NSpid (node, pod), name"
docker exec "$NODE" sh -c "for t in /proc/$PID/task/*; do echo \$(basename \$t) \$(grep NSpid \$t/status | cut -f2-) \$(cat \$t/comm); done"
echo "-- py-spy dump (thread ids as the interpreter reports them)"
docker exec "$NODE" py-spy dump --pid "$PID" --nonblocking 2>&1 | grep -E '^Thread'
echo "-- 5 s idle, default mode vs --gil"
docker exec "$NODE" py-spy record -p "$PID" -d 5 -r 100 --nonblocking -f raw -o /tmp/idle-all.txt 2>&1 | grep -o 'Samples: [0-9]* Errors: [0-9]*'
docker exec "$NODE" py-spy record -p "$PID" -d 5 -r 100 --nonblocking --gil -f raw -o /tmp/idle-gil.txt 2>&1 | grep -o 'Samples: [0-9]* Errors: [0-9]*'
echo "-- listen sockets in the pod's network namespace (Send-Q = backlog)"
docker exec "$NODE" nsenter -t "$PID" -n ss -ltn
echo "-- fastapi/telemetry/_asgi.py: the pass-through when nothing is configured"
kubectl -n storefront exec "$POD" -c app -- python -c "
import inspect, fastapi, fastapi.telemetry._asgi as t
print('fastapi', fastapi.__version__)
for i, l in enumerate(inspect.getsource(t).splitlines(), 1):
    if 260 <= i <= 275: print(i, l)"
