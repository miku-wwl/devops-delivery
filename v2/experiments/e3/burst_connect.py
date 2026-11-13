"""How long do new TCP connections take when many are opened at once?

    python - <host> <port> <n> [<n> ...] < burst_connect.py

For each n: open n connections to host:port concurrently, send "PING\\r\\n" on each and wait for
the first byte of the answer (Valkey answers +PONG or -NOAUTH; either is one round trip), then
close them. Prints, per n, the connect time and the connect + first-round-trip time (p50, p95,
max) and the number of failures (no answer within 5 s). Three rounds per n, 2 s apart.
Run it in a pod of the ambient mesh (traffic goes through the node's ztunnel) and in a pod
outside the mesh on the same node, against the same target: the difference is ztunnel's.
"""

import asyncio
import statistics
import sys
import time


async def one(host: str, port: int) -> tuple[float, float] | None:
    started = time.perf_counter()
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), 5)
        connected = time.perf_counter()
        writer.write(b"PING\r\n")
        await writer.drain()
        await asyncio.wait_for(reader.read(1), 5)
        done = time.perf_counter()
        writer.close()
        return (connected - started) * 1000, (done - started) * 1000
    except (OSError, TimeoutError):
        return None


def q(values: list[float], p: float) -> float:
    return statistics.quantiles(values, n=100)[int(p) - 1] if len(values) > 1 else values[0]


async def main(host: str, port: int, sizes: list[int]) -> None:
    print(f"{'n':>4} {'round':>5}  {'connect p50':>11} {'p95':>7} {'max':>7}   "
          f"{'+round trip p50':>15} {'p95':>7} {'max':>7}  failed")
    for n in sizes:
        for r in range(3):
            results = await asyncio.gather(*(one(host, port) for _ in range(n)))
            ok = [x for x in results if x is not None]
            c, t = [x[0] for x in ok], [x[1] for x in ok]
            if ok:
                print(f"{n:>4} {r + 1:>5}  {q(c, 50):>11.1f} {q(c, 95):>7.1f} {max(c):>7.1f}   "
                      f"{q(t, 50):>15.1f} {q(t, 95):>7.1f} {max(t):>7.1f}  {n - len(ok)}")
            else:
                print(f"{n:>4} {r + 1:>5}  all {n} failed")
            await asyncio.sleep(2)


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], int(sys.argv[2]), [int(x) for x in sys.argv[3:]]))
