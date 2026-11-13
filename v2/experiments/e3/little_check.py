"""Little's law on one pod, without Prometheus: sample the service's own /metrics often.

    kubectl -n storefront exec -i <pod> -c app -- python - <seconds> [<hz>] < little_check.py

Reads http://127.0.0.1:8080/metrics HZ times per second for SECONDS seconds (operational
requests are not counted by the service, so the sampling does not see itself). From the
samples: N = the mean of the in-flight gauge; X = requests completed per second and R = their
mean duration, both from the counter and histogram sum at the first and the last sample.
Little's law says N = X * R. Also shows what a sampler every 15 s (like the Prometheus scrape)
would have reported from the same samples, at each of the possible phases.
"""

import re
import statistics
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8080/metrics"
PATTERNS = {
    "inflight": re.compile(r"^http_server_inflight_requests (\S+)$", re.M),
    "count": re.compile(r"^http_server_request_duration_seconds_count\{[^}]*\} (\S+)$", re.M),
    "sum": re.compile(r"^http_server_request_duration_seconds_sum\{[^}]*\} (\S+)$", re.M),
}


def sample() -> tuple[float, float, float, float]:
    text = urllib.request.urlopen(URL, timeout=2).read().decode()  # noqa: S310 - fixed local URL
    inflight = float(PATTERNS["inflight"].search(text).group(1))
    count = sum(float(x) for x in PATTERNS["count"].findall(text))
    total = sum(float(x) for x in PATTERNS["sum"].findall(text))
    return time.time(), inflight, count, total


def main(seconds: float, hz: float) -> None:
    samples = []
    end = time.time() + seconds
    while time.time() < end:
        samples.append(sample())
        time.sleep(max(0.0, 1 / hz - 0.002))
    t0, _, c0, s0 = samples[0]
    t1, _, c1, s1 = samples[-1]
    x = (c1 - c0) / (t1 - t0)
    r = (s1 - s0) / (c1 - c0) if c1 > c0 else 0.0
    n = statistics.fmean(v for _, v, _, _ in samples)
    print(f"{len(samples)} samples in {t1 - t0:.1f} s ({len(samples) / (t1 - t0):.1f} per s)")
    print(f"X = {x:.1f} requests/s, R = {1000 * r:.1f} ms, X * R = {x * r:.3f}")
    print(f"N (mean of all samples) = {n:.3f}")
    step = max(1, round(15 * len(samples) / (t1 - t0)))   # samples per 15 s
    phases = [statistics.fmean(v for _, v, _, _ in samples[p::step]) for p in range(0, step, max(1, step // 10))]
    print(f"a sampler every 15 s would have reported N between {min(phases):.3f} and {max(phases):.3f}"
          f" depending on its phase ({len(samples[::step])} readings each)")


if __name__ == "__main__":
    main(float(sys.argv[1]) if len(sys.argv) > 1 else 60, float(sys.argv[2]) if len(sys.argv) > 2 else 20)
