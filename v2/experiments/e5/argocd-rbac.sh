#!/usr/bin/env bash
# Argo CD's RBAC, checked offline: every row of argocd-rbac.tsv is asked with
# "argocd admin settings rbac can" inside the argocd-server pod (it reads argocd-rbac-cm from the
# cluster; no login, no password). Groups as in Kubernetes; "g" lines map them to roles.
#   bash v2/experiments/e5/argocd-rbac.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# stdout only: the CLI logs a JSON warning on stderr (the built-in role:admin is "not found in policies"),
# and kubectl reports a "no" (exit code 1) on stderr - the first run parsed those lines (argocd-rbac-1.log)
A() { kubectl -n argocd exec deploy/argocd-server -- argocd admin settings rbac "$@" --namespace argocd 2>/dev/null; }
echo "== policy check: $(A validate | tr '
' ' ')"
n=0; bad=0
printf "%-13s %-7s %-13s %-36s %-4s %-4s %s\n" subject action resource object want got result
while IFS=$'\t' read -r sub act res obj want; do
  case "$sub" in ''|'#'*) continue;; esac
  got=$(A can "$sub" "$act" "$res" "$obj" | grep -x -i -E "yes|no" | tr 'A-Z' 'a-z')
  n=$((n + 1)); r=ok; [ "$got" = "$want" ] || { r=MISMATCH; bad=$((bad + 1)); }
  printf "%-13s %-7s %-13s %-36s %-4s %-4s %s\n" "$sub" "$act" "$res" "$obj" "$want" "$got" "$r"
done < "$HERE/argocd-rbac.tsv"
echo "== $n checks, $((n - bad)) as expected, $bad mismatches"
[ "$bad" -eq 0 ]
