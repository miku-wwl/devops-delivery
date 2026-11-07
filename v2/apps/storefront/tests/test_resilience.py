from __future__ import annotations

import asyncio

import pytest

from storefront.common.resilience import (
    NAIVE,
    RESILIENT,
    BreakerState,
    Bulkhead,
    BulkheadFullError,
    CircuitBreaker,
    RetryBudget,
)


class Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def test_backoff_grows_exponentially_up_to_the_cap_and_jitter_stays_below_it():
    p = RESILIENT.replace(backoff_base_s=0.05, backoff_cap_s=0.3, jitter=False)
    assert [p.backoff(n) for n in (1, 2, 3, 4, 5)] == [0.05, 0.1, 0.2, 0.3, 0.3]
    jittered = RESILIENT.replace(backoff_base_s=0.05, backoff_cap_s=0.3)
    assert jittered.backoff(3, rng=lambda: 0.5) == pytest.approx(0.1)
    assert NAIVE.backoff(3) == 0.1  # fixed delay: every client retries at the same moment


def test_retry_budget_limits_retries_to_a_fraction_of_requests():
    budget = RetryBudget(ratio=0.2, max_tokens=2)
    budget.tokens = 0
    allowed = 0
    for _ in range(100):
        budget.deposit()
        if budget.try_withdraw():
            allowed += 1
    assert allowed == 20


def test_breaker_opens_on_failure_ratio_then_half_opens_and_closes():
    clock = Clock()
    seen = []
    b = CircuitBreaker(
        window=10,
        min_calls=4,
        failure_ratio=0.5,
        open_seconds=5,
        half_open_calls=2,
        clock=clock,
        on_transition=lambda o, n: seen.append(n),
    )
    for ok in (True, False, True, False):
        assert b.allow()
        b.record(ok)
    assert b.state is BreakerState.OPEN
    assert not b.allow()
    clock.now = 5.0
    assert b.allow() and b.state is BreakerState.HALF_OPEN
    assert b.allow()
    assert not b.allow()  # only two trial calls
    b.record(True)
    b.record(True)
    assert b.state is BreakerState.CLOSED
    assert seen == [BreakerState.OPEN, BreakerState.HALF_OPEN, BreakerState.CLOSED]


def test_breaker_reopens_when_a_trial_call_fails_and_needs_min_calls():
    clock = Clock()
    b = CircuitBreaker(window=10, min_calls=4, failure_ratio=0.5, open_seconds=1, clock=clock)
    for _ in range(3):
        b.record(False)
    assert b.state is BreakerState.CLOSED  # 3 failures, but fewer than min_calls
    b.record(False)
    assert b.state is BreakerState.OPEN
    clock.now = 1.0
    assert b.allow()
    b.record(False)
    assert b.state is BreakerState.OPEN


async def test_bulkhead_rejects_instead_of_queueing():
    bulkhead = Bulkhead(2)
    release = asyncio.Event()

    async def hold() -> None:
        async with bulkhead:
            await release.wait()

    tasks = [asyncio.create_task(hold()) for _ in range(2)]
    await asyncio.sleep(0)
    assert bulkhead.inflight == 2
    with pytest.raises(BulkheadFullError):
        async with bulkhead:
            pass
    release.set()
    await asyncio.gather(*tasks)
    assert bulkhead.inflight == 0
    async with Bulkhead(None):  # unlimited
        pass
