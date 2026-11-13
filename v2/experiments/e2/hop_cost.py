"""What does one round trip cost through the ambient mesh? Run inside a pod.

    python hop_cost.py <http-host:port> <valkey-host:port> [n]

Two dependencies, each over ONE kept-alive connection, n sequential round trips:
  http    GET /healthz on a storefront pod   (server side IN the mesh)
  valkey  PING on the Valkey pod             (server side NOT in the mesh)
Run once from a pod inside the mesh and once from a pod outside it: the 2x2 result separates
the cost of the client-side ztunnel from the cost of the server-side ztunnel.
"""

from __future__ import annotations

import http.client
import socket
import statistics
import sys
import time


def pct(xs: list[float], q: float) -> float:
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def report(name: str, samples: list[float]) -> None:
    us = [s * 1e6 for s in samples]
    print(f"{name:9s} n={len(us)}  p50={pct(us, 0.50):7.0f} us  p90={pct(us, 0.90):7.0f} us  "
          f"p99={pct(us, 0.99):7.0f} us  mean={statistics.fmean(us):7.0f} us")


def bench_http(target: str, n: int) -> list[float]:
    host, port = target.split(":")
    conn = http.client.HTTPConnection(host, int(port), timeout=5)
    out = []
    for i in range(n + 50):
        t0 = time.perf_counter()
        conn.request("GET", "/healthz")
        conn.getresponse().read()
        if i >= 50:  # warm-up: connection set-up, first-request effects
            out.append(time.perf_counter() - t0)
    conn.close()
    return out


def bench_valkey(target: str, n: int) -> list[float]:
    host, port = target.split(":")
    s = socket.create_connection((host, int(port)), timeout=5)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    out = []
    for i in range(n + 50):
        t0 = time.perf_counter()
        s.sendall(b"PING\r\n")
        if s.recv(64) != b"+PONG\r\n":
            raise RuntimeError("unexpected reply")
        if i >= 50:
            out.append(time.perf_counter() - t0)
    s.close()
    return out


def bench_http_new_conn(target: str, n: int) -> list[float]:
    """Connect, one request, close: what a client pays whenever it has no idle connection."""
    host, port = target.split(":")
    out = []
    for i in range(n + 20):
        t0 = time.perf_counter()
        conn = http.client.HTTPConnection(host, int(port), timeout=5)
        conn.request("GET", "/healthz")
        conn.getresponse().read()
        conn.close()
        if i >= 20:
            out.append(time.perf_counter() - t0)
    return out


def bench_http_parallel(target: str, n: int, workers: int) -> list[float]:
    """`workers` kept-alive connections used concurrently, n requests each."""
    import threading

    results: list[float] = []
    lock = threading.Lock()

    def one() -> None:
        r = bench_http(target, n)
        with lock:
            results.extend(r)

    threads = [threading.Thread(target=one) for _ in range(workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


if __name__ == "__main__":
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 2000
    report("http", bench_http(sys.argv[1], n))
    report("valkey", bench_valkey(sys.argv[2], n))
    report("http-new", bench_http_new_conn(sys.argv[1], n // 4))
    report("http-x16", bench_http_parallel(sys.argv[1], n // 8, 16))
