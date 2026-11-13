"""Integration tests against real PostgreSQL, Valkey and NATS JetStream (compose.test.yaml):
    docker compose -f compose.test.yaml run --rm tests
Skipped unless TEST_PG_URL is set."""

from __future__ import annotations

import asyncio
import os
import uuid

import asyncpg
import nats
import pytest

from conftest import HostRouter, metric, running
from storefront.catalog.main import build as build_catalog
from storefront.common import cache as cachelib
from storefront.common.db import migrate
from storefront.common.settings import Settings
from storefront.inventory.main import build as build_inventory
from storefront.notifier.main import build as build_notifier
from storefront.orders.main import build as build_orders
from storefront.payments.main import PspBehaviour
from storefront.payments.main import build as build_payments

PG = os.environ.get("TEST_PG_URL")
VALKEY = os.environ.get("TEST_VALKEY_URL", "redis://valkey:6379/0")
NATS = os.environ.get("TEST_NATS_URL", "nats://nats:4222")
pytestmark = [pytest.mark.integration, pytest.mark.skipif(not PG, reason="TEST_PG_URL not set")]


async def fresh_database(name: str) -> str:
    admin = await asyncpg.connect(f"{PG}/postgres")
    await admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
    await admin.execute(f'CREATE DATABASE "{name}"')
    await admin.close()
    return f"{PG}/{name}"


def settings(service: str, **env: str) -> Settings:
    for k, v in env.items():
        os.environ[k] = v
    try:
        return Settings(service=service)
    finally:
        for k in env:
            del os.environ[k]


async def test_migrations_apply_once():
    dsn = await fresh_database("it_migrate")
    assert await migrate(dsn, "orders") == ["001_orders.sql"]
    assert await migrate(dsn, "orders") == []


async def test_concurrent_reservations_never_oversell():
    dsn = await fresh_database("it_inventory")
    await migrate(dsn, "inventory")
    app = build_inventory(settings("inventory", DATABASE_URL=dsn, DB_POOL_MAX="10"))
    async with running(app) as c:

        async def one() -> int:
            r = await c.post(
                "/reservations",
                json={"order_id": str(uuid.uuid4()), "items": [{"product_id": "sku-019", "qty": 1}]},
            )
            return r.status_code

        codes = await asyncio.gather(*(one() for _ in range(30)))
        assert codes.count(201) == 5 and codes.count(409) == 25
        assert (await c.get("/stock/sku-019")).json() == {
            "product_id": "sku-019",
            "available": 0,
            "reserved": 5,
        }


async def test_notifier_waits_for_the_stream_instead_of_crashing():
    """Regression (E1 first deployment): the notifier started before orders had created the
    stream, failed with 'stream not found' and crash-looped. It must start, stay not-ready,
    and become ready once the stream exists."""
    nc = await nats.connect(NATS)
    js = nc.jetstream()
    try:
        await js.delete_stream("ORDERS")
    except Exception:  # noqa: BLE001,S110 - not there
        pass
    notifier = build_notifier(settings("notifier", NATS_URL=NATS, VALKEY_URL=VALKEY))
    async with running(notifier) as c:
        await asyncio.sleep(1.5)
        assert (await c.get("/readyz")).status_code == 503
        from storefront.orders.outbox import ensure_stream

        await ensure_stream(js, 1)
        for _ in range(60):
            if (await c.get("/readyz")).status_code == 200:
                break
            await asyncio.sleep(0.5)
        else:
            pytest.fail("notifier not ready 30 s after the stream appeared")
    await nc.close()


async def test_an_order_flows_through_the_outbox_and_nats_to_the_notifier():
    dsns = {svc: await fresh_database(f"it_{svc}") for svc in ("catalog", "inventory", "orders")}
    for svc, dsn in dsns.items():
        await migrate(dsn, svc)
    nc = await nats.connect(NATS)
    js = nc.jetstream()
    for stream in ("ORDERS",):
        try:
            await js.delete_stream(stream)
        except Exception:  # noqa: BLE001,S110 - not there yet
            pass
    v = cachelib.connect(VALKEY)
    await v.flushdb()

    catalog = build_catalog(settings("catalog", DATABASE_URL=dsns["catalog"], VALKEY_URL=VALKEY))
    inventory = build_inventory(settings("inventory", DATABASE_URL=dsns["inventory"]))
    payments = build_payments(settings("payments", VALKEY_URL=VALKEY))
    router = HostRouter({"catalog": catalog, "inventory": inventory, "payments": payments})
    orders = build_orders(settings("orders", DATABASE_URL=dsns["orders"], NATS_URL=NATS), transport=router)
    notifier = build_notifier(settings("notifier", NATS_URL=NATS, VALKEY_URL=VALKEY))
    async with running(catalog), running(inventory), running(payments) as _, running(orders) as oc:
        payments.state.psp = PspBehaviour(latency_p50_ms=5, latency_p99_ms=20, decline_rate=0)
        async with running(notifier) as nc_client:
            r = await oc.post(
                "/orders",
                headers={"Idempotency-Key": "it-order-0001"},
                json={"customer_id": "c-9", "items": [{"product_id": "sku-005", "qty": 3}]},
            )
            assert r.status_code == 201, r.text
            order_id = r.json()["id"]
            for _ in range(100):
                sent = (await nc_client.get("/notifications/recent")).json()
                if any(n["order_id"] == order_id for n in sent):
                    break
                await asyncio.sleep(0.1)
            else:
                pytest.fail("notification not sent within 10 s")
            assert metric(notifier, "notifier_messages_total", {"result": "sent"}) == 1
    conn = await asyncpg.connect(dsns["orders"])
    row = await conn.fetchrow("SELECT status, total_cents FROM orders WHERE id = $1", uuid.UUID(order_id))
    published = await conn.fetchval("SELECT count(*) FROM outbox WHERE published_at IS NOT NULL")
    await conn.close()
    assert dict(row) == {"status": "CONFIRMED", "total_cents": 3 * 1125} and published == 1
    info = await js.stream_info("ORDERS")
    assert info.state.messages == 1
    await v.aclose()
    await nc.close()
