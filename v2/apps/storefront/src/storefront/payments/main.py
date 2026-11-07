"""payments: a SIMULATED external payment provider ([模拟] in the book).

It stands in for a third party we do not control: its latency follows a log-normal
distribution (fixed by its median and 99th percentile), and a configurable share of charges
is declined (402), fails (500) or hangs. Charges are idempotent per Idempotency-Key, as with
real payment APIs: a retried charge returns the first result and never charges twice.
Behaviour can be changed at runtime through PUT /admin/psp (experiments E3, E6).
"""

from __future__ import annotations

import asyncio
import json
import math
import os
import random
import re
import time
import uuid
from typing import Any

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from prometheus_client import Counter
from pydantic import BaseModel, Field

from ..common import cache as cachelib
from ..common.settings import Settings
from ..common.web import create_app

_KEY = re.compile(r"[A-Za-z0-9._-]{8,64}")
Z99 = 2.3263  # standard normal quantile of 0.99


class PspBehaviour(BaseModel):
    latency_p50_ms: float = Field(float(os.environ.get("PSP_LATENCY_P50_MS", 40)), gt=0)
    latency_p99_ms: float = Field(float(os.environ.get("PSP_LATENCY_P99_MS", 250)), gt=0)
    decline_rate: float = Field(float(os.environ.get("PSP_DECLINE_RATE", 0.02)), ge=0, le=1)
    error_rate: float = Field(float(os.environ.get("PSP_ERROR_RATE", 0)), ge=0, le=1)
    hang_rate: float = Field(float(os.environ.get("PSP_HANG_RATE", 0)), ge=0, le=1)
    hang_seconds: float = Field(float(os.environ.get("PSP_HANG_SECONDS", 30)), ge=0, le=300)

    def latency_s(self, rng: random.Random) -> float:
        """Log-normal with the given median and p99: sigma = ln(p99/p50) / z(0.99)."""
        sigma = max(math.log(self.latency_p99_ms / self.latency_p50_ms), 0) / Z99
        return self.latency_p50_ms * math.exp(sigma * rng.gauss(0, 1)) / 1000


class ChargeRequest(BaseModel):
    order_id: uuid.UUID
    amount_cents: int = Field(gt=0, le=10_000_000)


def build(settings: Settings, cache: Any = None, rng: random.Random | None = None) -> FastAPI:
    rng = rng or random.Random()  # noqa: S311 - simulation, not security

    async def startup(app: FastAPI) -> None:
        nonlocal cache
        if cache is None:
            cache = cachelib.connect(settings.valkey_url) if settings.valkey_url else cachelib.MemoryCache()

    async def shutdown(app: FastAPI) -> None:
        await cache.aclose()

    async def ready(app: FastAPI) -> bool:
        try:
            return bool(await cache.ping())
        except Exception:  # noqa: BLE001
            return False

    app = create_app(settings, startup=startup, shutdown=shutdown, ready=ready)
    app.state.psp = PspBehaviour()
    charges = Counter(
        "payments_charges_total", "Charges by result.", ["result"], registry=app.state.metrics.registry
    )

    @app.post("/charges", status_code=201)
    async def charge(req: ChargeRequest, idempotency_key: str = Header(...)) -> JSONResponse:
        if not _KEY.fullmatch(idempotency_key):
            raise HTTPException(400, "Idempotency-Key must be 8-64 characters [A-Za-z0-9._-]")
        key = f"psp:charge:{idempotency_key}"
        stored = await cache.get(key)  # a Valkey failure is a 500: never risk a double charge
        if stored is not None:
            charges.labels("replayed").inc()
            body = json.loads(stored)
            return JSONResponse(
                body,
                status_code=201 if body["status"] == "approved" else 402,
                headers={"Idempotent-Replayed": "true"},
            )
        psp: PspBehaviour = app.state.psp
        # Two requests with the same key at the same time (a client retrying after its own
        # timeout) must not both charge: the second one gets 409 and has to ask again later.
        lock = f"{key}:lock"
        if not await cache.set(lock, "1", nx=True, ex=int(psp.hang_seconds) + 30):
            charges.labels("conflict").inc()
            return JSONResponse(
                {"error": "a request with this Idempotency-Key is in progress"}, status_code=409
            )
        try:
            roll = rng.random()
            if roll < psp.hang_rate:
                charges.labels("hang").inc()
                await asyncio.sleep(psp.hang_seconds)
                return JSONResponse({"error": "provider timeout"}, status_code=504)
            await asyncio.sleep(psp.latency_s(rng))
            if roll < psp.hang_rate + psp.error_rate:
                charges.labels("error").inc()
                return JSONResponse({"error": "provider error"}, status_code=500)
            declined = roll < psp.hang_rate + psp.error_rate + psp.decline_rate
            body = {
                "charge_id": uuid.uuid4().hex,
                "order_id": str(req.order_id),
                "amount_cents": req.amount_cents,
                "status": "declined" if declined else "approved",
                "processed_at": time.time(),
            }
            await cache.set(key, json.dumps(body), ex=86_400)
            charges.labels(body["status"]).inc()
            return JSONResponse(body, status_code=402 if declined else 201)
        finally:
            await cache.delete(lock)

    @app.get("/charges/{idempotency_key}")
    async def charge_status(idempotency_key: str) -> dict[str, Any]:
        """What a reconciler asks after an ambiguous outcome (timeout, 409)."""
        stored = await cache.get(f"psp:charge:{idempotency_key}")
        if stored is None:
            raise HTTPException(404, "no completed charge with this key")
        return json.loads(stored)

    @app.get("/admin/psp", include_in_schema=False)
    async def get_behaviour() -> PspBehaviour:
        return app.state.psp

    @app.put("/admin/psp", include_in_schema=False)
    async def set_behaviour(b: PspBehaviour) -> PspBehaviour:
        app.state.psp = b
        return b

    return app


app = build(Settings(service="payments"))
