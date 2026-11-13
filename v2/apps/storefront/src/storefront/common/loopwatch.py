"""Event-loop watchdog: is the service's single event loop ever blocked, and by what?

An asyncio service does all its work on one thread. If anything holds that thread - a
synchronous call, a long garbage collection, or the process simply not being scheduled - every
request in the process waits. E2 found ~0.9 s stalls before a request body was even read;
this module measures such stalls instead of guessing:

  event_loop_lag_seconds      how late a 50 ms sleep wakes up (histogram)
  python_gc_pause_seconds     duration of each garbage collection, by generation (histogram)
  "event loop blocked" log    when the loop has not run for LOOP_STALL_MS (default 250 ms):
      stack        where the loop thread was when the watchdog noticed
      cpu_ms       CPU time the process used during the gap   (high: busy computing)
      runqueue_ms  time the loop thread waited for a CPU      (high: runnable, not scheduled)
      neither high -> blocked waiting (I/O, a lock, the GIL held by a C call in another thread)
"""

from __future__ import annotations

import asyncio
import gc
import logging
import os
import sys
import threading
import time
import traceback

from prometheus_client import CollectorRegistry, Histogram

log = logging.getLogger("storefront.loopwatch")
LAG_BUCKETS = (0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)


def _schedstat(tid: int) -> tuple[float, float]:
    """(seconds on CPU, seconds waiting on a run queue) of one thread; zeros if unavailable."""
    try:
        with open(f"/proc/self/task/{tid}/schedstat") as f:
            on_cpu, waiting, _ = f.read().split()
        return int(on_cpu) / 1e9, int(waiting) / 1e9
    except (OSError, ValueError):
        return 0.0, 0.0


class LoopWatch:
    def __init__(self, registry: CollectorRegistry, stall_s: float = 0.25, interval_s: float = 0.05) -> None:
        self.stall_s, self.interval_s = stall_s, interval_s
        self.lag = Histogram(
            "event_loop_lag_seconds",
            f"How late the event loop wakes up from a {int(interval_s * 1000)} ms sleep.",
            buckets=LAG_BUCKETS,
            registry=registry,
        )
        self.gc_pause = Histogram(
            "python_gc_pause_seconds",
            "Duration of garbage collections.",
            ["generation"],
            buckets=LAG_BUCKETS,
            registry=registry,
        )
        self.stalls = 0
        self._beat = time.monotonic()
        self._loop_tid: int | None = None
        self._gc_started = 0.0
        self._stop = threading.Event()

    def _on_gc(self, phase: str, info: dict) -> None:
        if phase == "start":
            self._gc_started = time.perf_counter()
        elif self._gc_started:
            self.gc_pause.labels(str(info.get("generation", "?"))).observe(
                time.perf_counter() - self._gc_started
            )

    async def run(self) -> None:
        self._loop_tid = threading.get_native_id()
        self._loop_ident = threading.get_ident()
        # The heartbeat starts now, not when the object was built: the time between building the
        # app and starting the loop is start-up, not a stall (first version reported it).
        self._beat = time.monotonic()
        gc.callbacks.append(self._on_gc)
        threading.Thread(target=self._watch, name="loopwatch", daemon=True).start()
        try:
            while not self._stop.is_set():
                t0 = time.monotonic()
                await asyncio.sleep(self.interval_s)
                self.lag.observe(max(time.monotonic() - t0 - self.interval_s, 0.0))
                self._beat = time.monotonic()
        finally:
            self._stop.set()
            if self._on_gc in gc.callbacks:
                gc.callbacks.remove(self._on_gc)

    def _watch(self) -> None:
        reported = False
        # baselines from the start, so the first report is not "CPU time since process start"
        cpu0, run0 = _schedstat(self._loop_tid or 0)
        t0 = os.times()
        proc0 = t0.user + t0.system
        while not self._stop.wait(self.stall_s / 5):
            blocked = time.monotonic() - self._beat
            if blocked < self.stall_s:
                if reported:  # the stall ended: report its full length and what the thread did
                    on_cpu, waited = _schedstat(self._loop_tid or 0)
                    t = os.times()
                    log.warning(
                        "event loop blocked",
                        extra={
                            "blocked_ms": round(self._last_blocked * 1000),
                            "cpu_ms": round(((t.user + t.system) - proc0) * 1000),
                            "loop_thread_cpu_ms": round((on_cpu - cpu0) * 1000),
                            "runqueue_ms": round((waited - run0) * 1000),
                            "stack": self._stack,
                        },
                    )
                    self.stalls += 1
                reported = False
                cpu0, run0 = _schedstat(self._loop_tid or 0)
                t = os.times()
                proc0 = t.user + t.system
                continue
            self._last_blocked = blocked
            if not reported:  # first sight of this stall: remember where the loop thread is
                frame = sys._current_frames().get(getattr(self, "_loop_ident", 0))
                self._stack = "".join(traceback.format_stack(frame)[-8:]) if frame else "?"
                reported = True

    def stop(self) -> None:
        self._stop.set()
