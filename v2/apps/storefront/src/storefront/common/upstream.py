"""HTTP client for calls to another service, with the resilience policy applied.

Order of checks for one logical call:
  deadline left? -> breaker allows? -> bulkhead slot? -> attempt (per-attempt timeout)
  -> failed and retryable? -> budget allows? -> backoff -> next attempt
Only idempotent calls are retried: GET, or a POST that carries an Idempotency-Key.
"""

from __future__ import annotations

import asyncio
import logging
import time

import httpx

from . import context
from .metrics import Metrics
from .resilience import BreakerState, Bulkhead, BulkheadFullError, CircuitBreaker, Policy, RetryBudget

log = logging.getLogger(__name__)
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class UpstreamError(Exception):
    """A call that did not produce a usable response. `kind` decides the caller's status code:
    circuit_open / bulkhead_full / retry_budget -> 503, timeout / deadline -> 504,
    connect_error / bad_status (a 5xx or 429 that survived the retries) -> 502."""

    def __init__(self, upstream: str, kind: str, status: int | None = None) -> None:
        super().__init__(f"{upstream}: {kind}" + (f" (HTTP {status})" if status else ""))
        self.upstream, self.kind, self.status = upstream, kind, status


class Upstream:
    def __init__(
        self,
        name: str,
        base_url: str,
        policy: Policy,
        metrics: Metrics,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.name, self.policy, self.metrics = name, policy, metrics
        # Connection pool sized to the bulkhead: no point opening more connections than calls.
        limits = httpx.Limits(max_connections=policy.bulkhead or 200, max_keepalive_connections=50)
        self.client = httpx.AsyncClient(
            base_url=base_url, transport=transport, limits=limits, timeout=policy.timeout_s
        )
        self.budget = RetryBudget(policy.retry_budget_ratio) if policy.retry_budget_ratio else None
        self.breaker = CircuitBreaker(on_transition=self._on_transition) if policy.breaker else None
        self.bulkhead = Bulkhead(policy.bulkhead)
        metrics.breaker_state.labels(name).set(0)

    def _on_transition(self, old: BreakerState, new: BreakerState) -> None:
        self.metrics.breaker_state.labels(self.name).set(int(new))
        self.metrics.breaker_transitions.labels(self.name, new.name.lower()).inc()
        log.warning(
            "circuit breaker %s: %s -> %s",
            self.name,
            old.name,
            new.name,
            extra={"upstream": self.name, "breaker_from": old.name, "breaker_to": new.name},
        )

    def _reject(self, reason: str) -> UpstreamError:
        self.metrics.upstream_rejected.labels(self.name, reason).inc()
        return UpstreamError(self.name, reason)

    async def request(
        self, method: str, path: str, *, json: object | None = None, headers: dict[str, str] | None = None
    ) -> httpx.Response:
        headers = {**context.outgoing_headers(), **(headers or {})}
        idempotent = method in ("GET", "HEAD") or "Idempotency-Key" in headers
        if self.budget:
            self.budget.deposit()
        try:
            async with self.bulkhead:
                self.metrics.bulkhead_inflight.labels(self.name).set(self.bulkhead.inflight)
                return await self._attempts(method, path, json, headers, idempotent)
        except BulkheadFullError:
            raise self._reject("bulkhead_full") from None
        finally:
            self.metrics.bulkhead_inflight.labels(self.name).set(self.bulkhead.inflight)

    async def _attempts(
        self, method: str, path: str, json: object | None, headers: dict[str, str], idempotent: bool
    ) -> httpx.Response:
        attempt = 0
        while True:
            remaining = context.remaining_seconds()
            if remaining is not None and remaining <= 0:
                raise self._reject("deadline")
            if self.breaker and not self.breaker.allow():
                raise self._reject("circuit_open")
            timeout = self.policy.timeout_s if remaining is None else min(self.policy.timeout_s, remaining)
            started = time.perf_counter()
            status, outcome = None, "ok"
            try:
                resp = await self.client.request(method, path, json=json, headers=headers, timeout=timeout)
                status = resp.status_code
                if status >= 500 or status == 429:
                    outcome = f"http_{status}"
            except httpx.TimeoutException:
                outcome = "timeout"
            except httpx.TransportError:
                outcome = "connect_error"
            self.metrics.upstream_duration.labels(self.name).observe(time.perf_counter() - started)
            self.metrics.upstream_requests.labels(self.name, outcome).inc()
            if self.breaker:
                self.breaker.record(outcome == "ok")
            if outcome == "ok":
                return resp
            retryable = outcome in ("timeout", "connect_error") or status in RETRYABLE_STATUS
            if not (idempotent and retryable and attempt < self.policy.retries):
                break
            if self.budget and not self.budget.try_withdraw():
                self.metrics.upstream_rejected.labels(self.name, "retry_budget").inc()
                break
            attempt += 1
            self.metrics.upstream_retries.labels(self.name).inc()
            await asyncio.sleep(self.policy.backoff(attempt))
        if outcome == "timeout":
            raise UpstreamError(self.name, "timeout")
        if outcome == "connect_error":
            raise UpstreamError(self.name, "connect_error")
        raise UpstreamError(self.name, "bad_status", status)

    async def aclose(self) -> None:
        await self.client.aclose()
