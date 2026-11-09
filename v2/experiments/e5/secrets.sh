#!/usr/bin/env bash
# Secrets from OpenBao through the External Secrets Operator (chapter 6).
#   bash v2/experiments/e5/secrets.sh
#   1. the platform writes secret/insight/api-key and secret/shop/db-password (random test values;
#      only hashes are printed); how long until insight's Secret insight-api-key holds the value?
#   2. bob (team insight, his own certificate) creates an ExternalSecret for shop/db-password
#   3. rotation: bob's pod reads the key from a mounted file and from an environment variable every
#      2 s; the platform writes a new value - when does the Secret change, the file, the variable?
#   4. OpenBao's audit log: who read which path, and the refusal
#   5. ztunnel: is the traffic between External Secrets and OpenBao mutual TLS?
# Values reach OpenBao through stdin (the root token as well). bob's pod and ExternalSecret are deleted.
set -uo pipefail
S=$HOME/.lab-secrets/v2/openbao
U=$HOME/.lab-secrets/v2/users
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
as_bob() { kubectl --kubeconfig "$U/bob.kubeconfig" -n insight "$@"; }
trap 'as_bob delete pod key-reader --ignore-not-found --wait=false >/dev/null 2>&1; as_bob delete externalsecret steal-shop-db --ignore-not-found >/dev/null 2>&1' EXIT
h() { printf %s "$1" | sha256sum | cut -c1-12; }
put() {   # path value: as root, token and value through stdin
  { jq -r .root_token "$S/init.json"; printf '%s\n' "$2"; } |
    kubectl -n secrets exec -i openbao-0 -- sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; read -r V; bao kv put -mount=secret "$0" value="$V" >/dev/null' "$1"
}
k8s_hash() { kubectl -n insight get secret insight-api-key -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d | sha256sum | cut -c1-12; }
T0=$(date -u +%FT%TZ)
echo "== 0. stores: insight $(kubectl -n insight get secretstore openbao -o jsonpath='{.status.conditions[0].status}'), shop-dev $(kubectl -n shop-dev get secretstore openbao -o jsonpath='{.status.conditions[0].status}')"
A=$(openssl rand -hex 16); B=$(openssl rand -hex 16)
echo "== 1. $(date -u +%T) the platform writes insight/api-key ($(h "$A")...) and shop/db-password ($(h "$B")...)"
t=$(date +%s); put insight/api-key "$A"; put shop/db-password "$B"
for i in $(seq 1 60); do [ "$(k8s_hash)" = "$(h "$A")" ] && break; sleep 1; done
echo "  $(date -u +%T) insight/insight-api-key holds $(k8s_hash)... after $(( $(date +%s) - t )) s (refreshInterval 30 s)"
echo "== 2. $(date -u +%T) bob asks for team shop's database password"
as_bob apply -f - <<'YAML' 2>&1 | sed 's/^/  /'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: steal-shop-db}
spec:
  refreshInterval: 30s
  secretStoreRef: {name: openbao, kind: SecretStore}
  target: {name: steal-shop-db}
  data:
    - secretKey: password
      remoteRef: {key: shop/db-password, property: value}
YAML
sleep 15
as_bob get externalsecret steal-shop-db -o json | jq -r '"  status: \(.status.conditions[0].reason): \(.status.conditions[0].message)"' | cut -c1-300
echo "  Secret steal-shop-db exists: $(kubectl -n insight get secret steal-shop-db -o name 2>/dev/null || echo no)"
echo "== 3. rotation"
as_bob apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: key-reader}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: r
      image: $IMG
      command: ["python", "-c", "import hashlib, os, time\nwhile True:\n    f = hashlib.sha256(open('/etc/api-key/api-key', 'rb').read()).hexdigest()[:12]\n    e = hashlib.sha256(os.environ['API_KEY'].encode()).hexdigest()[:12]\n    print(time.strftime('%H:%M:%S'), 'file', f, 'env', e, flush=True)\n    time.sleep(2)"]
      env: [{name: API_KEY, valueFrom: {secretKeyRef: {name: insight-api-key, key: api-key}}}]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      volumeMounts: [{name: key, mountPath: /etc/api-key, readOnly: true}]
  volumes: [{name: key, secret: {secretName: insight-api-key}}]
YAML
as_bob wait --for=condition=Ready pod/key-reader --timeout=120s >/dev/null
sleep 4
A2=$(openssl rand -hex 16)
echo "  $(date -u +%T) the platform writes a new value ($(h "$A2")...)"
t=$(date +%s); put insight/api-key "$A2"
for i in $(seq 1 90); do [ "$(k8s_hash)" = "$(h "$A2")" ] && break; sleep 1; done
echo "  $(date -u +%T) Secret updated after $(( $(date +%s) - t )) s"
for i in $(seq 1 60); do as_bob logs key-reader | grep -q "file $(h "$A2")" && break; sleep 2; done
as_bob logs key-reader | awk -v n="$(h "$A2")" '$3 == n && !s {print "  " $0 "   <- first line with the new value in the file"; s = 1} END {print "  last line: " $0}'
echo "  (old value $(h "$A")..., new value $(h "$A2")...)"
echo "== 4. OpenBao's audit log since $T0: requests to secret paths"
kubectl -n secrets logs openbao-0 --since-time="$T0" | grep '"type":"response"' |
  jq -r 'select(.request.path | startswith("secret/")) | "  \(.time[11:19]) \(.auth.display_name // "-") (\(.auth.metadata.service_account_namespace // "-")/\(.auth.metadata.service_account_name // "-")) \(.request.operation) \(.request.path) \(if .error then "ERROR " + .error else "ok" end)"' |
  sort | uniq -c | sed 's/^ *//' | cut -c1-220
echo "== 5. ztunnel on the OpenBao node: inbound connections to OpenBao"
node=$(kubectl -n secrets get pod openbao-0 -o jsonpath='{.spec.nodeName}')
zt=$(kubectl -n istio-system get pods -l app=ztunnel --field-selector spec.nodeName="$node" -o jsonpath='{.items[0].metadata.name}')
kubectl -n istio-system logs "$zt" --since-time="$T0" | grep 'dst.workload="openbao-0"' | tail -2 |
  grep -o -E 'src.identity="[^"]*"|dst.identity="[^"]*"|direction="[^"]*"' | sort | uniq -c | sed 's/^/  /'
