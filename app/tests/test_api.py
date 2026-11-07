from __future__ import annotations

import logging
import re
import time

import pytest


def test_health_endpoints(client):
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").json() == {"status": "ready"}


def test_info_reports_build(client):
    body = client.get("/api/v1/info").json()
    assert body == {"service": "demo-api", "version": "1.2.3", "commit": "abc1234"}


def test_create_and_fetch_order(client):
    created = client.post("/api/v1/orders", json={"sku": "BOOK-001", "quantity": 3})
    assert created.status_code == 201
    order = created.json()
    assert order["unit_price"] == "12.50"
    assert order["total"] == "37.50"

    fetched = client.get(f"/api/v1/orders/{order['id']}")
    assert fetched.status_code == 200
    assert fetched.json() == order


def test_list_orders_returns_in_creation_order(client):
    for sku in ("PEN-002", "MUG-003"):
        client.post("/api/v1/orders", json={"sku": sku, "quantity": 1})
    skus = [o["sku"] for o in client.get("/api/v1/orders").json()]
    assert skus == ["PEN-002", "MUG-003"]


def test_unknown_sku_is_rejected(client):
    response = client.post("/api/v1/orders", json={"sku": "NOPE-999", "quantity": 1})
    assert response.status_code == 422
    assert response.json()["detail"] == "unknown SKU: NOPE-999"


@pytest.mark.parametrize("quantity", [0, -1, 101])
def test_quantity_must_be_between_1_and_100(client, quantity):
    response = client.post("/api/v1/orders", json={"sku": "BOOK-001", "quantity": quantity})
    assert response.status_code == 422


def test_missing_order_returns_404(client):
    response = client.get("/api/v1/orders/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "order not found"


def test_metrics_count_requests_by_route_template(client):
    client.post("/api/v1/orders", json={"sku": "PEN-002", "quantity": 2})
    client.get("/api/v1/orders/1")
    client.get("/api/v1/orders/42")
    text = client.get("/metrics").text
    assert (
        'http_requests_total{method="GET",route="/api/v1/orders/{order_id}",status="200"} 1.0'
        in text
    )
    assert (
        'http_requests_total{method="GET",route="/api/v1/orders/{order_id}",status="404"} 1.0'
        in text
    )
    assert "demo_api_orders_created_total 1.0" in text
    assert 'demo_api_build_info{commit="abc1234",version="1.2.3"} 1.0' in text
    assert "http_request_duration_seconds_bucket" in text


def test_injected_errors_return_500(make_client):
    faulty = make_client(fault_error_rate=1.0)
    response = faulty.post("/api/v1/orders", json={"sku": "BOOK-001", "quantity": 1})
    assert response.status_code == 500
    assert "injected fault" in response.json()["detail"]
    assert faulty.get("/healthz").status_code == 200, "health checks are never faulted"


def test_injected_latency_slows_order_creation(make_client):
    slow = make_client(fault_latency_ms=150)
    start = time.perf_counter()
    response = slow.post("/api/v1/orders", json={"sku": "MUG-003", "quantity": 1})
    assert response.status_code == 201
    assert time.perf_counter() - start >= 0.15


GENERATED_ID = re.compile(r"[0-9a-f]{32}")


def test_request_id_is_generated_when_missing(client):
    response = client.get("/api/v1/info")
    assert GENERATED_ID.fullmatch(response.headers["X-Request-ID"])


def test_safe_request_id_from_the_caller_is_reused(client):
    response = client.get("/api/v1/info", headers={"X-Request-ID": "checkout-42.retry_1"})
    assert response.headers["X-Request-ID"] == "checkout-42.retry_1"


@pytest.mark.parametrize("unsafe", ["", "has space", "x" * 65, '{"level":"error"}', "<script>"])
def test_unsafe_request_id_is_replaced(client, unsafe):
    returned = client.get("/api/v1/info", headers={"X-Request-ID": unsafe}).headers["X-Request-ID"]
    assert returned != unsafe
    assert GENERATED_ID.fullmatch(returned)


def test_request_id_is_returned_on_errors_and_logged(make_client, caplog):
    faulty = make_client(fault_error_rate=1.0)
    with caplog.at_level(logging.INFO, logger="demo_api"):
        response = faulty.get("/api/v1/info", headers={"X-Request-ID": "drill-1"})
    assert response.status_code == 500
    assert response.headers["X-Request-ID"] == "drill-1"
    access = [r for r in caplog.records if r.getMessage() == "request"]
    assert [(r.status, r.request_id) for r in access] == [(500, "drill-1")]
