"""PostgreSQL access: an asyncpg pool with metrics and an acquire timeout, and migrations.

The pool is the service's bulkhead towards the database: at most DB_POOL_MAX connections, and
a request waits at most DB_ACQUIRE_TIMEOUT_S for one before it fails with 503 (PoolTimeoutError)
instead of queueing without bound. Migrations run once per release in an init container:
    python -m storefront.common.db migrate <service>
"""

from __future__ import annotations

import asyncio
import logging
import sys
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from importlib import resources

import asyncpg

from .metrics import Metrics

log = logging.getLogger(__name__)
MIGRATION_LOCK = 7_340_001  # pg_advisory_lock key shared by all migration runners


class PoolTimeoutError(Exception):
    pass


class Database:
    def __init__(
        self,
        dsn: str,
        metrics: Metrics,
        min_size: int = 1,
        max_size: int = 10,
        acquire_timeout_s: float = 1.0,
    ) -> None:
        self.dsn, self.metrics = dsn, metrics
        self.min_size, self.max_size, self.acquire_timeout_s = min_size, max_size, acquire_timeout_s
        self.pool: asyncpg.Pool | None = None

    async def start(self) -> None:
        self.pool = await asyncpg.create_pool(
            self.dsn, min_size=self.min_size, max_size=self.max_size, command_timeout=10
        )
        m = self.metrics.db_connections
        m.labels("max").set(self.max_size)
        m.labels("open").set_function(lambda: self.pool.get_size() if self.pool else 0)
        m.labels("in_use").set_function(
            lambda: (self.pool.get_size() - self.pool.get_idle_size()) if self.pool else 0
        )

    async def close(self) -> None:
        if self.pool:
            await self.pool.close()

    @asynccontextmanager
    async def connection(self) -> AsyncIterator[asyncpg.Connection]:
        assert self.pool is not None, "Database.start() was not called"  # noqa: S101
        started = time.perf_counter()
        try:
            conn = await self.pool.acquire(timeout=self.acquire_timeout_s)
        except TimeoutError:
            self.metrics.db_acquire_timeouts.inc()
            raise PoolTimeoutError from None
        finally:
            self.metrics.db_acquire.observe(time.perf_counter() - started)
        try:
            yield conn
        finally:
            await self.pool.release(conn)

    async def healthy(self) -> bool:
        try:
            async with self.connection() as conn:
                return await conn.fetchval("SELECT 1") == 1
        except Exception:  # noqa: BLE001 - readiness must answer, whatever the failure
            return False


async def migrate(dsn: str, service: str) -> list[str]:
    """Apply storefront/<service>/migrations/*.sql in name order, each once, under a lock."""
    files = sorted(
        (
            f
            for f in resources.files(f"storefront.{service}").joinpath("migrations").iterdir()
            if f.name.endswith(".sql")
        ),
        key=lambda f: f.name,
    )
    conn = await asyncpg.connect(dsn)
    applied = []
    try:
        await conn.execute("SELECT pg_advisory_lock($1)", MIGRATION_LOCK)
        await conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            "name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())"
        )
        done = {r["name"] for r in await conn.fetch("SELECT name FROM schema_migrations")}
        for f in files:
            if f.name in done:
                continue
            async with conn.transaction():
                await conn.execute(f.read_text(encoding="utf-8"))
                await conn.execute("INSERT INTO schema_migrations(name) VALUES ($1)", f.name)
            applied.append(f.name)
    finally:
        await conn.execute("SELECT pg_advisory_unlock($1)", MIGRATION_LOCK)
        await conn.close()
    return applied


def main(argv: list[str]) -> int:
    import os

    if len(argv) != 3 or argv[1] != "migrate":
        print("usage: python -m storefront.common.db migrate <service>", file=sys.stderr)
        return 2
    applied = asyncio.run(migrate(os.environ["DATABASE_URL"], argv[2]))
    print(f"{argv[2]}: applied {applied or 'nothing (up to date)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
