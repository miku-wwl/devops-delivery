#!/usr/bin/env bash
# Run the RBAC test matrix as the real users: every row of rbac-matrix.tsv is asked with that
# user's own client certificate (kubectl auth can-i -> a SelfSubjectAccessReview), so the answer
# comes from the API server's authorizer for exactly that identity and its groups.
#   bash v2/experiments/e5/rbac-matrix.sh [matrix.tsv]
# Prints one line per check and the number of mismatches; exits 1 if any answer differs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M=${1:-$HERE/rbac-matrix.tsv}
U=$HOME/.lab-secrets/v2/users
n=0; bad=0
printf "%-16s %-11s %-28s %-11s %-4s %-4s %s\n" user verb resource namespace want got result
while IFS=$'\t' read -r user verb res ns want why; do
  case "$user" in ''|'#'*) continue;; esac
  [ -f "$U/$user.kubeconfig" ] || { echo "missing $U/$user.kubeconfig (run platform/tenants/users.sh)"; exit 2; }
  case "$ns" in
    -) scope=();;
    '*') scope=(--all-namespaces);;
    *) scope=(-n "$ns");;
  esac
  # res:sub is a subresource (pods:exec -> pods --subresource exec); res/name is one named object.
  # (kubectl auth can-i reads "pods/exec" as the pod NAMED exec - the first run's mistake.)
  r=$res; sub=()
  case "$res" in *:*) r=${res%%:*}; sub=(--subresource "${res#*:}");; esac
  got=$(kubectl --kubeconfig "$U/$user.kubeconfig" auth can-i "$verb" "$r" "${sub[@]}" "${scope[@]}" 2>/dev/null); got=${got:-error}
  n=$((n + 1)); r=ok
  [ "$got" = "$want" ] || { r="MISMATCH ($why)"; bad=$((bad + 1)); }
  printf "%-16s %-11s %-28s %-11s %-4s %-4s %s\n" "$user" "$verb" "$res" "$ns" "$want" "$got" "$r"
done < "$M"
echo "== $n checks, $((n - bad)) as expected, $bad mismatches"
[ "$bad" -eq 0 ]
