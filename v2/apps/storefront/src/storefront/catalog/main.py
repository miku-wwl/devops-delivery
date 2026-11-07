"""catalog: product data from PostgreSQL behind a Valkey cache-aside layer."""

from __future__ import annotations

import json
import logging
from typing import Any, Protocol

from fastapi import FastAPI, HTTPException, Query
from prometheus_client import Counter

from ..common import cache as cachelib
from ..common.db import Database
from ..common.settings import Settings
from ..common.web import create_app

log = logging.getLogger(__name__)
PRODUCT_TTL_S, LIST_TTL_S = 60, 30


class ProductStore(Protocol):
    async def get(self, product_id: str) -> dict[str, Any] | None: ...
    async def list(self, limit: int) -> list[dict[str, Any]]: ...


class PgProductStore:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get(self, product_id: str) -> dict[str, Any] | None:
        async with self.db.connection() as c:
            row = await c.fetchrow("SELECT id, name, price_cents FROM products WHERE id = $1", product_id)
        return dict(row) if row else None

    async def list(self, limit: int) -> list[dict[str, Any]]:
        async with self.db.connection() as c:
            rows = await c.fetch("SELECT id, name, price_cents FROM products ORDER BY id LIMIT $1", limit)
        return [dict(r) for r in rows]


def build(settings: Settings, store: ProductStore | None = None, cache: Any = None) -> FastAPI:
    db: Database | None = None

    async def startup(app: FastAPI) -> None:
        nonlocal db, store, cache
        if store is None:
            db = Database(
                settings.database_url or "",
                app.state.metrics,
                settings.db_pool_min,
                settings.db_pool_max,
                settings.db_acquire_timeout_s,
            )
            await db.start()
            store = PgProductStore(db)
        if cache is None:
            cache = (
                cachelib.connect(settings.valkey_url, settings.valkey_timeout_s)
                if settings.valkey_url
                else cachelib.MemoryCache()
            )

    async def shutdown(app: FastAPI) -> None:
        if db:
            await db.close()
        if cache:
            await cache.aclose()

    async def ready(app: FastAPI) -> bool:
        return await db.healthy() if db else True

    app = create_app(settings, startup=startup, shutdown=shutdown, ready=ready)
    lookups = Counter(
        "catalog_cache_requests_total",
        "Cache lookups by result.",
        ["result"],
        registry=app.state.metrics.registry,
    )

    async def cached(key: str, ttl: int, load: Any) -> Any:
        try:
            hit = await cache.get(key)
        except Exception:  # noqa: BLE001 - degrade to the database, never fail on the cache
            lookups.labels("error").inc()
            log.warning("cache read failed", extra={"key": key})
            return await load()
        if hit is not None:
            lookups.labels("hit").inc()
            return json.loads(hit)
        lookups.labels("miss").inc()
        value = await load()
        if value is not None:
            try:
                await cache.set(key, json.dumps(value), ex=ttl)
            except Exception:  # noqa: BLE001
                log.warning("cache write failed", extra={"key": key})
        return value

    @app.get("/products")
    async def list_products(limit: int = Query(20, ge=1, le=100)) -> list[dict[str, Any]]:
        return await cached(f"catalog:products:{limit}", LIST_TTL_S, lambda: store.list(limit))

    @app.get("/products/{product_id}")
    async def get_product(product_id: str) -> dict[str, Any]:
        product = await cached(f"catalog:product:{product_id}", PRODUCT_TTL_S, lambda: store.get(product_id))
        if product is None:
            raise HTTPException(404, f"unknown product {product_id}")
        return product

    return app


app = build(Settings(service="catalog"))
