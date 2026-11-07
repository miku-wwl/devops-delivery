#!/usr/bin/env bash
# What does pod-to-pod traffic look like on the wire between two nodes?
#   bash v2/experiments/e2/capture.sh <label>
# tcpdump runs in the network namespace of node ent-worker (a netshoot container joined to the
# node container), on eth0: packets there are on their way to or from pods on OTHER nodes.
# Port 8080 = the services' plain HTTP; port 15008 = Istio HBONE (mTLS tunnel).
set -uo pipefail
LABEL=${1:?label}
IMG=nicolaka/netshoot:v0.16
GW=$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
docker image inspect "$IMG" >/dev/null 2>&1 || docker pull -q "$IMG" >/dev/null
( for i in $(seq 40); do
    curl -s -o /dev/null "http://$GW:8080/api/products/sku-00$((i % 9 + 1))"
    curl -s -o /dev/null "http://$GW:8080/api/orders" -H "Content-Type: application/json" \
      -H "Idempotency-Key: capture-$LABEL-$i-$RANDOM" \
      -d '{"customer_id":"c-cap","items":[{"product_id":"sku-002","qty":1}]}'
    sleep 0.1
  done ) &
docker run --rm --net container:ent-worker --cap-add NET_RAW --cap-add NET_ADMIN "$IMG" \
  timeout 10 tcpdump -i eth0 -nn -s 0 -A 'tcp port 8080 or tcp port 15008' 2>/dev/null > "/tmp/cap-$LABEL.txt"
wait
echo "== packets on ent-worker eth0 by destination port (10 s)"
grep -oE '^[0-9:.]+ IP [0-9.]+\.[0-9]+ > [0-9.]+\.(8080|15008):' "/tmp/cap-$LABEL.txt" | grep -oE '\.(8080|15008):$' |
  sort | uniq -c | sed 's/[.:]//g; s/^ */  /; s/ \([0-9]*\)$/ packets to port \1/'
echo "== plaintext HTTP request lines visible on the wire"
grep -aoE '(GET|POST) /[a-z/{}._0-9-]+ HTTP/1\.1' "/tmp/cap-$LABEL.txt" | sort | uniq -c | head -8
echo "== readable header fields (X-Request-ID, Idempotency-Key)"
grep -aoiE '(x-request-id|idempotency-key): [A-Za-z0-9._-]+' "/tmp/cap-$LABEL.txt" | head -4
echo "== TLS on port 15008? (record type 0x16 handshake / 0x17 application data in the payload)"
grep -acE 'HTTP/1\.1' "/tmp/cap-$LABEL.txt" | sed 's/^/  lines containing HTTP\/1.1: /'
