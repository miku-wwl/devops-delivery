#!/usr/bin/env bash
# Admission policy: what is decided where, how fast, and what happens while the policy engine is down.
#   bash v2/experiments/e5/admission.sh
# Namespaces: shop-dev (tenant: Kyverno policy "tenant-pods", Pod Security "restricted",
# LimitRange) and e5-native (created here: Pod Security "restricted" and a ValidatingAdmissionPolicy
# with the same image rule written in CEL - built into the API server, no webhook). Every pod is
# created with --dry-run=server: admission runs completely, nothing is stored.
#   1. six pods in both namespaces: who admits or denies each, with which message
#   2. latency: 40 more admissions per namespace; mean admission time from the API server's metrics
#   3. the Kyverno admission controller (one replica) is restarted; a probe creates a valid pod every
#      second in shop-dev, storefront (no Kyverno policy applies there) and e5-native for 75 s
#   4. a new namespace with the label "tenant": how fast do the generated defaults appear?
# The ValidatingAdmissionPolicy, its binding and the namespaces e5-native and e5-team-c are deleted.
set -uo pipefail
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
cleanup() {
  kubectl delete validatingadmissionpolicybinding e5-native-images --ignore-not-found >/dev/null 2>&1
  kubectl delete validatingadmissionpolicy e5-native-images --ignore-not-found >/dev/null 2>&1
  kubectl delete ns e5-native e5-team-c --ignore-not-found --wait=false >/dev/null 2>&1
}
trap cleanup EXIT
kubectl wait --for=delete ns/e5-native ns/e5-team-c --timeout=180s >/dev/null 2>&1
kubectl create ns e5-native >/dev/null
kubectl label ns e5-native e5-admission=native pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest >/dev/null
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: {name: e5-native-images}
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules: [{apiGroups: [""], apiVersions: [v1], operations: [CREATE, UPDATE], resources: [pods]}]
  variables:
    - name: images
      expression: "object.spec.containers.map(c, c.image) + (has(object.spec.initContainers) ? object.spec.initContainers.map(c, c.image) : [])"
  validations:
    - expression: "variables.images.all(i, i.startsWith('localhost:5001/') && i.substring(15).contains(':') && !i.endsWith(':latest'))"
      message: "Images must be localhost:5001/<name>:<tag> - the platform registry, a fixed tag, not :latest."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: {name: e5-native-images}
spec:
  policyName: e5-native-images
  validationActions: [Deny]
  matchResources:
    namespaceSelector: {matchLabels: {e5-admission: native}}
YAML
sleep 5
pod() {   # name image securityContext(yes/no) resources(yes/no)
  local sc="" csc="" res=""
  [ "$3" = yes ] && sc='  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}' &&
    csc='      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}'
  [ "$4" = yes ] && res='      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}'
  printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: %s}\nspec:\n%s\n  containers:\n    - name: c\n      image: %s\n      command: ["python", "-c", "print(1)"]\n%s\n%s\n' "$1" "$sc" "$2" "$csc" "$res"
}
admit() {   # ns name image sc res -> one line
  local out
  out=$(pod "$2" "$3" "$4" "$5" | kubectl -n "$1" create --dry-run=server -o json -f - 2>&1)
  if printf "%s" "$out" | jq -e .metadata >/dev/null 2>&1; then
    echo "admitted (resources after admission: $(printf "%s" "$out" | jq -c '.spec.containers[0].resources'))"
  else
    printf "%s" "$out" | tr '\n' ' ' | sed -E 's/^Error from server( \([A-Za-z]+\))?: //' | cut -c1-230
  fi
}
echo "== 1. who decides (image $IMG)"
REG=${IMG%:*}
for ns in shop-dev e5-native; do
  echo "-- $ns"
  printf "  %-34s %s\n" "valid pod"                 "$(admit "$ns" ok "$IMG" yes yes)"
  printf "  %-34s %s\n" "image from docker.io"      "$(admit "$ns" foreign docker.io/library/busybox:1.37 yes yes)"
  printf "  %-34s %s\n" "tag :latest"               "$(admit "$ns" latest "$REG:latest" yes yes)"
  printf "  %-34s %s\n" "no tag"                    "$(admit "$ns" notag "$REG" yes yes)"
  printf "  %-34s %s\n" "no resources stated"       "$(admit "$ns" nores "$IMG" yes no)"
  printf "  %-34s %s\n" "no securityContext"        "$(admit "$ns" nosc "$IMG" no yes)"
