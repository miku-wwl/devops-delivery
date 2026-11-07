from __future__ import annotations

import asyncio
import json
import random
import statistics
import uuid
from datetime import UTC, datetime

import httpx
import pytest

from conftest import HostRouter, metric, running
from storefront.catalog.main import build as build_catalog
from storefront.common.cache import MemoryCache
from storefront.common.settings import Settings
from storefront.gateway.main import build as build_gateway
from storefront.inventory.main import OutOfStockError
from storefront.inventory.main import build as build_inventory
from storefront.notifier.main import Worker
from storefront.notifier.main import build as build_notifier
from storefront.orders.main import build as build_orders
from storefront.payments.main import PspBehaviour
from storefront.payments.main import build as build_payments

PRODUCTS = {
    f"sku-{i:03d}": {"id": f"sku-{i:03d}", "name": f"Product {i}", "price_cents": 500 + i * 125}
    for i in range(1, 21)
}


class FakeProducts:
    async def get(self, product_id):
        return PRODUCTS.get(product_id)

    async def list(self, limit):
        return list(PRODUCTS.values())[:limit]


class FakeStock:
    def __init__(self) -> None:
        self.available = {pid: (5 if pid in ("sku-019", "sku-020") else 1000) for pid in PRODUCTS}
        self.reservations: dict[uuid.UUID, dict] = {}

    async def reserve(self, order_id, items):
        if order_id in self.reservations:
            return self.reservations[order_id]["status"], True
        for it in items:
            if self.available[it.product_id] < it.qty:
                raise OutOfStockError(it.product_id)
        for it in items:
            self.available[it.product_id] -= it.qty
        self.reservations[order_id] = {"status": "RESERVED", "items": items}
        return "RESERVED", False

    async def release(self, order_id):
        r = self.reservations.get(order_id)
        if r is None:
            return None
        if r["status"] == "RESERVED":
            for it in r["items"]:
                self.available[it.product_id] += it.qty
            r["status"] = "RELEASED"
        return "RELEASED"

    async def stock(self, product_id):
        return {"product_id": product_id, "available": self.available.get(product_id), "reserved": 0}


class FakeOrders:
    def __init__(self) -> None:
        self.rows: dict[uuid.UUID, dict] = {}
        self.keys: dict[str, uuid.UUID] = {}
        self.outbox: list[tuple[dict, dict]] = []

    async def claim(self, order_id, key, req):
        if key in self.keys:
            return False
        self.keys[key] = order_id
        self.rows[order_id] = {
            "id": order_id,
            "customer_id": req.customer_id,
            "status": "PENDING",
            "items": [i.model_dump() for i in req.items],
            "total_cents": None,
            "failure_reason": None,
            "created_at": datetime.now(UTC),
        }
        return True

    async def by_key(self, key):
        return self.rows[self.keys[key]]

    async def get(self, order_id):
        return self.rows.get(order_id)

    async def finish(self, order_id, status, total, reason=None):
        self.rows[order_id].update(status=status, total_cents=total, failure_reason=reason)

    async def confirm(self, order_id, total, event, headers):
        self.rows[order_id].update(status="CONFIRMED", total_cents=total)
        self.outbox.append((event, headers))


QUICK_PSP = PspBehaviour(latency_p50_ms=1, latency_p99_ms=2, decline_rate=0)


def system(payments_handler=None):
    """orders wired to in-process catalog, inventory and payments apps."""
    stock, orders_store = FakeStock(), FakeOrders()
    catalog = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=MemoryCache())
    inventory = build_inventory(Settings(service="inventory"), store=stock)
    payments = build_payments(Settings(service="payments"), cache=MemoryCache(), rng=random.Random(7))
    payments.state.psp = QUICK_PSP
    routes = {"catalog": catalog, "inventory": inventory, "payments": payments_handler or payments}
    orders = build_orders(Settings(service="orders"), store=orders_store, transport=HostRouter(routes))
    return orders, orders_store, stock, payments


ORDER = {
    "customer_id": "c-1",
    "items": [{"product_id": "sku-001", "qty": 2}, {"product_id": "sku-002", "qty": 1}],
}


async def test_operational_endpoints_and_injected_faults():
    app = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=MemoryCache())
    async with running(app) as c:
        assert (await c.get("/healthz")).json() == {"status": "ok"}
        assert (await c.get("/readyz")).status_code == 200
        r = await c.get("/products/sku-001", headers={"X-Request-ID": "abc-123"})
        assert r.status_code == 200 and r.headers["X-Request-ID"] == "abc-123"
        assert (await c.get("/products/sku-001", headers={"X-Request-ID": "bad id!"})).headers[
            "X-Request-ID"
        ] != "bad id!"
        assert (await c.put("/admin/faults", json={"error_rate": 1})).status_code == 200
        assert (await c.get("/products/sku-001")).status_code == 500
        assert (await c.get("/healthz")).status_code == 200  # operational routes are exempt
        assert (await c.put("/admin/faults", json={"error_rate": 1, "status": 503})).status_code == 200
        assert (await c.get("/products/sku-001")).status_code == 503
        assert (await c.put("/admin/faults", json={"error_rate": 1})).status_code == 200
        text = (await c.get("/metrics")).text
        assert "storefront_build_info" in text and "http_server_requests_total" in text
        # the scrape does not count itself as a request in flight
        assert "http_server_inflight_requests 0.0" in text
        # the injected 500 is counted under the route template, not as "unmatched"
        labels = {"method": "GET", "route": "/products/{product_id}", "code": "500"}
        assert metric(app, "http_server_requests_total", labels) == 1
        assert metric(app, "http_server_requests_total", {**labels, "route": "/healthz"}) == 0


