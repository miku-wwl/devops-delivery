"""Prometheus metrics following the RED method: Rate, Errors, Duration.

Each app instance owns its own CollectorRegistry, so tests can create many apps
without "duplicated timeseries" errors.
"""

from __future__ import annotations

from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram, generate_latest

from .config import Settings

LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)


class Metrics:
    def __init__(self, settings: Settings) -> None:
        self.registry = CollectorRegistry()
        self.requests = Counter(
            "http_requests_total",
            "HTTP requests handled, by route template and status code.",
            ["method", "route", "status"],
            registry=self.registry,
        )
        self.duration = Histogram(
            "http_request_duration_seconds",
            "HTTP request latency in seconds, by route template.",
            ["method", "route"],
            buckets=LATENCY_BUCKETS,
            registry=self.registry,
        )
        self.orders_created = Counter(
            "demo_api_orders_created", "Orders successfully created.", registry=self.registry
        )
        build_info = Gauge(
            "demo_api_build_info",
            "Always 1; labels identify the running build.",
            ["version", "commit"],
            registry=self.registry,
        )
        build_info.labels(settings.version, settings.commit).set(1)

    def observe(self, method: str, route: str, status: int, seconds: float) -> None:
        self.requests.labels(method, route, str(status)).inc()
        self.duration.labels(method, route).observe(seconds)

    def render(self) -> bytes:
        return generate_latest(self.registry)
