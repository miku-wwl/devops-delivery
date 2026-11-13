#!/bin/sh
# Render what Argo CD will deploy, the way the ApplicationSet does it (platform/apps/storefront.yaml):
# chart charts/storefront-service, release name = service, values envs/<env>/storefront/common.yaml
# + envs/<env>/storefront/services/<service>.yaml. The tenants' manifests are copied as they are.
#   sh ci/render.sh          # -> rendered/<env>/<service>.yaml, rendered/tenants/
set -eu
rm -rf rendered
for envdir in envs/*/storefront; do
  env=$(basename "$(dirname "$envdir")")
  mkdir -p "rendered/$env"
  for f in "$envdir"/services/*.yaml; do
    svc=$(basename "$f" .yaml)
    helm template "$svc" charts/storefront-service -f "$envdir/common.yaml" -f "$f" > "rendered/$env/$svc.yaml"
  done
  echo "$env: $(ls "rendered/$env" | wc -l) releases rendered"
done
# E11: Argo CD's own chart, at the version of platform/apps/argocd.yaml, with its values - a chart
# upgrade that rejects our values fails here, before the merge
V=$(awk '/chart: argo-cd/ {f = 1} f && /targetRevision:/ {print $2; exit}' platform/apps/argocd.yaml)
mkdir -p rendered/platform
helm template argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$V" -n argocd \
  -f bootstrap/argocd-values.yaml > rendered/platform/argocd.yaml
echo "argo-cd $V: $(grep -c '^kind:' rendered/platform/argocd.yaml) objects rendered"
mkdir -p rendered/tenants
for d in tenants/*/; do cp "$d"*.yaml rendered/tenants/; done
echo "tenants: $(ls rendered/tenants | wc -l) manifests"