async def test_an_unhandled_error_is_counted_as_500_and_keeps_the_request_id():
    # the middleware is plain ASGI since E3; an exception passes through it to Starlette's
    # error handler (500), and must still be counted - it used to be silently skipped
    app = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=MemoryCache())

    @app.get("/boom")
    async def boom() -> None:
        raise RuntimeError("boom")

    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
            assert (await c.get("/boom")).status_code == 500
            ok = await c.get("/healthz", headers={"X-Request-ID": "abc-123"})
            assert ok.headers["X-Request-ID"] == "abc-123"  # operational responses carry it too
    labels = {"method": "GET", "route": "/boom", "code": "500"}
    assert metric(app, "http_server_requests_total", labels) == 1
    assert metric(app, "http_server_inflight_requests") == 0


async def test_catalog_cache_aside_and_degrades_when_the_cache_fails():
    app = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=MemoryCache())
    async with running(app) as c:
        assert (await c.get("/products/sku-003")).json()["price_cents"] == 875
        await c.get("/products/sku-003")
        assert metric(app, "catalog_cache_requests_total", {"result": "miss"}) == 1
        assert metric(app, "catalog_cache_requests_total", {"result": "hit"}) == 1
        assert (await c.get("/products/nope")).status_code == 404
        assert len((await c.get("/products?limit=5")).json()) == 5

    class Broken(MemoryCache):
        async def get(self, key):
            raise ConnectionError("valkey down")

    app = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=Broken())
    async with running(app) as c:
        assert (await c.get("/products/sku-003")).status_code == 200
        assert metric(app, "catalog_cache_requests_total", {"result": "error"}) == 1


async def test_payments_is_idempotent_and_refuses_a_concurrent_duplicate():
    cache = MemoryCache()
    app = build_payments(Settings(service="payments"), cache=cache, rng=random.Random(1))
    app.state.psp = QUICK_PSP
    body = {"order_id": str(uuid.uuid4()), "amount_cents": 1000}
    async with running(app) as c:
        first = await c.post("/charges", json=body, headers={"Idempotency-Key": "key-00000001"})
        again = await c.post("/charges", json=body, headers={"Idempotency-Key": "key-00000001"})
        assert first.status_code == 201 and again.headers["Idempotent-Replayed"] == "true"
        assert first.json()["charge_id"] == again.json()["charge_id"]
        await cache.set("psp:charge:key-00000002:lock", "1")
        busy = await c.post("/charges", json=body, headers={"Idempotency-Key": "key-00000002"})
        assert busy.status_code == 409
        assert (await c.get("/charges/key-00000001")).json()["status"] == "approved"
        assert (await c.post("/charges", json=body, headers={"Idempotency-Key": "short"})).status_code == 400


async def test_a_failed_lock_release_does_not_fail_a_completed_charge():
    """Regression (E1): a Valkey timeout on the lock DEL, after the result was stored, made a
    completed charge answer 500."""

    class SlowDelete(MemoryCache):
        async def delete(self, *keys):
            raise TimeoutError("valkey read timed out")

    cache = SlowDelete()
    app = build_payments(Settings(service="payments"), cache=cache, rng=random.Random(3))
    app.state.psp = QUICK_PSP
    body = {"order_id": str(uuid.uuid4()), "amount_cents": 1000}
    async with running(app) as c:
        r = await c.post("/charges", json=body, headers={"Idempotency-Key": "key-00000009"})
        assert r.status_code == 201
        again = await c.post("/charges", json=body, headers={"Idempotency-Key": "key-00000009"})
        assert again.headers["Idempotent-Replayed"] == "true"
        assert again.json()["charge_id"] == r.json()["charge_id"]


def test_payment_latency_model_has_the_configured_median_and_p99():
    rng = random.Random(42)
    psp = PspBehaviour(latency_p50_ms=40, latency_p99_ms=250)
    samples = sorted(psp.latency_s(rng) * 1000 for _ in range(50_000))
    assert statistics.median(samples) == pytest.approx(40, rel=0.03)
    assert samples[int(0.99 * len(samples))] == pytest.approx(250, rel=0.06)


