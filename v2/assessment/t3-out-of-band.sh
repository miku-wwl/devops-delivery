#!/usr/bin/env bash
# T3 (E12, chapter 13) - "checkout fails, browsing works, Git and Argo CD say everything is in order".
#   bash v2/assessment/t3-out-of-band.sh inject|grade|restore
# inject: an Istio AuthorizationPolicy (DENY everything to payments) applied by hand - outside Git, so
# Argo CD neither shows nor removes it; ztunnel enforces it on new connections, so the payments pods are
# replaced (their old connections would outlive the policy, chapter 6).
# grade: no object in storefront that Argo CD does not track (AuthorizationPolicy, NetworkPolicy);
# 5 checkouts in a row work, browsing works, all applications Synced and Healthy.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
clean() { [ -z "$(untracked storefront authorizationpolicies.security.istio.io)$(untracked storefront networkpolicies)" ]; }
case ${1:?inject|grade|restore} in
inject)
  kubectl -n storefront apply -f - >/dev/null <<'EOF'
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: {name: e12-quarantine, namespace: storefront}
spec:
  selector: {matchLabels: {app.kubernetes.io/name: payments}}
  action: DENY
  rules: [{}]
EOF
  kubectl -n storefront delete pod -l app.kubernetes.io/name=payments --wait=false >/dev/null
  echo "$(now) T3 injected - candidate: \"checkout fails, browsing works, Git and Argo CD say everything is in order\"" ;;
grade)
  echo "== $(now) T3 grade"
  wait_for 120 checkout_ok 5
  check "no object in storefront outside Git (untracked AuthorizationPolicy or NetworkPolicy)" clean
  check "5 checkouts in a row answered 2xx or 402" checkout_ok 5
  check "browsing answers 200" browse_ok
  check "all applications Synced and Healthy" apps_healthy
  verdict ;;
restore)
  kubectl -n storefront delete authorizationpolicy e12-quarantine --ignore-not-found >/dev/null
  echo "$(now) T3 restored" ;;
esac
