#!/usr/bin/env bash
# Change the desired state of an environment through a merge request in the
# GitOps configuration repository - the only way deployments happen in this lab.
#
#   bash delivery/argocd/promote.sh <env> <change>... [--merge] [--title "..."]
#
#   bash delivery/argocd/promote.sh prod image.tag=0.1.1 --merge
#   bash delivery/argocd/promote.sh prod image.digest=sha256:... --merge
#   bash delivery/argocd/promote.sh prod faults.errorRate:=0.5 --merge --title "tune retries"
#   bash delivery/argocd/promote.sh prod @/abs/path/patch.yaml --merge
#
# key=value sets a YAML string; key:=raw sets a raw YAML value (numbers, booleans);
# @file.yaml deep-merges a YAML patch (e.g. delivery/gitops/patches/prod-rollout.yaml).
# Prints the merge request and, with --merge, the merge commit Argo CD will sync.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

env="${1:?usage: promote.sh <env> <change>... [--merge] [--title text]}"; shift
merge=false; title=""; changes=()
while [ $# -gt 0 ]; do
  case "$1" in
    --merge) merge=true ;;
    --title) title="$2"; shift ;;
    *) changes+=("$1") ;;
  esac
  shift
done
[ ${#changes[@]} -gt 0 ] || { echo "no changes given" >&2; exit 2; }

branch="change/${env}-$(date +%Y%m%d%H%M%S)"
clone_on_branch "$branch"
file="$WORK/envs/${env}/values.yaml"
[ -f "$file" ] || { echo "unknown environment: $env" >&2; exit 2; }
for c in "${changes[@]}"; do
  if [[ "$c" == @* ]]; then
    yq -i ". *= load(\"${c#@}\")" "$file"            # deep-merge a YAML patch
  elif [[ "$c" == *":="* ]]; then
    key="${c%%:=*}" val="${c#*:=}"; yq -i ".${key} = ${val}" "$file"
  else
    key="${c%%=*}" val="${c#*=}"; yq -i ".${key} = \"${val}\"" "$file"
  fi
done
git -C "$WORK" diff --stat
git -C "$WORK" diff -U1 -- "envs/${env}/values.yaml" | sed -n '5,$p'

parts=()
for c in "${changes[@]}"; do
  if [[ "$c" == @* ]]; then parts+=("@$(basename "${c#@}")"); else parts+=("$c"); fi
done
summary="${env}: ${parts[*]}"
commit_and_push "deploy(${summary})"
mr=$(create_mr "$branch" "${title:-deploy(${summary})}")
iid=$(jq -r .iid <<<"$mr")
echo "merge request !${iid}: $(jq -r .web_url <<<"$mr")"
if $merge; then merge_mr "$iid"; fi
