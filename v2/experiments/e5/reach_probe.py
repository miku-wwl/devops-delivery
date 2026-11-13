"""Reachability with an application-level answer.

    python reach_probe.py name=proto:host:port ...

A TCP handshake alone proves nothing inside the ambient mesh: the pod's local ztunnel accepts the
connection before it knows whether the destination can be reached. So every probe waits for the
destination itself to answer:
  http   send GET / (HTTP/1.1), expect a status line below 500 from the destination itself.
         An answer the waypoint (Envoy) generated on its own is reported as "proxyNNN": it lacks
         the x-envoy-upstream-service-time header Envoy adds to answers from the destination.
         The first version sent HTTP/1.0, which Envoy refuses with 426 - and counted that as ok.
  nats   expect the server's INFO greeting
  redis  send PING, expect a reply ("+PONG" or an error such as "-NOAUTH": both come from Valkey)
  pg     send an SSLRequest, expect PostgreSQL's one-byte answer ("S" or "N")
  dns    resolve the host name
Prints "name result milliseconds"; result is ok, proxyNNN, httpNNN (5xx), timeout, refused, reset,
closed or unexpected.
"""

import socket
import sys
import time


def probe(proto: str, host: str, port: str, timeout: float = 3.0) -> str:
    if proto == "dns":
        socket.getaddrinfo(host, None)
        return "ok"
    with socket.create_connection((host, int(port)), timeout=timeout) as s:
        s.settimeout(timeout)
        if proto == "http":
            s.sendall(f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode())
            data = b""
            while b"\r\n\r\n" not in data and len(data) < 8192:
                chunk = s.recv(2048)
                if not chunk:
                    break
                data += chunk
            if data.startswith(b"HTTP/"):
                head = data.split(b"\r\n\r\n", 1)[0].lower()
                code = int(data.split(b" ", 2)[1])
                # Envoy (the waypoint) adds x-envoy-upstream-service-time to answers it got from the
                # destination; its own replies (426, 503, 403 ...) lack it.
                if b"server: istio-envoy" in head and b"x-envoy-upstream-service-time" not in head:
                    return f"proxy{code}"
                return "ok" if code < 500 else f"http{code}"
            ok = False
        elif proto == "nats":
            data = s.recv(16)
            ok = data.startswith(b"INFO")
        elif proto == "redis":
            s.sendall(b"PING\r\n")
            data = s.recv(16)
            ok = data[:1] in (b"+", b"-")
        elif proto == "pg":
            s.sendall(bytes([0, 0, 0, 8, 4, 210, 22, 47]))
            data = s.recv(1)
            ok = data in (b"S", b"N")
        else:
            raise ValueError(proto)
        if not data:
            return "closed"
        return "ok" if ok else "unexpected:" + data[:8].hex()


for arg in sys.argv[1:]:
    name, spec = arg.split("=", 1)
    proto, host, port = (spec.split(":") + ["", ""])[:3]
    t = time.time()
    try:
        result = probe(proto, host, port)
    except socket.timeout:
        result = "timeout"
    except ConnectionRefusedError:
        result = "refused"
    except ConnectionResetError:
        result = "reset"
    except OSError as e:
        result = type(e).__name__
    print(f"{name} {result} {1000 * (time.time() - t):.0f}ms", flush=True)
