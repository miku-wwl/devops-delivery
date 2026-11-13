from __future__ import annotations

import time

import httpx
import pytest

from storefront.common import context
from storefront.common.metrics import Metrics
from storefront.common.resilience import NAIVE, RESILIENT
from storefront.common.upstream import Upstream, UpstreamError

FAST = RESILIENT.replace(backoff_base_s=0.001, backoff_cap_s=0.001)


def upstream(handler, policy=FAST) -> tuple[Upstream, Metrics, list[httpx.Request]]:
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request, len(seen))

    m = Metrics("test", "dev", "x")
    return Upstream("dep", "http://dep", policy, m, transport=httpx.MockTransport(record)), m, seen


def value(m: Metrics, name: str, **labels: str) -> float:
    return m.registry.get_sample_value(name, labels) or 0.0


async def test_get_is_retried_after_a_503_and_the_retry_is_counted():
    up, m, seen = upstream(lambda req, n: httpx.Response(503 if n == 1 else 200, json={"n": n}))
    resp = await up.request("GET", "/x")
    assert resp.json() == {"n": 2}
    assert len(seen) == 2
    assert value(m, "upstream_retries_total", upstream="dep") == 1
    assert value(m, "upstream_requests_total", upstream="dep", outcome="http_503") == 1


async def test_post_without_idempotency_key_is_never_retried():
    up, _, seen = upstream(lambda req, n: httpx.Response(503))
    with pytest.raises(UpstreamError) as e:
        await up.request("POST", "/x", json={})
    assert e.value.kind == "bad_status" and e.value.status == 503
    assert len(seen) == 1


async def test_post_with_idempotency_key_is_retried():
    up, _, seen = upstream(lambda req, n: httpx.Response(200) if n == 3 else httpx.Response(502))
    await up.request("POST", "/x", json={}, headers={"Idempotency-Key": "abcdefgh"})
    assert len(seen) == 3


async def test_timeouts_become_upstream_errors_and_4xx_pass_through():
    def slow(req, n):
        raise httpx.ReadTimeout("slow", request=req)

    up, m, seen = upstream(slow)
    with pytest.raises(UpstreamError) as e:
        await up.request("GET", "/x")
    assert e.value.kind == "timeout" and len(seen) == 3  # 1 + 2 retries
    up404, _, _ = upstream(lambda req, n: httpx.Response(404))
    assert (await up404.request("GET", "/x")).status_code == 404


async def test_retry_budget_stops_a_retry_storm():
    policy = FAST.replace(retries=3, breaker=False)
    up, m, seen = upstream(lambda req, n: httpx.Response(503), policy)
    up.budget.tokens = 0
    for _ in range(10):
        with pytest.raises(UpstreamError):
            await up.request("GET", "/x")
    # 10 requests deposit 2 tokens: 2 retries in total instead of 30;
    # every request ends with one retry the budget refused
    assert len(seen) == 12
    assert value(m, "upstream_rejected_total", upstream="dep", reason="retry_budget") == 10


async def test_breaker_opens_and_then_fails_fast_without_calling():
    up, m, seen = upstream(lambda req, n: httpx.Response(500), FAST.replace(retries=0))
    for _ in range(10):
        with pytest.raises(UpstreamError):
            await up.request("GET", "/x")
    assert value(m, "circuit_breaker_state", upstream="dep") == 2
    calls = len(seen)
    with pytest.raises(UpstreamError) as e:
        await up.request("GET", "/x")
    assert e.value.kind == "circuit_open" and len(seen) == calls


async def test_deadline_is_propagated_and_an_expired_deadline_fails_fast():
    up, _, seen = upstream(lambda req, n: httpx.Response(200))
    context.set_request("rid-1", time.time() + 2)
    await up.request("GET", "/x")
    assert seen[0].headers["X-Request-ID"] == "rid-1"
    assert int(seen[0].headers["X-Deadline-Ms"]) > time.time() * 1000
    context.set_request("rid-2", time.time() - 1)
    with pytest.raises(UpstreamError) as e:
        await up.request("GET", "/x")
    assert e.value.kind == "deadline" and len(seen) == 1
    context.set_request("", None)


async def test_naive_policy_retries_without_budget_or_breaker():
    up, _, seen = upstream(
        lambda req, n: httpx.Response(503), NAIVE.replace(backoff_cap_s=0.001, backoff_base_s=0.001)
    )
    assert up.budget is None and up.breaker is None
    with pytest.raises(UpstreamError):
        await up.request("GET", "/x")
    assert len(seen) == 4
