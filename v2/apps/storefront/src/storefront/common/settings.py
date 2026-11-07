"""Settings from environment variables (12-factor). Nothing here talks to the network."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from .resilience import NAIVE, RESILIENT, Policy


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _float(name: str, default: float) -> float:
    return float(_env(name, str(default)))


def _int(name: str, default: int) -> int:
    return int(_env(name, str(default)))


@dataclass(frozen=True)
class Settings:
    service: str
    version: str = field(default_factory=lambda: _env("APP_VERSION", "dev"))
    commit: str = field(default_factory=lambda: _env("GIT_SHA", "unknown"))
    environment: str = field(default_factory=lambda: _env("DEPLOY_ENV", "local"))
    log_level: str = field(default_factory=lambda: _env("LOG_LEVEL", "INFO"))
    # "resilient" (timeouts, retry budget, circuit breaker, bulkhead) or "naive" (E6 baseline)
    resilience_mode: str = field(default_factory=lambda: _env("RESILIENCE_MODE", "resilient"))
    database_url: str | None = field(default_factory=lambda: os.environ.get("DATABASE_URL"))
    db_pool_min: int = field(default_factory=lambda: _int("DB_POOL_MIN", 1))
    db_pool_max: int = field(default_factory=lambda: _int("DB_POOL_MAX", 10))
    db_acquire_timeout_s: float = field(default_factory=lambda: _float("DB_ACQUIRE_TIMEOUT_S", 1.0))
    valkey_url: str | None = field(default_factory=lambda: os.environ.get("VALKEY_URL"))
    nats_url: str | None = field(default_factory=lambda: os.environ.get("NATS_URL"))
    nats_stream_replicas: int = field(default_factory=lambda: _int("NATS_STREAM_REPLICAS", 1))
    # access log: every 5xx and every slow request, plus a sample of the rest
    access_log_sample: float = field(default_factory=lambda: _float("ACCESS_LOG_SAMPLE", 0.01))
    slow_request_ms: float = field(default_factory=lambda: _float("SLOW_REQUEST_MS", 500))
    # fault injection ([注入] in the book): applied to every non-operational route
    fault_latency_ms: float = field(default_factory=lambda: _float("FAULT_LATENCY_MS", 0))
    fault_error_rate: float = field(default_factory=lambda: _float("FAULT_ERROR_RATE", 0))

    def upstream_url(self, name: str) -> str:
        """Base URL of another service, e.g. CATALOG_URL=http://catalog.storefront.svc:8080"""
        return _env(f"{name.upper()}_URL", f"http://{name}:8080")

    def policy(self, name: str) -> Policy:
        """Resilience policy for calls to upstream `name`; per-upstream overrides via env,
        e.g. INVENTORY_TIMEOUT_S=0.5, INVENTORY_RETRIES=1, INVENTORY_BULKHEAD=20."""
        base = NAIVE if self.resilience_mode == "naive" else RESILIENT
        p = name.upper()
        bulkhead = os.environ.get(f"{p}_BULKHEAD")
        return base.replace(
            timeout_s=_float(f"{p}_TIMEOUT_S", base.timeout_s),
            retries=_int(f"{p}_RETRIES", base.retries),
            bulkhead=(int(bulkhead) or None) if bulkhead is not None else base.bulkhead,
        )
