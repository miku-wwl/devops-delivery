#!/usr/bin/env bash
# Lab users with x509 client certificates, issued by the cluster's own CA through the CSR API.
#   bash v2/platform/tenants/users.sh               # the four standing users (7 days)
#   bash v2/platform/tenants/users.sh break-glass   # carol with the break-glass group (1 hour)
# Users and groups (the certificate's O= fields become the user's groups):
#   alice  team-shop       developer of the storefront team
#   bob    team-insight    developer of the insight team
#   carol  platform-sre    platform operator; "carol-breakglass" adds the group break-glass
#   dave   auditors        read-only auditor
# Keys, certificates and kubeconfigs are written to ~/.lab-secrets/v2/users/ (mode 600) and never
# leave it; this script prints only subjects, groups, expiry and certificate fingerprints.
# Kubernetes cannot revoke a client certificate before it expires (no revocation list): the
# expiry is the only limit, so it is short. Production clusters use OIDC instead (chapter 6).
set -euo pipefail
U=$HOME/.lab-secrets/v2/users
mkdir -p "$U"; chmod 700 "$U"
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
issue() {   # file-name username seconds group...
  local file=$1 user=$2 secs=$3; shift 3
  local subj="/CN=$user" g csr=e5-user-$file
  for g in "$@"; do subj="$subj/O=$g"; done
  [ -f "$U/$file.key" ] || (umask 077; openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$U/$file.key" 2>/dev/null)
  openssl req -new -key "$U/$file.key" -subj "$subj" -out "$U/$file.csr" 2>/dev/null
  kubectl delete csr "$csr" --ignore-not-found >/dev/null
  kubectl apply -f - >/dev/null <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: $csr, labels: {app.kubernetes.io/part-of: e5-users}}
spec:
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $secs
  usages: [client auth]
  request: $(base64 -w0 < "$U/$file.csr")
YAML
  kubectl certificate approve "$csr" >/dev/null
  for _ in $(seq 1 20); do
    kubectl get csr "$csr" -o jsonpath='{.status.certificate}' | base64 -d > "$U/$file.crt" 2>/dev/null || true
    [ -s "$U/$file.crt" ] && break; sleep 1
  done
  [ -s "$U/$file.crt" ] || { echo "no certificate issued for $file"; return 1; }
  kubectl delete csr "$csr" >/dev/null
  (umask 077; cat > "$U/$file.kubeconfig" <<KC
apiVersion: v1
kind: Config
clusters: [{name: ent, cluster: {server: $SERVER, certificate-authority-data: $CA}}]
users: [{name: $file, user: {client-certificate: $U/$file.crt, client-key: $U/$file.key}}]
contexts: [{name: $file@ent, context: {cluster: ent, user: $file}}]
current-context: $file@ent
KC
  )
  rm -f "$U/$file.csr"; chmod 600 "$U/$file".*
  printf "  %-17s %-36s until %s  sha256 %s\n" "$file" "$(openssl x509 -in "$U/$file.crt" -noout -subject -nameopt compat | sed 's/^subject=//')" \
    "$(date -u -d "$(openssl x509 -in "$U/$file.crt" -noout -enddate | cut -d= -f2)" +%FT%TZ)" \
    "$(openssl x509 -in "$U/$file.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d : | cut -c1-16)"
}
echo "== client certificates from the cluster CA (kubeconfigs in ~/.lab-secrets/v2/users/)"
if [ "${1:-}" = break-glass ]; then
  issue carol-breakglass carol 3600 platform-sre break-glass
else
  issue alice alice 604800 team-shop
  issue bob bob 604800 team-insight
  issue carol carol 604800 platform-sre
  issue dave dave 604800 auditors
fi
