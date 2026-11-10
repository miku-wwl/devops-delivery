#!/usr/bin/env bash
# Tracing cost (E9, chapter 10): what the services and the collector spend at the current head
# sampling ratio, under the running k6 load (10 iterations/s). Run once at 10 % and once at 100 %.
#   bash v2/experiments/e9/tracing-cost.sh <label> >> v2/evidence/e9/tracing-cost.log
set -uo pipefail
P="/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1"
q() { kubectl get --raw "$P/query?query=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1")" | python3 -c '
import json, sys
out = []
for x in json.load(sys.stdin)["data"]["result"]:
    m = x["metric"]
    out.append(m.get("container", m.get("service", "")) + "=" + format(float(x["value"][1]), ".3f"))
print(" ".join(out) or "-")'; }
echo "== $(date -u +%T) $1 (head sampling ratio $(kubectl -n storefront get deploy gateway -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_TRACES_SAMPLER_ARG")].value}'), image $(kubectl -n storefront get deploy gateway -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $NF}'))"
echo "  gateway requests/s (5m): $(q 'sum(rate(http_server_requests_total{namespace="storefront",service="gateway"}[5m]))')"
echo "  CPU cores of the six services' app containers (5m): $(q 'sum(rate(container_cpu_usage_seconds_total{namespace="storefront",container="app"}[5m]))')"
echo "  CPU cores per service (5m): $(q 'sum by (container) (label_replace(rate(container_cpu_usage_seconds_total{namespace="storefront",container="app"}[5m]), "container", "$1", "pod", "([a-z]+)-.*"))')"
echo "  collector: spans accepted/s $(q 'sum(rate(otelcol_receiver_accepted_spans[5m]))'), traces/s $(q 'sum(rate(otelcol_processor_tail_sampling_new_trace_id_received[5m]))'), spans exported to Tempo/s $(q 'sum(rate(otelcol_exporter_sent_spans[5m]))')"
echo "  collector CPU cores $(q 'sum(rate(container_cpu_usage_seconds_total{namespace="observability",pod=~"otel-collector-.*",container!=""}[5m]))'), memory MiB $(q 'sum(container_memory_working_set_bytes{namespace="observability",pod=~"otel-collector-.*",container!=""}) / 1048576')"
