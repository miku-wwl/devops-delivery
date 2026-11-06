"""HTTP API of demo-api."""

from __future__ import annotations

import asyncio
import logging
import random
import time
from datetime import datetime
from decimal import Decimal

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field

from .config import Settings
from .logs import configure_logging
from .metrics import Metrics
from .orders import OrderStore, UnknownSkuError, price_order

log = logging.getLogger("demo_api")

QUIET_ROUTES = {"/healthz", "/readyz", "/metrics"}


class OrderIn(BaseModel):
    sku: str = Field(min_length=1, max_length=32, examples=["BOOK-001"])
    quantity: int = Field(ge=1, le=100, examples=[2])


class OrderOut(BaseModel):
    id: int
    sku: str
    quantity: int
    unit_price: Decimal
    total: Decimal
    created_at: datetime


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    app = FastAPI(title="demo-api", version=settings.version)
    store = OrderStore()
    metrics = Metrics(settings)
    app.state.settings = settings
    app.state.metrics = metrics

    @app.middleware("http")
    async def observe_requests(request: Request, call_next):
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            elapsed = time.perf_counter() - start
            route = request.scope.get("route")
            template = getattr(route, "path", "unmatched")
            metrics.observe(request.method, template, status, elapsed)
            if template not in QUIET_ROUTES:
                log.info(
                    "request",
                    extra={
                        "method": request.method,
                        "route": template,
                        "status": status,
                        "duration_ms": round(elapsed * 1000, 1),
                        "version": settings.version,
                    },
                )

    async def inject_faults() -> None:
        # Not cryptographic randomness - this only decides whether to simulate a failure.
        if settings.fault_error_rate and random.random() < settings.fault_error_rate:  # noqa: S311
            raise HTTPException(status_code=500, detail="injected fault (FAULT_ERROR_RATE)")

    @app.get("/healthz")
    async def healthz() -> dict:
        return {"status": "ok"}

    @app.get("/readyz")
    async def readyz() -> dict:
        return {"status": "ready"}

    @app.get("/api/v1/info", dependencies=[Depends(inject_faults)])
    async def info() -> dict:
        return {
            "service": settings.service_name,
            "version": settings.version,
            "commit": settings.commit,
        }

    @app.post(
        "/api/v1/orders",
        status_code=201,
        response_model=OrderOut,
        dependencies=[Depends(inject_faults)],
    )
    async def create_order(body: OrderIn):
        if settings.fault_latency_ms:
            # Simulates a slow pricing dependency (used by the canary and tracing drills).
            await asyncio.sleep(settings.fault_latency_ms / 1000)
        try:
            unit_price, total = price_order(body.sku, body.quantity)
        except UnknownSkuError:
            raise HTTPException(status_code=422, detail=f"unknown SKU: {body.sku}") from None
        order = store.create(body.sku, body.quantity, unit_price, total)
        metrics.orders_created.inc()
        log.info(
            "order created", extra={"order_id": order.id, "sku": order.sku, "total": str(total)}
        )
        return order

    @app.get(
        "/api/v1/orders/{order_id}",
        response_model=OrderOut,
        dependencies=[Depends(inject_faults)],
    )
    async def get_order(order_id: int):
        order = store.get(order_id)
        if order is None:
            raise HTTPException(status_code=404, detail="order not found")
        return order

    @app.get("/api/v1/orders", response_model=list[OrderOut], dependencies=[Depends(inject_faults)])
    async def list_orders():
        return store.list()

    @app.get("/metrics")
    async def prometheus_metrics() -> Response:
        return Response(metrics.render(), media_type="text/plain; version=0.0.4; charset=utf-8")

    return app


configure_logging()
app = create_app()
