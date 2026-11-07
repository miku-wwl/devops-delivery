"""Resilience primitives for calls between services.

Each primitive answers one question about a call to a dependency:
  timeout       how long may one attempt take?            (Policy.timeout_s)
  deadline      how long may the whole request take?       (propagated by the caller, see web.py)
  retry         is it worth trying again, and when?        (Policy.retries, full-jitter backoff)
  retry budget  can the system afford another retry?       (RetryBudget)
  breaker       is the dependency failing right now?       (CircuitBreaker)
  bulkhead      how many calls may wait on it at once?     (Bulkhead)

The NAIVE policy is the baseline of the failure-propagation experiments (E6): a long timeout,
three immediate retries without a budget, no breaker and no bulkhead.
"""

from __future__ import annotations

import asyncio
import random
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, replace
from enum import IntEnum


@dataclass(frozen=True)
class Policy:
    timeout_s: float
    retries: int
    retry_budget_ratio: float | None  # None: retries are not budgeted
    backoff_base_s: float
    backoff_cap_s: float
    jitter: bool
    breaker: bool
    bulkhead: int | None  # max concurrent calls; None: unlimited

    def replace(self, **changes: object) -> Policy:
        return replace(self, **changes)

    def backoff(self, attempt: int, rng: Callable[[], float] = random.random) -> float:
        """Delay before retry number `attempt` (1-based). Full jitter spreads the retries of
        many clients over the whole interval instead of synchronising them."""
        ceiling = min(self.backoff_cap_s, self.backoff_base_s * 2 ** (attempt - 1))
        return ceiling * rng() if self.jitter else ceiling


NAIVE = Policy(
    timeout_s=30.0,
    retries=3,
    retry_budget_ratio=None,
    backoff_base_s=0.1,
    backoff_cap_s=0.1,
    jitter=False,
    breaker=False,
    bulkhead=None,
)
RESILIENT = Policy(
    timeout_s=1.0,
    retries=2,
    retry_budget_ratio=0.2,
    backoff_base_s=0.05,
    backoff_cap_s=1.0,
    jitter=True,
    breaker=True,
    bulkhead=64,
)


class RetryBudget:
    """Token bucket that limits retries to a fraction of the request rate.

    Every request deposits `ratio` tokens, every retry withdraws one, so retries add at most
    `ratio` x the normal load (plus a burst of `max_tokens`). Without a budget, three retries
    at each of three layers can multiply the load on the deepest dependency by 4^3 = 64.
    """

    def __init__(self, ratio: float, max_tokens: float = 10.0) -> None:
        self.ratio = ratio
        self.max_tokens = max_tokens
        self.tokens = max_tokens

    def deposit(self) -> None:
        self.tokens = min(self.max_tokens, self.tokens + self.ratio)

    def try_withdraw(self) -> bool:
        if self.tokens >= 1.0:
            self.tokens -= 1.0
            return True
        return False


class BreakerState(IntEnum):
    CLOSED = 0
    HALF_OPEN = 1
    OPEN = 2


class CircuitBreaker:
    """Count-based circuit breaker.

    CLOSED: calls pass; the last `window` outcomes are kept. When at least `min_calls`
    are recorded and the failure ratio reaches `failure_ratio`, the breaker OPENs.
    OPEN: calls fail fast for `open_seconds`, then the breaker goes HALF_OPEN.
    HALF_OPEN: up to `half_open_calls` trial calls pass; all succeed -> CLOSED,
    any fails -> OPEN again.
    """

    def __init__(
        self,
        window: int = 20,
        min_calls: int = 10,
        failure_ratio: float = 0.5,
        open_seconds: float = 5.0,
        half_open_calls: int = 3,
        clock: Callable[[], float] = time.monotonic,
        on_transition: Callable[[BreakerState, BreakerState], None] | None = None,
    ) -> None:
        self.window, self.min_calls, self.failure_ratio = window, min_calls, failure_ratio
        self.open_seconds, self.half_open_calls = open_seconds, half_open_calls
        self.clock, self.on_transition = clock, on_transition
        self.state = BreakerState.CLOSED
        self._outcomes: deque[bool] = deque(maxlen=window)
        self._opened_at = 0.0
        self._trials = 0
        self._trial_successes = 0

    def _move(self, new: BreakerState) -> None:
        old, self.state = self.state, new
        if new is BreakerState.OPEN:
            self._opened_at = self.clock()
        if new is not BreakerState.CLOSED:
            self._trials = self._trial_successes = 0
        if new is BreakerState.CLOSED:
            self._outcomes.clear()
        if self.on_transition and old is not new:
            self.on_transition(old, new)

    def allow(self) -> bool:
        if self.state is BreakerState.OPEN:
            if self.clock() - self._opened_at < self.open_seconds:
                return False
            self._move(BreakerState.HALF_OPEN)
        if self.state is BreakerState.HALF_OPEN:
            if self._trials >= self.half_open_calls:
                return False
            self._trials += 1
        return True

    def record(self, success: bool) -> None:
        if self.state is BreakerState.HALF_OPEN:
            if not success:
                self._move(BreakerState.OPEN)
                return
            self._trial_successes += 1
            if self._trial_successes >= self.half_open_calls:
                self._move(BreakerState.CLOSED)
            return
        if self.state is BreakerState.OPEN:
            return  # a late result of a call admitted before the breaker opened
        self._outcomes.append(success)
        failures = self._outcomes.count(False)
        if len(self._outcomes) >= self.min_calls and failures / len(self._outcomes) >= self.failure_ratio:
            self._move(BreakerState.OPEN)


class BulkheadFullError(Exception):
    pass


class Bulkhead:
    """Caps concurrent calls to one dependency. A slow dependency then ties up at most
    `limit` of the caller's in-flight requests; the rest fail fast instead of queueing."""

    def __init__(self, limit: int | None) -> None:
        self.limit = limit
        self.inflight = 0
        self._sem = asyncio.Semaphore(limit) if limit else None

    async def __aenter__(self) -> Bulkhead:
        if self._sem is not None:
            if self._sem.locked():
                raise BulkheadFullError
            await self._sem.acquire()
        self.inflight += 1
        return self

    async def __aexit__(self, *exc: object) -> None:
        self.inflight -= 1
        if self._sem is not None:
            self._sem.release()
