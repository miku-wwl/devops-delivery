"""orders: places orders as an orchestrated saga over catalog, inventory and payments.

POST /orders (Idempotency-Key required):
  1. claim the key: INSERT the order as PENDING (the UNIQUE key makes retries and concurrent
     duplicates return the first order instead of creating a second one)
  2. price the items           GET  catalog   /products/{id}        (in parallel)
  3. reserve the stock         POST inventory /reservations          (idempotent per order)
  4. charge                    POST payments  /charges               (idempotent per order)
  5. confirm + outbox event    one transaction: UPDATE orders, INSERT outbox
A failure after step 3 is compensated by releasing the reservation. The event is published
to NATS by the outbox relay (outbox.py), never directly from the request.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
import uuid
from typing import Any

import asyncpg
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from opentelemetry import trace
from prometheus_client import Counter
from pydantic import BaseModel, Field

from ..common import messaging
from ..common.db import Database
from ..common.settings import Settings
from ..common.upstream import Upstream, UpstreamError
from ..common.web import create_app
from .outbox import Relay, ensure_stream

log = logging.getLogger(__name__)
_KEY = re.compile(r"[A-Za-z0-9._-]{8,64}")
ORDER_COLUMNS = "id, customer_id, status, items, total_cents, failure_reason, created_at"


class Item(BaseModel):
    product_id: str = Field(pattern=r"^[a-z0-9-]{1,32}$")
    qty: int = Field(ge=1, le=10)


class OrderRequest(BaseModel):
    customer_id: str = Field(pattern=r"^[A-Za-z0-9._-]{1,64}$")
    items: list[Item] = Field(min_length=1, max_length=10)


def order_json(row: asyncpg.Record | dict[str, Any]) -> dict[str, Any]:
    d = dict(row)
    d["id"] = str(d["id"])
    d["items"] = json.loads(d["items"]) if isinstance(d["items"], str) else d["items"]
    d["created_at"] = d["created_at"].isoformat()
    return d


class OrderStore:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def by_key(self, key: str) -> asyncpg.Record | None:
        async with self.db.connection() as c:
            return await c.fetchrow(f"SELECT {ORDER_COLUMNS} FROM orders WHERE idempotency_key = $1", key)  # noqa: S608

    async def get(self, order_id: uuid.UUID) -> asyncpg.Record | None:
        async with self.db.connection() as c:
            return await c.fetchrow(f"SELECT {ORDER_COLUMNS} FROM orders WHERE id = $1", order_id)  # noqa: S608

    async def claim(self, order_id: uuid.UUID, key: str, req: OrderRequest) -> bool:
        try:
            async with self.db.connection() as c:
                await c.execute(
                    "INSERT INTO orders (id, idempotency_key, customer_id, status, items) "
                    "VALUES ($1, $2, $3, 'PENDING', $4)",
                    order_id,
                    key,
                    req.customer_id,
                    json.dumps([i.model_dump() for i in req.items]),
                )
            return True
        except asyncpg.UniqueViolationError:
            return False

    async def finish(
        self, order_id: uuid.UUID, status: str, total: int | None, reason: str | None = None
    ) -> None:
        async with self.db.connection() as c:
            await c.execute(
                "UPDATE orders SET status = $2, total_cents = $3, failure_reason = $4, "
                "updated_at = now() WHERE id = $1",
                order_id,
                status,
                total,
                reason,
            )

    async def confirm(
        self, order_id: uuid.UUID, total: int, event: dict[str, Any], headers: dict[str, str]
    ) -> None:
        async with self.db.connection() as c, c.transaction():
            await c.execute(
                "UPDATE orders SET status = 'CONFIRMED', total_cents = $2, updated_at = now() WHERE id = $1",
                order_id,
                total,
            )
            await c.execute(
                "INSERT INTO outbox (event_id, subject, payload, headers) "
                "VALUES ($1, 'orders.confirmed', $2, $3)",
                uuid.UUID(event["event_id"]),
                json.dumps(event),
                json.dumps(headers),
            )


def build(settings: Settings, store: Any = None, transport: Any = None) -> FastAPI:
    db: Database | None = None
    relay: Relay | None = None
    nc: Any = None
    tasks: list[asyncio.Task] = []
    up: dict[str, Upstream] = {}

    async def startup(app: FastAPI) -> None:
        nonlocal db, store, relay, nc
        for name in ("catalog", "inventory", "payments"):
            up[name] = Upstream(
                name,
                settings.upstream_url(name),
                settings.policy(name),
                app.state.metrics,
                transport=transport,
            )
        if store is None:
            db = Database(
                settings.database_url or "",
                app.state.metrics,
                settings.db_pool_min,
                settings.db_pool_max,
                settings.db_acquire_timeout_s,
            )
            await db.start()
            store = OrderStore(db)
        if settings.nats_url and db:
            import nats

            nc = await nats.connect(
                settings.nats_url, name=f"orders-{settings.version}", max_reconnect_attempts=-1
            )
            js = nc.jetstream()
            await ensure_stream(js, settings.nats_stream_replicas)
            relay = Relay(db, js, app.state.metrics.registry)
            tasks.append(asyncio.create_task(relay.run(), name="outbox-relay"))

    async def shutdown(app: FastAPI) -> None:
        if relay:
            relay.stop()
        for t in tasks:
            await asyncio.wait([t], timeout=5)
        if nc:
            await nc.drain()
        for u in up.values():
            await u.aclose()
        if db:
            await db.close()

    async def ready(app: FastAPI) -> bool:
        return await db.healthy() if db else True

    app = create_app(settings, startup=startup, shutdown=shutdown, ready=ready)
    results = Counter(
        "orders_total", "Orders by final status.", ["status"], registry=app.state.metrics.registry
    )
    compensation_failures = Counter(
        "orders_compensation_failures_total",
        "Reservations that could not be released after a failure.",
        registry=app.state.metrics.registry,
    )

    async def release(order_id: uuid.UUID) -> None:
        try:
            await up["inventory"].request(
                "POST", f"/reservations/{order_id}/release", headers={"Idempotency-Key": str(order_id)}
            )
        except UpstreamError:
            compensation_failures.inc()
            log.error("compensation failed: reservation not released", extra={"order_id": str(order_id)})

    async def fail(
        order_id: uuid.UUID, status: str, reason: str, code: int, total: int | None = None
    ) -> JSONResponse:
        await store.finish(order_id, status, total, reason)
        results.labels(status).inc()
        trace.get_current_span().set_attribute("order.status", status)
        return JSONResponse({"id": str(order_id), "status": status, "reason": reason}, code)

    @app.post("/orders", status_code=201)
    async def place_order(req: OrderRequest, idempotency_key: str = Header(...)) -> JSONResponse:
        if not _KEY.fullmatch(idempotency_key):
            raise HTTPException(400, "Idempotency-Key must be 8-64 characters [A-Za-z0-9._-]")
        span = trace.get_current_span()
        order_id = uuid.uuid4()
        if not await store.claim(order_id, idempotency_key, req):
            existing = await store.by_key(idempotency_key)
            results.labels("replayed").inc()
            return JSONResponse(
                order_json(existing), status_code=200, headers={"Idempotent-Replayed": "true"}
            )
        span.set_attribute("order.id", str(order_id))
        try:
            # 2. prices, in parallel
            responses = await asyncio.gather(
                *(up["catalog"].request("GET", f"/products/{i.product_id}") for i in req.items)
            )
            for i, r in zip(req.items, responses, strict=True):
                if r.status_code == 404:
                    return await fail(order_id, "REJECTED", f"unknown product {i.product_id}", 422)
            total = sum(r.json()["price_cents"] * i.qty for i, r in zip(req.items, responses, strict=True))
        except UpstreamError as e:
            await fail(order_id, "FAILED", f"catalog {e.kind}", 503)
            raise
        # 3. reserve
        try:
            r = await up["inventory"].request(
                "POST",
                "/reservations",
                headers={"Idempotency-Key": str(order_id)},
                json={"order_id": str(order_id), "items": [i.model_dump() for i in req.items]},
            )
        except UpstreamError as e:
            await release(order_id)  # the reservation may exist even though we saw no answer
            await fail(order_id, "FAILED", f"inventory {e.kind}", 503, total)
            raise
        if r.status_code == 409:
            return await fail(order_id, "REJECTED", "out of stock", 409, total)
        # 4. charge
        try:
            p = await up["payments"].request(
                "POST",
                "/charges",
                headers={"Idempotency-Key": str(order_id)},
                json={"order_id": str(order_id), "amount_cents": total},
            )
        except UpstreamError as e:
            await release(order_id)
            await fail(order_id, "FAILED", f"payments {e.kind}", 503, total)
            raise
        if p.status_code == 402:
            await release(order_id)
            return await fail(order_id, "PAYMENT_DECLINED", "declined by provider", 402, total)
        if p.status_code != 201:  # 409: another attempt with this key is still running
            await release(order_id)
            return await fail(order_id, "FAILED", f"payments HTTP {p.status_code}", 503, total)
        # 5. confirm and record the event in the same transaction
        event = {
            "event_id": str(uuid.uuid4()),
            "type": "OrderConfirmed",
            "order_id": str(order_id),
            "customer_id": req.customer_id,
            "total_cents": total,
            "occurred_at": time.time(),
        }
        await store.confirm(order_id, total, event, messaging.inject())
        results.labels("CONFIRMED").inc()
        span.set_attribute("order.status", "CONFIRMED")
        return JSONResponse({"id": str(order_id), "status": "CONFIRMED", "total_cents": total}, 201)

    @app.get("/orders/{order_id}")
    async def get_order(order_id: uuid.UUID) -> dict[str, Any]:
        row = await store.get(order_id)
        if row is None:
            raise HTTPException(404, "no such order")
        return order_json(row)

    return app


app = build(Settings(service="orders"))
