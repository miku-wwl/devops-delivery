"""inventory: stock levels and per-order reservations in PostgreSQL.

A reservation is all-or-nothing and idempotent per order_id. Stock rows are updated with a
guarded UPDATE (available >= qty) inside one transaction, in product-id order so that two
orders for the same products cannot deadlock. Popular products are hot rows: under load the
row locks become the bottleneck (E3 measures it).
"""

from __future__ import annotations

import json
import uuid
from typing import Any

import asyncpg
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from prometheus_client import Counter
from pydantic import BaseModel, Field

from ..common.db import Database
from ..common.settings import Settings
from ..common.web import create_app


class Item(BaseModel):
    product_id: str = Field(pattern=r"^[a-z0-9-]{1,32}$")
    qty: int = Field(ge=1, le=100)


class ReservationRequest(BaseModel):
    order_id: uuid.UUID
    items: list[Item] = Field(min_length=1, max_length=20)


class OutOfStockError(Exception):
    def __init__(self, product_id: str) -> None:
        self.product_id = product_id


class PgStockStore:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def reserve(self, order_id: uuid.UUID, items: list[Item]) -> tuple[str, bool]:
        """Returns (status, replayed)."""
        try:
            async with self.db.connection() as c, c.transaction():
                existing = await c.fetchval(
                    "SELECT status FROM reservations WHERE order_id = $1 FOR UPDATE", order_id
                )
                if existing:
                    return existing, True
                for it in sorted(items, key=lambda i: i.product_id):
                    left = await c.fetchval(
                        "UPDATE stock SET available = available - $2, reserved = reserved + $2 "
                        "WHERE product_id = $1 AND available >= $2 RETURNING available",
                        it.product_id,
                        it.qty,
                    )
                    if left is None:
                        raise OutOfStockError(it.product_id)
                await c.execute(
                    "INSERT INTO reservations (order_id, items, status) VALUES ($1, $2, 'RESERVED')",
                    order_id,
                    json.dumps([i.model_dump() for i in items]),
                )
                return "RESERVED", False
        except asyncpg.UniqueViolationError:  # a concurrent duplicate won the race
            async with self.db.connection() as c:
                return await c.fetchval("SELECT status FROM reservations WHERE order_id = $1", order_id), True

    async def release(self, order_id: uuid.UUID) -> str | None:
        async with self.db.connection() as c, c.transaction():
            row = await c.fetchrow(
                "SELECT status, items FROM reservations WHERE order_id = $1 FOR UPDATE", order_id
            )
            if row is None:
                return None
            if row["status"] == "RELEASED":
                return "RELEASED"
            for it in sorted(json.loads(row["items"]), key=lambda i: i["product_id"]):
                await c.execute(
                    "UPDATE stock SET available = available + $2, reserved = reserved - $2 "
                    "WHERE product_id = $1",
                    it["product_id"],
                    it["qty"],
                )
            await c.execute(
                "UPDATE reservations SET status = 'RELEASED', updated_at = now() WHERE order_id = $1",
                order_id,
            )
            return "RELEASED"

    async def stock(self, product_id: str) -> dict[str, Any] | None:
        async with self.db.connection() as c:
            row = await c.fetchrow(
                "SELECT product_id, available, reserved FROM stock WHERE product_id = $1", product_id
            )
        return dict(row) if row else None


def build(settings: Settings, store: Any = None) -> FastAPI:
    db: Database | None = None

    async def startup(app: FastAPI) -> None:
        nonlocal db, store
        if store is None:
            db = Database(
                settings.database_url or "",
                app.state.metrics,
                settings.db_pool_min,
                settings.db_pool_max,
                settings.db_acquire_timeout_s,
            )
            await db.start()
            store = PgStockStore(db)

    async def shutdown(app: FastAPI) -> None:
        if db:
            await db.close()

    async def ready(app: FastAPI) -> bool:
        return await db.healthy() if db else True

    app = create_app(settings, startup=startup, shutdown=shutdown, ready=ready)
    outcomes = Counter(
        "inventory_reservations_total",
        "Reservation requests by result.",
        ["result"],
        registry=app.state.metrics.registry,
    )

    @app.post("/reservations", status_code=201)
    async def reserve(req: ReservationRequest) -> JSONResponse:
        try:
            status, replayed = await store.reserve(req.order_id, req.items)
        except OutOfStockError as e:
            outcomes.labels("out_of_stock").inc()
            return JSONResponse({"error": "out of stock", "product_id": e.product_id}, 409)
        outcomes.labels("replayed" if replayed else "reserved").inc()
        return JSONResponse(
            {"order_id": str(req.order_id), "status": status},
            status_code=200 if replayed else 201,
            headers={"Idempotent-Replayed": "true"} if replayed else None,
        )

    @app.post("/reservations/{order_id}/release")
    async def release(order_id: uuid.UUID) -> dict[str, str]:
        status = await store.release(order_id)
        if status is None:
            raise HTTPException(404, "no such reservation")
        outcomes.labels("released").inc()
        return {"order_id": str(order_id), "status": status}

    @app.get("/stock/{product_id}")
    async def stock(product_id: str) -> dict[str, Any]:
        row = await store.stock(product_id)
        if row is None:
            raise HTTPException(404, f"unknown product {product_id}")
        return row

    return app


app = build(Settings(service="inventory"))
