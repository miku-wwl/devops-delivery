"""Latency probe: GET /healthz on one pod every 20 ms for a fixed time, over one kept-alive
connection. Prints every request slower than 100 ms with its UTC time, and a per-10 s summary.

    python exec_probe.py <host:port> <seconds>
"""

from __future__ import annotations

import http.client
import sys
import time
from datetime import UTC, datetime

target, seconds = sys.argv[1], float(sys.argv[2])
host, port = target.split(":")
conn = http.client.HTTPConnection(host, int(port), timeout=10)
start = time.time()
window: list[float] = []
window_start = start
while time.time() - start < seconds:
    t0 = time.perf_counter()
    conn.request("GET", "/healthz")
    conn.getresponse().read()
    ms = (time.perf_counter() - t0) * 1000
    now = time.time()
    window.append(ms)
    if ms > 100:
        print(f"SLOW {datetime.fromtimestamp(now - ms / 1000, UTC).strftime('%H:%M:%S.%f')[:-3]} "
              f"{ms:7.1f} ms", flush=True)
    if now - window_start >= 10:
        w = sorted(window)
        print(f"{datetime.fromtimestamp(window_start, UTC).strftime('%H:%M:%S')}  n={len(w)} "
              f"p50={w[len(w) // 2]:.1f} ms  max={w[-1]:.1f} ms", flush=True)
        window, window_start = [], now
    time.sleep(0.02)