async def test_order_saga_happy_path_and_idempotent_replay():
    orders, store, stock, _ = system()
    async with running(orders) as c:
        r = await c.post("/orders", json=ORDER, headers={"Idempotency-Key": "order-key-1"})
        assert r.status_code == 201, r.text
        body = r.json()
        assert body["status"] == "CONFIRMED" and body["total_cents"] == 2 * 625 + 750
        assert stock.available["sku-001"] == 998
        assert len(store.outbox) == 1 and store.outbox[0][0]["type"] == "OrderConfirmed"
        replay = await c.post("/orders", json=ORDER, headers={"Idempotency-Key": "order-key-1"})
        assert replay.status_code == 200 and replay.headers["Idempotent-Replayed"] == "true"
        assert replay.json()["id"] == body["id"] and len(store.outbox) == 1
        assert (await c.get(f"/orders/{body['id']}")).json()["status"] == "CONFIRMED"
        assert metric(orders, "orders_total", {"status": "CONFIRMED"}) == 1


async def test_order_rejected_when_out_of_stock_or_unknown_product():
    orders, store, stock, _ = system()
    async with running(orders) as c:
        r = await c.post(
            "/orders",
            headers={"Idempotency-Key": "order-key-2"},
            json={"customer_id": "c-1", "items": [{"product_id": "sku-019", "qty": 6}]},
        )
        assert r.status_code == 409 and r.json()["status"] == "REJECTED"
        r = await c.post(
            "/orders",
            headers={"Idempotency-Key": "order-key-3"},
            json={"customer_id": "c-1", "items": [{"product_id": "sku-999", "qty": 1}]},
        )
        assert r.status_code == 422
        assert not store.outbox


async def test_declined_payment_releases_the_reservation():
    orders, store, stock, payments = system()
    payments.state.psp = QUICK_PSP.model_copy(update={"decline_rate": 1.0})
    async with running(orders) as c:
        r = await c.post("/orders", json=ORDER, headers={"Idempotency-Key": "order-key-4"})
        assert r.status_code == 402 and r.json()["status"] == "PAYMENT_DECLINED"
        assert stock.available["sku-001"] == 1000  # compensated
        assert not store.outbox


async def test_payments_unreachable_fails_the_order_and_compensates():
    def down(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    orders, store, stock, _ = system(payments_handler=down)
    async with running(orders) as c:
        r = await c.post("/orders", json=ORDER, headers={"Idempotency-Key": "order-key-5"})
        assert r.status_code == 502 and r.json()["kind"] == "connect_error"
        assert stock.available["sku-001"] == 1000
        (row,) = store.rows.values()
        assert row["status"] == "FAILED" and row["failure_reason"] == "payments connect_error"


async def test_gateway_relays_and_requires_an_idempotency_key():
    orders, _, _, _ = system()
    catalog = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=MemoryCache())
    gateway = build_gateway(
        Settings(service="gateway"), transport=HostRouter({"orders": orders, "catalog": catalog})
    )
    async with running(orders), running(catalog), running(gateway) as c:
        assert len((await c.get("/api/products?limit=3")).json()) == 3
        assert (await c.post("/api/orders", json=ORDER)).status_code == 422
        r = await c.post("/api/orders", json=ORDER, headers={"Idempotency-Key": "order-key-6"})
        assert r.status_code == 201
        assert (await c.get(f"/api/orders/{r.json()['id']}")).json()["status"] == "CONFIRMED"


async def test_notifier_sends_once_per_event_id():
    cache = MemoryCache()
    app = build_notifier(Settings(service="notifier"), cache=cache)
    async with running(app) as c:
        worker: Worker = app.state.worker
        worker.work_ms = 0
        data = json.dumps({"event_id": "e-1", "order_id": "o-1", "occurred_at": 0}).encode()
        assert await worker.handle("orders.confirmed", data, {"Nats-Msg-Id": "e-1"}) == "sent"
        assert await worker.handle("orders.confirmed", data, {"Nats-Msg-Id": "e-1"}) == "duplicate"
        recent = (await c.get("/notifications/recent")).json()
        assert [n["order_id"] for n in recent] == ["o-1"]


async def test_loopwatch_reports_a_blocked_event_loop_with_its_stack():
    """E2: ~0.9 s stalls were seen in traces; the watchdog must report such a stall, its length,
    and where the event loop thread was."""
    import logging
    import time

    app = build_catalog(Settings(service="catalog"), store=FakeProducts(), cache=MemoryCache())
    records: list[logging.LogRecord] = []

    class Keep(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            records.append(record)

    logging.getLogger("storefront.loopwatch").addHandler(Keep())
    # time between building the app and starting it (module import, uvicorn start-up) is not a
    # stall - the first deployed version reported it as one
    time.sleep(0.4)  # noqa: ASYNC251
    async with running(app):
        await asyncio.sleep(0.2)
        time.sleep(0.6)  # noqa: ASYNC251 - block the event loop on purpose
        await asyncio.sleep(0.3)
    stalls = [r for r in records if r.getMessage() == "event loop blocked"]
    assert len(stalls) == 1, "exactly the one deliberate stall - start-up must not count"
    assert stalls[0].blocked_ms >= 450
    assert "time.sleep" in stalls[0].stack or "test_loopwatch" in stalls[0].stack
    assert stalls[0].cpu_ms < 300  # sleeping, not computing
    assert metric(app, "event_loop_lag_seconds_count") > 0
