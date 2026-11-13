#!/usr/bin/env bash
# Who holds TCP connections to whom? Counted on the SERVER side of every storefront pod.
#   bash v2/experiments/load/connections.sh
# A client pod cannot tell which replica it reached: it connects to the Service IP and
# kube-proxy rewrites the destination in the node's network namespace (DNAT). The server pod
# sees the real peer instead, so each server's /proc/net/tcp is read (python is in the image;
# the image has no ss/netstat). Peers are mapped back to pod names; prometheus = scrapes.
set -euo pipefail
NS=${NS:-storefront}
declare -A NAME
while read -r ns name ip; do NAME[$ip]="$name"; done < <(
  kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}')
printf '%-30s %-40s %s\n' "server pod (port 8080)" "client" "established"
for pod in $(kubectl -n "$NS" get pods -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$NS" exec "$pod" -c app -- python -c '
import socket, struct
def ip(h): return socket.inet_ntoa(struct.pack("<I", int(h, 16)))
for line in open("/proc/net/tcp").readlines()[1:]:
    f = line.split()
    lport = int(f[1].split(":")[1], 16)
    rip = f[2].split(":")[0]
    if f[3] == "01" and lport == 8080:
        print(ip(rip))
' 2>/dev/null | sort | uniq -c | while read -r n rip; do
    printf '%-30s %-40s %s\n' "$pod" "${NAME[$rip]:-$rip}" "$n"
  done
done
