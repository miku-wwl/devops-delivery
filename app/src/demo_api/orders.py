"""Order domain logic: a fixed price catalogue and an in-memory order store."""

from __future__ import annotations

import itertools
import threading
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal

CATALOGUE: dict[str, Decimal] = {
    "BOOK-001": Decimal("12.50"),
    "PEN-002": Decimal("1.20"),
    "MUG-003": Decimal("8.00"),
}

CENT = Decimal("0.01")
# Bulk discount: orders of BULK_THRESHOLD or more items get BULK_DISCOUNT off.
BULK_THRESHOLD = 10
BULK_DISCOUNT = Decimal("0.10")


class UnknownSkuError(LookupError):
    """Raised when an order references a SKU that is not in the catalogue."""


def price_order(sku: str, quantity: int) -> tuple[Decimal, Decimal]:
    """Return (unit_price, total) for an order line, rounded to cents."""
    try:
        unit = CATALOGUE[sku]
    except KeyError as exc:
        raise UnknownSkuError(sku) from exc
    subtotal = unit * quantity
    if quantity >= BULK_THRESHOLD:
        subtotal -= subtotal * BULK_DISCOUNT
    total = subtotal.quantize(CENT, rounding=ROUND_HALF_UP)
    return unit, total


@dataclass(frozen=True)
class Order:
    id: int
    sku: str
    quantity: int
    unit_price: Decimal
    total: Decimal
    created_at: datetime


class OrderStore:
    """Thread-safe in-memory store. Data is lost on restart - fine for a demo workload."""

    def __init__(self) -> None:
        self._orders: dict[int, Order] = {}
        self._ids = itertools.count(1)
        self._lock = threading.Lock()

    def create(self, sku: str, quantity: int, unit_price: Decimal, total: Decimal) -> Order:
        with self._lock:
            order = Order(next(self._ids), sku, quantity, unit_price, total, datetime.now(UTC))
            self._orders[order.id] = order
            return order

    def get(self, order_id: int) -> Order | None:
        return self._orders.get(order_id)

    def list(self) -> list[Order]:
        return sorted(self._orders.values(), key=lambda o: o.id)
