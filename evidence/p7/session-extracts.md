# P7 session extracts (OpenTelemetry Demo)

These checks were run interactively during the P7 session, not through
`automation/evidence/transcript.sh`. Commands and outputs are copied verbatim from the
session's tool output; timestamps are UTC (when the output was returned). The demo has
since been torn down (`otel-demo-teardown.log`), so they cannot be re-recorded as-is.

## 1. Release tags exist for 3.1.0 (GHCR, anonymous pull token) — 2026-11-06T03:30:39Z

```console
$ TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:open-telemetry/demo:pull" | jq -r .token)
$ url="/v2/open-telemetry/demo/tags/list?n=1000"; : > /tmp/tags
$ for i in $(seq 1 30); do
    curl -s -D /tmp/h -H "Authorization: Bearer $TOKEN" "https://ghcr.io$url" | jq -r '.tags[]?' >> /tmp/tags
    next=$(grep -i '^link:' /tmp/h | sed -E 's/^[Ll]ink: <([^>]+)>.*/\1/' | tr -d '\r')
    [ -z "$next" ] && break; url="$next"
  done
$ echo "total tags: $(wc -l < /tmp/tags)"; grep -E '^3\.1\.0-' /tmp/tags | sort | tr '\n' ' '
total tags: 15249
3.1.0-accounting 3.1.0-ad 3.1.0-agent 3.1.0-cart 3.1.0-chatbot 3.1.0-checkout 3.1.0-currency 3.1.0-email 3.1.0-flagd-ui 3.1.0-fraud-detection 3.1.0-frontend 3.1.0-frontend-proxy 3.1.0-frontend-tests 3.1.0-image-provider 3.1.0-kafka 3.1.0-load-generator 3.1.0-mcp 3.1.0-opamp-server 3.1.0-opensearch 3.1.0-payment 3.1.0-product-catalog 3.1.0-quote 3.1.0-recommendation 3.1.0-shipping 3.1.0-telemetry-docs
```

## 2. Memory budget of the minimal profile — 2026-11-06T03:31:08Z

```console
$ cd ~/work/opentelemetry-demo
$ docker compose --env-file .env --env-file .../observability/otel-demo/lab.env \
    -f compose.yaml -f compose.observability.yaml -f compose.extras.yaml config --format json |
  jq -r '[.services[] | (.deploy.resources.limits.memory // .mem_limit // 0) | tonumber] | "services: \(length), sum of memory limits: \((add / 1048576) | floor) MiB"'
services: 25, sum of memory limits: 6819 MiB
$ docker compose ... config --images | grep -c ':3.1.0-'
18
```

## 2b. First start: everything but frontend-proxy — 2026-11-06T03:42:42Z

```console
$ for i in $(seq 1 60); do
    n=$(docker ps --filter label=com.docker.compose.project=opentelemetry-demo --format '{{.Names}}' | wc -l)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8080/ || true)
    [ "$code" = "200" ] && [ "$n" -ge 20 ] && break; sleep 5
  done; echo "containers running: $n, frontend-proxy http://localhost:8080 -> HTTP $code"
containers running: 24, frontend-proxy http://localhost:8080 -> HTTP 000
$ tail -2 evidence/p7/otel-demo-up.raw.log
 Container frontend-proxy Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint frontend-proxy (d86a7acaaa91d14b706210aaf9c575711b6d070934d40a1eae452d4101a1efab): failed to bind host port 0.0.0.0:10000/tcp: address already in use
```

## 3. Who holds port 10000 on the Windows side (PowerShell) — 2026-11-06T03:42:59Z

```console
PS> Get-NetTCPConnection -LocalPort 10000 -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess,@{n='Process';e={(Get-Process -Id $_.OwningProcess).ProcessName}}
LocalAddress LocalPort OwningProcess Process
------------ --------- ------------- -------
127.0.0.1        10000          7576 YunDetectService

10001: free
10002: free
10010: free
```

## 3b. Recreate frontend-proxy with `ENVOY_ADMIN_PORT=10001` in lab.env — 2026-11-06T03:43:19Z

```console
$ docker compose --env-file .env --env-file .../observability/otel-demo/lab.env \
    -f compose.yaml -f compose.observability.yaml -f compose.extras.yaml up --detach --quiet-pull 2>&1 | grep -E 'frontend-proxy|Error' | tail -3
 Container frontend-proxy Recreated
 Container frontend-proxy Starting
 Container frontend-proxy Started
$ ... echo "frontend-proxy http://localhost:8080 -> HTTP $code"
frontend-proxy http://localhost:8080 -> HTTP 200
$ docker ps --filter label=com.docker.compose.project=opentelemetry-demo --format '{{.Names}}' | wc -l
25
```

## 4. Value flagd serves for `paymentFailure` after the flag was turned off — 2026-11-06T03:53:40Z

```console
$ docker run --rm --network opentelemetry-demo curlimages/curl:8.23.0 -s -X POST \
    http://flagd:8013/flagd.evaluation.v1.Service/ResolveFloat \
    -H 'Content-Type: application/json' -d '{"flagKey":"paymentFailure","context":{}}'
{"value":0, "reason":"STATIC", "variant":"off", "metadata":{}}
```

(`docker logs flagd --since 15m | grep -viE debug` in the same command returned no reload
messages, consistent with `otel-demo-fault-on.log`, where the grep for reload/change exits 1.)
