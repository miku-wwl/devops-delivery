"""Database round trips from inside a storefront pod, every 0.5 s, for SECONDS seconds.

    kubectl -n storefront exec -i <pod> -c app -- python - <seconds> < probe_db.py

Runs in the pod's network namespace, so its traffic takes the same path as the service's own
(through the node's ztunnel). Prints one line per probe: the latency of SELECT 1 on a pooled
connection and, every 2 s, of opening a new connection. Prints no connection details.
"""

import asyncio
import os
import sys
import time

import asyncpg


async def main(seconds: float) -> None:
    dsn = os.environ["DATABASE_URL"]
    conn = await asyncpg.connect(dsn)
    end, i = time.time() + seconds, 0
    while time.time() < end:
        line = time.strftime("%H:%M:%S", time.gmtime())
        started = time.perf_counter()
        try:
            await asyncio.wait_for(conn.fetchval("SELECT 1"), 5)
            line += f" query_ms={(time.perf_counter() - started) * 1000:.1f}"
        except Exception as exc:  # noqa: BLE001 - report and reconnect
            line += f" query_failed={type(exc).__name__}"
            conn = await asyncpg.connect(dsn)
        if i % 4 == 0:
            started = time.perf_counter()
            try:
                fresh = await asyncio.wait_for(asyncpg.connect(dsn), 5)
                line += f" connect_ms={(time.perf_counter() - started) * 1000:.1f}"
                await fresh.close()
            except Exception as exc:  # noqa: BLE001
                line += f" connect_failed={type(exc).__name__}"
        print(line, flush=True)
        i += 1
        await asyncio.sleep(0.5)
    await conn.close()


if __name__ == "__main__":
    asyncio.run(main(float(sys.argv[1]) if len(sys.argv) > 1 else 90))
