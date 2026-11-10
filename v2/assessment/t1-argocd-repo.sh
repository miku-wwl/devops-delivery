#!/usr/bin/env bash
# T1 (E12, chapter 13) - "a change merged ten minutes ago has not reached the cluster".
#   bash v2/assessment/t1-argocd-repo.sh inject|grade|restore
# inject: the password of Argo CD's repository secret repo-platform-gitops (applied by bootstrap.sh,
# not by Argo CD - selfHeal does not repair it) becomes a random string; every application is told to
# refresh. The candidate gets only the sentence above.
# grade: the secret holds the valid read token again (compared by hash), no application reports a
# ComparisonError, all applications Synced and Healthy.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TOK="$HOME/.lab-secrets/v2/platform-gitops-read-token"
refresh() { kubectl -n argocd get applications -o name | xargs -r -I{} kubectl -n argocd annotate {} argocd.argoproj.io/refresh=hard --overwrite >/dev/null; }
pw_ok() { [ "$(kubectl -n argocd get secret repo-platform-gitops -o jsonpath='{.data.password}' | base64 -d | sha256sum)" = "$(tr -d '\n' < "$TOK" | sha256sum)" ]; }
no_comparison_error() { [ "$(kubectl -n argocd get applications -o json | jq '[.items[].status.conditions[]? | select(.type == "ComparisonError")] | length')" = 0 ]; }
case ${1:?inject|grade|restore} in
inject)
  kubectl -n argocd patch secret repo-platform-gitops -p "{\"stringData\":{\"password\":\"e12-$(openssl rand -hex 8)\"}}" >/dev/null
  refresh
  echo "$(now) T1 injected - candidate: \"a change merged ten minutes ago has not reached the cluster\"" ;;
grade)
  echo "== $(now) T1 grade"
  refresh; wait_for 180 no_comparison_error; wait_for 240 apps_healthy
  check "the repository secret holds the valid read token (compared by hash)" pw_ok
  check "no application reports a ComparisonError" no_comparison_error
  check "all applications Synced and Healthy" apps_healthy
  verdict ;;
restore)   # the token travels through stdin (a manifest), as in bootstrap.sh
  kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-platform-gitops
  namespace: argocd
  labels: {argocd.argoproj.io/secret-type: repository}
stringData:
  type: git
  url: http://gitlab:8929/root/platform-gitops.git
  username: argocd
  password: $(tr -d '\n' < "$TOK")
EOF
  refresh; echo "$(now) T1 restored" ;;
esac
