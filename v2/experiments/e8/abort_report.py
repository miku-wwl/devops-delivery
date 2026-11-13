"""Report of the canary abort drill (E8, chapter 9) from probe.py's log.

  python3 abort_report.py <probe.log> <decision-epoch> <merged-epoch> <applied-epoch> [canary-version]

Per phase (before the decision, decision -> merge, after the merge): requests, the canary's share,
failed requests (5xx or no answer) split by the version that answered, and when the canary answered
for the last time.
"""
import sys


def main() -> None:
    log, decide, merged, applied = sys.argv[1], *map(float, sys.argv[2:5])
    canary = sys.argv[5] if len(sys.argv) > 5 else "8ef5584"
    rows = []
    for line in open(log):
        f = line.split()
        if len(f) == 3:
            rows.append((float(f[0]), int(f[1]), f[2]))

    def stats(sel: list, label: str) -> None:
        n = len(sel)
        if not n:
            print(f"{label}: no requests")
            return
        can = [r for r in sel if r[2] == canary]
        bad = [r for r in sel if r[1] >= 500 or r[1] == 0]
        bad_can = [r for r in can if r[1] >= 500]
        bad_other = [r for r in bad if r[2] != canary]
        span = sel[-1][0] - sel[0][0]
        print(f"{label} ({span:.0f} s): {n} requests, canary answered {len(can)} ({100 * len(can) / n:.2f} %), "
              f"failed {len(bad)} ({100 * len(bad) / n:.2f} %): {len(bad_can)} of the canary's {len(can)} answers, "
              f"{len(bad_other)} others")

    stats([r for r in rows if r[0] < decide], "before the decision (faulty canary, weight 5)")
    stats([r for r in rows if decide <= r[0] < merged], "from the decision to the merge")
    stats([r for r in rows if r[0] >= merged], "after the merge")
    last = max((r[0] for r in rows if r[2] == canary), default=None)
    if last is not None:
        print(f"last canary answer: {last - merged:+.1f} s after the merge, {last - decide:+.1f} s after the decision; "
              f"the route had weight 0 in the cluster {applied - merged:+.1f} s after the merge")


if __name__ == "__main__":
    main()
