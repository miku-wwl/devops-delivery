#!/usr/bin/env bash
# Record a terminal transcript as evidence: every command is echoed with a "$ "
# prompt, then executed, and its real stdout+stderr is captured verbatim.
#
#   bash automation/evidence/transcript.sh evidence/p3/helm-lint.log "helm lint" <<'EOF'
#   # comment lines are copied into the transcript
#   helm lint delivery/helm/demo-api
#   helm template demo delivery/helm/demo-api \
#     -f delivery/helm/demo-api/values-dev.yaml
#   EOF
#
# Rules
#   * one command per line; end a line with "\" to continue it on the next line
#   * commands run one after another in the same shell, so cd/export persist
#   * a non-zero exit status is recorded as "[exit N]" and the run continues
#   * commands get /dev/null as stdin (the command list itself is never consumed)
#   * the script exits with the number of failed commands (0 = all succeeded), capped at
#     125: exit statuses are 8 bits, so 256 failures would otherwise wrap around to 0
set -uo pipefail

out="${1:?usage: transcript.sh OUTFILE [TITLE] < commands}"
title="${2:-$(basename "$out" .log)}"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"   # absolute: commands may cd
: > "$out"

emit() { printf '%s\n' "$*" | tee -a "$out"; }

mapfile -t LINES
exec </dev/null

emit "# transcript: ${title}"
emit "# recorded: $(date -u '+%Y-%m-%dT%H:%M:%SZ') | host: $(hostname) | user: $(id -un) | cwd: $(pwd)"
emit ""

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
failures=0
cmd=""

run_cmd() {
  local first=1 l
  while IFS= read -r l; do
    if [ $first -eq 1 ]; then emit "\$ $l"; first=0; else emit "$l"; fi
  done <<< "$cmd"
  eval "$cmd" >"$tmp" 2>&1
  local rc=$?
  tr -d '\r' < "$tmp" | tee -a "$out"
  if [ $rc -ne 0 ]; then emit "[exit $rc]"; failures=$((failures + 1)); fi
  emit ""
  cmd=""
}

for line in "${LINES[@]}"; do
  line="${line%$'\r'}"
  if [ -z "$cmd" ]; then
    if [[ -z "${line// /}" ]]; then continue; fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then emit "$line"; continue; fi
  fi
  if [ -z "$cmd" ]; then cmd="$line"; else cmd+=$'\n'"$line"; fi
  if [[ "$line" == *\\ ]]; then continue; fi
  run_cmd
done
[ -n "$cmd" ] && run_cmd

exit $(( failures > 125 ? 125 : failures ))
