"""Prometheus metrics shared by all services: RED for HTTP, plus dependency-call metrics.

Each app owns its own CollectorRegistry, so tests can build many apps in one process.
Service-specific metrics are registered on the same registry (see each service's main.py).
"""

from __future__ import annotations

from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    GCCollector,
    Histogram,
    PlatformCollector,
    ProcessCollector,
)

# Bucket boundaries decide how precise a percentile estimate can be: histogram_quantile
# interpolates linearly inside a bucket. E1 showed both failure modes: a p95 of exactly
# 4.75 ms for pool waits that take microseconds (everything in the first 0-5 ms bucket gives
# 0.95 x 5 ms), and a payments p95 of 216 ms from the wide 100-250 ms bucket.
LATENCY_BUCKETS = (
    0.005,
    0.01,
    0.02,
    0.03,
    0.05,
    0.075,
    0.1,
    0.15,
    0.2,
    0.3,
    0.5,
    0.75,
    1.0,
    2.0,
    5.0,
    10.0,
    30.0,
)
WAIT_BUCKETS = (0.0001, 0.00025, 0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5)


class Metrics:
    def __init__(self, service: str, version: str, commit: str) -> None:
        self.registry = r = CollectorRegistry()
        ProcessCollector(registry=r)
        PlatformCollector(registry=r)
        GCCollector(registry=r)
        self.requests = Counter(
            "http_server_requests_total",
            "HTTP requests served, by route template and status code.",
            ["method", "route", "code"],
            registry=r,
        )
        self.duration = Histogram(
            "http_server_request_duration_seconds",
            "HTTP request latency, by route template.",
            ["method", "route"],
            buckets=LATENCY_BUCKETS,
            registry=r,
        )
        self.inflight = Gauge("http_server_inflight_requests", "Requests being served right now.", registry=r)
        self.upstream_requests = Counter(
            "upstream_requests_total",
            "Attempts of calls to other services, by outcome.",
            ["upstream", "outcome"],
            registry=r,
        )
        self.upstream_duration = Histogram(
            "upstream_request_duration_seconds",
            "Latency of one attempt of a call to another service.",
            ["upstream"],
            buckets=LATENCY_BUCKETS,
            registry=r,
        )
        self.upstream_retries = Counter(
            "upstream_retries_total", "Retries sent to other services.", ["upstream"], registry=r
        )
        self.upstream_rejected = Counter(
            "upstream_rejected_total",
            "Calls not sent: breaker open, bulkhead full, budget or deadline exhausted.",
            ["upstream", "reason"],
            registry=r,
        )
        self.breaker_state = Gauge(
            "circuit_breaker_state", "0 closed, 1 half-open, 2 open.", ["upstream"], registry=r
        )
        self.breaker_transitions = Counter(
            "circuit_breaker_transitions_total", "Breaker state changes.", ["upstream", "to"], registry=r
        )
        self.bulkhead_inflight = Gauge(
            "bulkhead_inflight", "Calls in flight per dependency.", ["upstream"], registry=r
        )
        self.db_acquire = Histogram(
            "db_pool_acquire_seconds",
            "Time spent waiting for a database connection.",
            buckets=WAIT_BUCKETS,
            registry=r,
        )
        self.db_acquire_timeouts = Counter(
            "db_pool_acquire_timeouts_total", "Requests that gave up waiting for a connection.", registry=r
        )
        self.db_connections = Gauge(
            "db_pool_connections", "Pool connections by state.", ["state"], registry=r
        )
        Gauge(
            "storefront_build_info",
            "Always 1; labels identify the running build.",
            ["service", "version", "commit"],
            registry=r,
        ).labels(service, version, commit).set(1)