done
echo "== 2. admission time: 40 valid pods per namespace, means from the API server's metrics"
metrics() { kubectl get --raw /metrics | grep -E '^apiserver_(admission_webhook_admission_duration_seconds|validating_admission_policy_check_duration_seconds)_(sum|count)' ; }
metrics > /tmp/e5-m0
for i in $(seq 1 40); do pod "l$i" "$IMG" yes yes | kubectl -n shop-dev create --dry-run=server -f - >/dev/null 2>&1; pod "l$i" "$IMG" yes yes | kubectl -n e5-native create --dry-run=server -f - >/dev/null 2>&1; done
metrics > /tmp/e5-m1
python3 - /tmp/e5-m0 /tmp/e5-m1 <<'PY'
import re, sys
def load(p):
    d = {}
    for line in open(p):
        name, val = line.rsplit(" ", 1)
        d[name] = float(val)
    return d
a, b = load(sys.argv[1]), load(sys.argv[2])
groups = {}
for k in b:
    if not k.endswith("}") or "_count{" not in k:
        continue
    n = b[k] - a.get(k, 0)
    if n <= 0:
        continue
    s = b[k.replace("_count{", "_sum{")] - a.get(k.replace("_count{", "_sum{"), 0)
    label = re.sub(r'^apiserver_', '', k.split("_count{")[0]) + " " + ",".join(
        x for x in re.findall(r'(\w+="[^"]*")', k) if x.split("=")[0] in ("name", "policy", "operation", "rejected", "type", "enforcement_action"))
    print(f"  {label}: {int(n)} calls, mean {1000 * s / n:.2f} ms")
PY
rm -f /tmp/e5-m0 /tmp/e5-m1
echo "== 3. the Kyverno admission controller restarts; a valid pod every second in three namespaces"
OLD=$(kubectl -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o jsonpath='{.items[0].metadata.name}')
echo "  $(date -u +%T.%3N) deleting $OLD"
kubectl -n kyverno delete pod "$OLD" --wait=false >/dev/null
for i in $(seq 1 75); do
  line="$(date -u +%T)"
  for ns in shop-dev storefront e5-native; do
    if pod "p$i" "$IMG" yes yes | kubectl -n "$ns" create --dry-run=server -f - >/dev/null 2>/tmp/e5-err; then r=ok; else r="FAIL($(grep -o -E 'failed calling webhook "[^"]*"|no endpoints available|connection refused|context deadline exceeded|denied the request' /tmp/e5-err | head -1))"; fi
    line="$line $ns=$r"
  done
  echo "  $line"
  sleep 1
done | awk '{sig = $2 " " $3 " " $4} sig != prev {print; prev = sig; n = 0} {n++} END {print "  (" NR " samples; lines are printed when a result changes)"}'
rm -f /tmp/e5-err
kubectl -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o jsonpath='  new admission controller {.items[0].metadata.name}, started {.items[0].status.startTime}, ready {.items[0].status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}'
echo "== 4. a new tenant namespace: how fast the generated defaults appear"
t0=$(date +%s.%N)
kubectl create ns e5-team-c >/dev/null; kubectl label ns e5-team-c tenant=team-c >/dev/null
for i in $(seq 1 60); do
  n=$(( $(kubectl -n e5-team-c get networkpolicy --no-headers 2>/dev/null | wc -l) + $(kubectl -n e5-team-c get resourcequota,limitrange --no-headers 2>/dev/null | wc -l) ))
  [ "$n" -ge 4 ] && break; sleep 0.5
done
printf "  %d of 4 objects after %.1f s\n" "$n" "$(echo "$(date +%s.%N) - $t0" | bc)"
kubectl -n e5-team-c get networkpolicy,resourcequota,limitrange -o custom-columns=KIND:.kind,NAME:.metadata.name,MANAGED-BY:.metadata.labels.app\\.kubernetes\\.io/managed-by --no-headers | sed 's/^/  /'
