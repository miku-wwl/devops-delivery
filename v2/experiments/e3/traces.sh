#!/usr/bin/env bash
# Traces from Tempo (via the API server proxy), for evidence.
#   bash v2/experiments/e3/traces.sh list <start-iso> <end-iso> '<traceql>' [min-duration-ms]
#   bash v2/experiments/e3/traces.sh spans <trace-id>
# list:  matching traces, oldest first: id, start time, root span name, duration.
# spans: every span of one trace in start order: offset from the first span, service/pod,
#        name, duration, error status and a few attributes (HTTP status, db.system).
set -euo pipefail
T=/api/v1/namespaces/observability/services/tempo:3200/proxy
case "${1:?list|spans}" in
  list)
    S=$(date -u -d "${2:?start}" +%s); E=$(date -u -d "${3:?end}" +%s); MIN=${5:-0}
    kubectl get --raw "$T/api/search?q=$(jq -rn --arg q "${4:?traceql}" '$q|@uri')&start=$S&end=$E&limit=500&spss=3" |
      jq -r --argjson min "$MIN" '.traces | sort_by(.startTimeUnixNano)[] | select((.durationMs // 0) >= $min) |
        "\(.traceID) \((.startTimeUnixNano | tonumber) / 1e9 | strftime("%H:%M:%S")) \(.rootTraceName) \(.durationMs // 0) ms"' ;;
  spans)
    kubectl get --raw "$T/api/traces/${2:?trace id}" | jq -r '
      [.batches[] | ([.resource.attributes[] | select(.key == "service.name") | .value.stringValue][0]) as $svc
        | ([.resource.attributes[] | select(.key == "k8s.pod.name") | .value.stringValue][0] // "") as $pod
        | .scopeSpans[].spans[]
        | {svc: $svc, pod: $pod, name, start: (.startTimeUnixNano | tonumber),
           dur: (((.endTimeUnixNano | tonumber) - (.startTimeUnixNano | tonumber)) / 1e6),
           err: (if .status.code == "STATUS_CODE_ERROR" then "ERROR" else "" end),
           attrs: ([.attributes[]? | select(.key | test("status_code|db.system"))
                    | "\(.key)=\(.value.stringValue // .value.intValue)"] | join(" "))}]
      | sort_by(.start) | (.[0].start) as $t0 | .[] | select(.name | test("http (send|receive)$") | not)
      | "+\(((.start - $t0) / 1e6) | floor) ms  \(.svc)/\(.pod[-5:])  \(.name)  \(.dur | floor) ms \(.err) \(.attrs)"' ;;
esac
