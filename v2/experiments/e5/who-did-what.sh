#!/usr/bin/env bash
# Real requests with the lab users' own certificates, then the same story told by the API
# server's audit log alone: who, as whom, did what, to which object, allowed or not, and why.
#   T0=<RFC3339, optional> bash v2/experiments/e5/who-did-what.sh <label>
# Destructive requests that should be denied use --dry-run=server: authorization and auditing
# happen exactly as for a real request, but nothing would change even if a role were wrong.
# A test Secret (random value) is created in shop-dev by the admin; only hashes of it are printed.
# Everything the script creates in shop-dev is deleted at the end (by alice, who may).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; OUT="$ROOT/v2/evidence/e5/$LABEL"; mkdir -p "$OUT"
U=$HOME/.lab-secrets/v2/users
T0=${T0:-$(date -u +%FT%T.%3NZ)}
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
as() { local u=$1; shift; kubectl --kubeconfig "$U/$u.kubeconfig" "$@"; }
step() {   # user description command...
  local u=$1 d=$2 out rc; shift 2
  printf "%s %-16s %s\n" "$(date -u +%T)" "$u" "$d"
  if [ "$u" = admin ]; then out=$(kubectl "$@" 2>&1); rc=$?; else out=$(as "$u" "$@" 2>&1); rc=$?; fi
  printf "%s\n" "$out" | head -4 | cut -c1-260 | sed 's/^/      | /'
  echo "      -> exit $rc"
}
POD=$(kubectl -n storefront get pods -l app.kubernetes.io/name=catalog -o jsonpath='{.items[0].metadata.name}')
VAL=$(openssl rand -hex 16)
kubectl -n shop-dev create secret generic demo-credentials --from-literal=password="$VAL" >/dev/null
echo "== test Secret shop-dev/demo-credentials created by the admin; sha256 of its value: $(printf %s "$VAL" | sha256sum | cut -c1-12)..."
echo "== actions (T0 $T0)"
step alice "list pods in storefront (prod, viewer)"            -n storefront get pods -o name
step alice "delete a storefront pod (dry run)"                 -n storefront delete pod "$POD" --dry-run=server
step alice "read a Secret in storefront"                       -n storefront get secrets -o name
step alice "deployment without securityContext in shop-dev"    -n shop-dev create deployment psa-demo --image="$IMG" -- python -c "import time; time.sleep(3600)"
sleep 3
step admin "why psa-demo has no pods (ReplicaSet events)"      -n shop-dev get events --field-selector reason=FailedCreate -o custom-columns=MSG:.message --no-headers
step alice "read the Secret in shop-dev directly"              -n shop-dev get secret demo-credentials -o name
as alice -n shop-dev apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: secret-reader}
spec:
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: r
      image: $IMG
      command: ["python", "-c", "import hashlib, os; print('sha256 of the mounted value:', hashlib.sha256(os.environ['P'].encode()).hexdigest()[:12] + '...')"]
      env: [{name: P, valueFrom: {secretKeyRef: {name: demo-credentials, key: password}}}]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
YAML
echo "$(date -u +%T) alice            created pod secret-reader in shop-dev (env from Secret demo-credentials)"
as alice -n shop-dev wait --for=jsonpath='{.status.phase}'=Succeeded pod/secret-reader --timeout=90s >/dev/null 2>&1
step alice "read the pod's log"                                -n shop-dev logs secret-reader
step alice "grant tenant-viewer in shop-dev to bob"            -n shop-dev create rolebinding bob-viewer --clusterrole=tenant-viewer --user=bob
step alice "grant cluster-admin in shop-dev to herself (dry run)" -n shop-dev create rolebinding alice-admin --clusterrole=cluster-admin --user=alice --dry-run=server
step alice "delete the namespace's quota (dry run)"            -n shop-dev delete resourcequota tenant --dry-run=server
step alice "list pods in insight"                              -n insight get pods -o name
step bob   "list pods in storefront"                           -n storefront get pods -o name
step bob   "list pods in shop-dev (after alice's grant)"       -n shop-dev get pods -o name
step carol "exec into a storefront pod"                        -n storefront exec "$POD" -- python -c "print('carol was here')"
step carol "read a Secret in storefront"                       -n storefront get secrets -o name
step carol-breakglass "read the Secret in shop-dev (break-glass)" -n shop-dev get secret demo-credentials -o name
step dave  "list RoleBindings in all namespaces"               get rolebindings -A -o name
step dave  "delete a storefront pod (dry run)"                 -n storefront delete pod "$POD" --dry-run=server
step admin "list storefront pods as alice (impersonation)"     --as=alice --as-group=team-shop -n storefront get pods -o name
echo "== cleanup by alice"
as alice -n shop-dev delete deployment psa-demo --wait=false >/dev/null 2>&1
as alice -n shop-dev delete pod secret-reader --wait=false >/dev/null 2>&1
as alice -n shop-dev delete rolebinding bob-viewer >/dev/null 2>&1
kubectl -n shop-dev delete secret demo-credentials >/dev/null
sleep 5
echo "== the audit log's account of the same minutes (users, impersonation, Argo CD in insight)"
docker exec ent-control-plane sh -c 'cat /var/log/kubernetes/audit/audit.log' |
  grep -E '"username":"(alice|bob|carol|dave|system:serviceaccount:argocd:argocd-application-controller)"|"impersonatedUser"' |
  jq -c --arg t0 "$T0" 'select(.stage == "ResponseComplete" and .requestReceivedTimestamp >= $t0)
    | select(.user.username != "system:serviceaccount:argocd:argocd-application-controller"
             or (.objectRef.namespace == "insight" and (.verb | test("create|update|patch|delete"))))' > "$OUT/audit.jsonl"
jq -r '[(.requestReceivedTimestamp[11:23]),
        (.user.username | sub("system:serviceaccount:argocd:"; "sa:argocd:")),
        ((.user.groups // []) | map(select(startswith("system:") | not)) | join(",")),
        (if .impersonatedUser then "as " + .impersonatedUser.username else "-" end),
        .verb,
        ((.objectRef.resource // "-") + (if .objectRef.subresource then "/" + .objectRef.subresource else "" end)),
        ((.objectRef.namespace // "-") + "/" + (.objectRef.name // "*")),
        (.responseStatus.code | tostring),
        (.annotations["authorization.k8s.io/decision"] // "-"),
        ((.annotations["authorization.k8s.io/reason"] // "") | sub("RBAC: allowed by "; "") | .[0:90])]
       | @tsv' "$OUT/audit.jsonl" | column -t -s $'\t'
echo "== Pod Security annotations recorded by the audit log"
jq -r 'select(.annotations | to_entries | map(select(.key | startswith("pod-security"))) | length > 0)
       | "\(.requestReceivedTimestamp[11:19]) \(.user.username) \(.verb) \(.objectRef.resource)/\(.objectRef.name // "*"): " +
         (.annotations | to_entries | map(select(.key | startswith("pod-security"))) | map("\(.key)=\(.value)") | join("; ") | .[0:300])' "$OUT/audit.jsonl"
echo "== events: $(wc -l < "$OUT/audit.jsonl") audit records in $OUT/audit.jsonl"
