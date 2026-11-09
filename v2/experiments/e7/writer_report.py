"""Report on a drill (E7): the writer's log against the rows that exist afterwards.

  python3 writer_report.py <writer.log> <rows.txt> [t0-epoch]

rows.txt: the seq numbers of the run present on the primary after the drill, one per line.
Prints the outcome counts, the lost writes (acknowledged, row missing), what became of the
unknown outcomes, every write outage (consecutive attempts without an acknowledgement, from the
first failed attempt to the next acknowledgement) and the server each connection reached.
"""
import sys
from datetime import datetime, timezone


def ts(t, t0):
    s = datetime.fromtimestamp(t, timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    return f"{s} (t={t - t0:+.1f}s)" if t0 else s


def main():
    log, rows_file = sys.argv[1], sys.argv[2]
    t0 = float(sys.argv[3]) if len(sys.argv) > 3 else None
    present = {int(x) for x in open(rows_file) if x.strip()}
    attempts, conns = [], []
    for line in open(log):
        f = line.split()
        if not f:
            continue
        if f[0] == "conn":
            conns.append((float(f[1]), f[2], f[3]))
        elif f[0] in ("ok", "fail", "unk"):
            attempts.append((f[0], int(f[1]), float(f[2]), float(f[3]), f[4] if len(f) > 4 else ""))
    by = {k: [a for a in attempts if a[0] == k] for k in ("ok", "fail", "unk")}
    print(f"attempts {len(attempts)}: ok {len(by['ok'])}, fail {len(by['fail'])}, unknown {len(by['unk'])}")
    lost = [a for a in by["ok"] if a[1] not in present]
    print(f"lost writes (acknowledged, row missing): {len(lost)}")
    shown = lost if len(lost) <= 10 else lost[:5] + [None] + lost[-5:]
    for a in shown:
        print(f"  seq {a[1]} acknowledged at {ts(a[2], t0)} in {a[3]} ms" if a else "  ...")
    if lost:
        print(f"  lost span: {ts(lost[0][2], t0)} .. {ts(lost[-1][2], t0)}")
    unk_in = [a for a in by["unk"] if a[1] in present]
    print(f"unknown outcomes: {len(by['unk'])}, of them committed: {len(unk_in)}, not committed: {len(by['unk']) - len(unk_in)}")
    bad = [a for a in by["fail"] if a[1] in present]
    print(f"'fail' rows that exist anyway (classification error): {len(bad)}")
    reasons = {}
    for a in by["fail"] + by["unk"]:
        reasons[(a[0], a[4])] = reasons.get((a[0], a[4]), 0) + 1
    for (k, r), n in sorted(reasons.items()):
        print(f"  {k} {r}: {n}")
    print("write outages (no acknowledgement in between; >= 0.5 s):")
    start = None
    for a in attempts:
        if a[0] != "ok" and start is None:
            start = a
        elif a[0] == "ok" and start is not None:
            end = a[2] + a[3] / 1000
            if end - start[2] >= 0.5:
                print(f"  {ts(start[2], t0)} -> {ts(end, t0)}: {end - start[2]:.1f} s (seq {start[1]}..{a[1] - 1})")
            start = None
    if start is not None:
        print(f"  {ts(start[2], t0)} -> (no acknowledgement until the end)")
    slow = sorted(by["ok"], key=lambda a: -a[3])[:3]
    print("slowest acknowledgements: " + ", ".join(f"seq {a[1]} {a[3]:.0f} ms at {ts(a[2], t0)}" for a in slow))
    lat = sorted(a[3] for a in by["ok"])
    if lat:
        q = lambda p: lat[min(len(lat) - 1, int(p * len(lat)))]  # noqa: E731
        print(f"commit latency ms: p50 {q(0.5):.1f}, p99 {q(0.99):.1f}, max {lat[-1]:.1f}")
    print("connections:")
    for t, addr, rec in conns:
        print(f"  {ts(t, t0)} -> {addr} in_recovery={rec}")


if __name__ == "__main__":
    main()
