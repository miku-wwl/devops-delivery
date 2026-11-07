#!/usr/bin/env bash
# What does pod-to-pod traffic look like on the wire between two nodes?
#   bash v2/experiments/e2/capture.sh <label>
# tcpdump runs in the network namespace of node ent-worker (a netshoot container joined to the
# node container), on eth0: packets there are on their way to or from pods on OTHER nodes.
# Port 8080 = the services' plain HTTP; port 15008 = Istio HBONE (mTLS tunnel).
set -uo pipefail
LABEL=${1:?label}
summarize() {   # $1 = capture file
  echo "== packets on ent-worker eth0 by destination port (10 s)"
  grep -oE '^[0-9:.]+ IP [0-9.]+\.[0-9]+ > [0-9.]+\.(8080|15008):' "$1" | grep -oE '(8080|15008):$' |
    sort | uniq -c | sed -E 's/^ *([0-9]+) ([0-9]+):$/  \1 packets to port \2/'
  echo "== plaintext HTTP request lines on the wire"
  echo "  north-south (public /api/... paths, from the load balancer): $(grep -acE '(GET|POST) /api/[^ ]* HTTP/1\.1' "$1")"
  echo "  east-west (service-to-service paths):                         $(grep -acE '(GET|POST) /(products|reservations|charges|orders)[^ ]* HTTP/1\.1' "$1")"
  grep -aoE '(GET|POST) /(products|reservations|charges|orders)[^ ]* HTTP/1\.1' "$1" | sed -E 's#/sku-[0-9]+#/{id}#; s#/[0-9a-f-]{36}#/{id}#' | sort | uniq -c | sed 's/^/    /' | head -5 || true
}
[ "${2:-}" = "--summary-only" ] && { summarize "/tmp/cap-$LABEL.txt"; exit 0; }
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
summarize "/tmp/cap-$LABEL.txt"
