"""Runtime settings, read once from environment variables (12-factor style)."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _float(name: str, default: float) -> float:
    raw = os.getenv(name, "")
    return float(raw) if raw.strip() else default


@dataclass(frozen=True)
class Settings:
    service_name: str = "demo-api"
    version: str = "dev"
    commit: str = "unknown"
    # Fault injection, used by the progressive-delivery and observability drills:
    #   FAULT_ERROR_RATE=0.3   -> 30% of /api requests fail with HTTP 500
    #   FAULT_LATENCY_MS=800   -> the pricing step takes 800 ms longer
    fault_error_rate: float = 0.0
    fault_latency_ms: float = 0.0

    @classmethod
    def from_env(cls) -> Settings:
        settings = cls(
            version=os.getenv("APP_VERSION", "dev"),
            commit=os.getenv("GIT_SHA", "unknown"),
            fault_error_rate=_float("FAULT_ERROR_RATE", 0.0),
            fault_latency_ms=_float("FAULT_LATENCY_MS", 0.0),
        )
        if not 0.0 <= settings.fault_error_rate <= 1.0:
            raise ValueError("FAULT_ERROR_RATE must be between 0 and 1")
        if settings.fault_latency_ms < 0:
            raise ValueError("FAULT_LATENCY_MS must not be negative")
        return settings
