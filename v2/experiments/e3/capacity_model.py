"""Capacity model from two low-load windows; predictions for higher rates.

    python3 capacity_model.py <window-low.json> <window-high.json> <rate-low> <rate-high> [rate ...]

The inputs are window_stats.py outputs at two iteration rates. Per service the model takes, from
the higher of the two windows: requests per iteration (req/s / rate), the service demand D (CPU
ms per request) and the share of the service's CPU on its busiest pod (load balancing is never
perfect). Each service is a set of single-threaded processes, so the busiest pod saturates when
its CPU reaches one core (in practice ~0.95: chapter 4, first step load). Then, per service,
  CPU of the busiest pod at rate X  = share * requests per iteration * D * X
  saturation rate                   = 0.95 / (share * requests per iteration * D)
and for the worker nodes together, fixed + marginal CPU from the two windows (a straight line).
Prints the model and, for every further rate, the predicted busiest-pod CPU of every service.
"""

from __future__ import annotations

import json
import sys

CEILING = 0.95   # cores a single Python process reaches at saturation (first run: 0.94-0.95)


def main() -> None:
    lo, hi = (json.load(open(p)) for p in sys.argv[1:3])
    r_lo, r_hi = float(sys.argv[3]), float(sys.argv[4])
    rates = [float(x) for x in sys.argv[5:]]
    model = {}
    print(f"model from {r_hi:g} it/s (D per request, requests per iteration, busiest-pod share):")
    print(f"  {'service':10s} {'req/it':>7s} {'D ms':>6s} {'share':>6s} {'ms/it busiest':>13s} {'saturates at':>13s}")
    for svc, s in hi["services"].items():
        if not s["req_per_s"] or not s["cpu_ms_per_req"]:
            continue
        req_it = s["req_per_s"] / r_hi
        share = s["busiest_pod_cores"] / s["cpu_cores"]
        per_it = share * req_it * s["cpu_ms_per_req"]          # busiest pod, ms CPU per iteration
        model[svc] = per_it
        print(f"  {svc:10s} {req_it:7.2f} {s['cpu_ms_per_req']:6.2f} {share:6.2f} {per_it:13.2f} "
              f"{1000 * CEILING / per_it:9.0f} it/s")
    first = max(model, key=model.get)
    print(f"first to saturate: {first}, at {1000 * CEILING / model[first]:.0f} it/s "
          f"(busiest pod at {CEILING} cores)")
    n_lo, n_hi = sum(lo["nodes_cpu_cores"].values()), sum(hi["nodes_cpu_cores"].values())
    marginal = (n_hi - n_lo) / (r_hi - r_lo)
    fixed = n_lo - marginal * r_lo
    print(f"worker nodes together: {fixed:.2f} cores + {1000 * marginal:.1f} ms per iteration")
    if rates:
        print("predicted CPU (cores) of the busiest pod of every service, and of all worker nodes:")
        print("  " + f"{'it/s':>6s} " + " ".join(f"{s:>9s}" for s in model) + f" {'nodes':>7s}")
        for x in rates:
            cells = " ".join(f"{min(model[s] * x / 1000, CEILING):9.2f}" for s in model)
            print(f"  {x:6.0f} {cells} {fixed + marginal * x:7.2f}")


if __name__ == "__main__":
    main()
