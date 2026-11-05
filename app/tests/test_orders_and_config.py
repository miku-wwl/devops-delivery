from __future__ import annotations

from decimal import Decimal

import pytest

from demo_api.config import Settings
from demo_api.orders import OrderStore, UnknownSkuError, price_order


def test_price_order_multiplies_and_rounds_to_cents():
    assert price_order("PEN-002", 3) == (Decimal("1.20"), Decimal("3.60"))


def test_price_order_rejects_unknown_sku():
    with pytest.raises(UnknownSkuError):
        price_order("NOPE-999", 1)


@pytest.mark.parametrize(
    ("quantity", "expected_total"),
    [
        (9, Decimal("112.50")),  # below the threshold: 9 x 12.50, no discount
        (10, Decimal("112.50")),  # exactly the threshold: 125.00 - 10%
        (12, Decimal("135.00")),  # above the threshold: 150.00 - 10%
    ],
)
def test_bulk_discount_applies_from_ten_items(quantity, expected_total):
    assert price_order("BOOK-001", quantity) == (Decimal("12.50"), expected_total)


def test_store_assigns_increasing_ids():
    store = OrderStore()
    first = store.create("BOOK-001", 1, Decimal("12.50"), Decimal("12.50"))
    second = store.create("PEN-002", 1, Decimal("1.20"), Decimal("1.20"))
    assert (first.id, second.id) == (1, 2)
    assert store.get(2) == second
    assert store.get(3) is None


def test_settings_read_from_environment(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "2.0.0")
    monkeypatch.setenv("GIT_SHA", "deadbee")
    monkeypatch.setenv("FAULT_ERROR_RATE", "0.25")
    monkeypatch.setenv("FAULT_LATENCY_MS", "300")
    s = Settings.from_env()
    assert (s.version, s.commit, s.fault_error_rate, s.fault_latency_ms) == (
        "2.0.0",
        "deadbee",
        0.25,
        300.0,
    )


def test_settings_defaults_when_unset(monkeypatch):
    for name in ("APP_VERSION", "GIT_SHA", "FAULT_ERROR_RATE", "FAULT_LATENCY_MS"):
        monkeypatch.delenv(name, raising=False)
    s = Settings.from_env()
    assert (s.version, s.fault_error_rate, s.fault_latency_ms) == ("dev", 0.0, 0.0)


@pytest.mark.parametrize(
    ("name", "value"), [("FAULT_ERROR_RATE", "1.5"), ("FAULT_LATENCY_MS", "-1")]
)
def test_settings_reject_invalid_fault_values(monkeypatch, name, value):
    monkeypatch.setenv(name, value)
    with pytest.raises(ValueError):
        Settings.from_env()
