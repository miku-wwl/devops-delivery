"""Per-request context that travels with a call chain: request ID and deadline.

The deadline is an absolute time (epoch milliseconds) sent in X-Deadline-Ms. Each service
gives every upstream call at most the time that is left, so work for a caller that has
already given up is not started at all ("deadline propagation", as in gRPC).
"""

from __future__ import annotations

import re
import time
import uuid
from contextvars import ContextVar

REQUEST_ID_HEADER = "X-Request-ID"
DEADLINE_HEADER = "X-Deadline-Ms"
VERSION_HEADER = "X-Storefront-Version"  # E8: on every response, the version that answered
_SAFE_REQUEST_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")

_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)
_deadline: ContextVar[float | None] = ContextVar("deadline", default=None)  # epoch seconds


def request_id_from(header_value: str | None) -> str:
    """Reuse the caller's ID only when it is short and plain; never log arbitrary client text."""
    if header_value and _SAFE_REQUEST_ID.fullmatch(header_value):
        return header_value
    return uuid.uuid4().hex


def deadline_from(header_value: str | None) -> float | None:
    try:
        return int(header_value) / 1000 if header_value else None
    except ValueError:
        return None


def set_request(request_id: str, deadline: float | None) -> None:
    _request_id.set(request_id)
    _deadline.set(deadline)


def current_request_id() -> str | None:
    return _request_id.get()


def current_deadline() -> float | None:
    return _deadline.get()


def remaining_seconds() -> float | None:
    deadline = _deadline.get()
    return None if deadline is None else deadline - time.time()


def outgoing_headers() -> dict[str, str]:
    headers: dict[str, str] = {}
    if rid := _request_id.get():
        headers[REQUEST_ID_HEADER] = rid
    if (deadline := _deadline.get()) is not None:
        headers[DEADLINE_HEADER] = str(int(deadline * 1000))
    return headers
