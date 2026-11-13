"""Probe (E8, chapter 9): one GET every INTERVAL seconds through the layer-7 entrance, each one
logged as "<epoch> <status> <version>" (version from the X-Storefront-Version header, "-" when the
request failed before any service answered). Used to time a rollback or a promotion to the request.

  python3 probe.py <base-url> <seconds> [interval-s] [header:value]  > probe.log
"""
import sys
import time
import urllib.error
import urllib.request


def main() -> None:
    base, seconds = sys.argv[1], float(sys.argv[2])
    interval = float(sys.argv[3]) if len(sys.argv) > 3 else 0.05
    headers = {}
    if len(sys.argv) > 4:
        k, v = sys.argv[4].split(":", 1)
        headers[k] = v
    end, nxt = time.time() + seconds, time.time()
    while time.time() < end:
        t = time.time()
        req = urllib.request.Request(f"{base}/api/products?limit=1", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:  # noqa: S310 - lab URL from the caller
                status, version = r.status, r.headers.get("X-Storefront-Version", "-")
        except urllib.error.HTTPError as e:
            status, version = e.code, e.headers.get("X-Storefront-Version", "-")
        except Exception:  # noqa: BLE001 - connection errors, timeouts
            status, version = 0, "-"
        print(f"{t:.3f} {status} {version}", flush=True)
        nxt += interval
        time.sleep(max(0.0, nxt - time.time()))


if __name__ == "__main__":
    main()
