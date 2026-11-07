"""Valkey access. A cache is an optimisation, not a dependency: callers fall back to the source
of truth when it fails. `MemoryCache` stands in for Valkey in unit tests and local runs."""

from __future__ import annotations

import time

import redis.asyncio as redis


def connect(url: str, timeout_s: float = 0.2) -> redis.Redis:
    """timeout_s depends on the role Valkey plays for the caller (VALKEY_TIMEOUT_S):
    a pure cache (catalog) wants it short - a slow cache must not make a request slower than
    having no cache; a store of record (payment idempotency, notifier dedupe) wants it long
    enough that a brief stall is waited out instead of failing a request (E1 finding)."""
    return redis.Redis.from_url(
        url,
        socket_timeout=timeout_s,
        socket_connect_timeout=timeout_s,
        decode_responses=True,
        health_check_interval=10,
    )


class MemoryCache:
    """The subset of the redis.asyncio API the services use."""

    def __init__(self) -> None:
        self.data: dict[str, tuple[object, float | None]] = {}

    def _live(self, key: str) -> object | None:
        value = self.data.get(key)
        if value is None:
            return None
        if value[1] is not None and value[1] < time.monotonic():
            del self.data[key]
            return None
        return value[0]

    async def get(self, key: str) -> object | None:
        return self._live(key)

    async def set(self, key: str, value: object, ex: int | None = None, nx: bool = False) -> bool | None:
        if nx and self._live(key) is not None:
            return None
        self.data[key] = (value, time.monotonic() + ex if ex else None)
        return True

    async def exists(self, key: str) -> int:
        return int(self._live(key) is not None)

    async def delete(self, *keys: str) -> int:
        return sum(1 for k in keys if self.data.pop(k, None) is not None)

    async def lpush(self, key: str, value: object) -> int:
        items = list(self._live(key) or [])
        items.insert(0, value)
        self.data[key] = (items, None)
        return len(items)

    async def ltrim(self, key: str, start: int, end: int) -> bool:
        self.data[key] = (list(self._live(key) or [])[start : end + 1], None)
        return True

    async def lrange(self, key: str, start: int, end: int) -> list[object]:
        items = list(self._live(key) or [])
        return items[start:] if end == -1 else items[start : end + 1]

    async def ping(self) -> bool:
        return True

    async def aclose(self) -> None:
        return None
