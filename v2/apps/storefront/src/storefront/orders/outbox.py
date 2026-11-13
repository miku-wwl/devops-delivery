"""Outbox relay: publish committed events from the outbox table to NATS JetStream.

Every orders replica runs a relay. `FOR UPDATE SKIP LOCKED` lets them share the work without
publishing the same row twice at the same time. If a replica dies after publishing but before
marking the rows, another replica publishes them again; JetStream drops the duplicates because
each message carries its event id in Nats-Msg-Id (deduplication window: 2 minutes).
Delivery is therefore at-least-once into the stream and effectively once inside the window.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any

from opentelemetry import trace
from prometheus_client import Counter, Gauge, Histogram

from ..common import messaging
from ..common.db import Database
from ..common.metrics import LATENCY_BUCKETS

log = logging.getLogger(__name__)
STREAM, SUBJECTS = "ORDERS", ["orders.>"]
tracer = trace.get_tracer("storefront.orders.outbox")


async def ensure_stream(js: Any, replicas: int) -> None:
    from nats.js.api import StorageType, StreamConfig
    from nats.js.errors import NotFoundError

    config = StreamConfig(
        name=STREAM,
        subjects=SUBJECTS,
        storage=StorageType.FILE,
        num_replicas=replicas,
        duplicate_window=120,
        max_age=7 * 86_400,
    )
    try:
        await js.stream_info(STREAM)
        await js.update_stream(config)
    except NotFoundError:
        await js.add_stream(config)


class Relay:
    def __init__(self, db: Database, js: Any, registry: Any, batch: int = 50) -> None:
        self.db, self.js, self.batch = db, js, batch
        self.published = Counter("outbox_published_total", "Events published to NATS.", registry=registry)
        self.failures = Counter(
            "outbox_publish_failures_total", "Publish attempts that failed.", registry=registry
        )
        self.delay = Histogram(
            "outbox_delay_seconds", "Time from commit to publish.", buckets=LATENCY_BUCKETS, registry=registry
        )
        self.pending = Gauge("outbox_pending", "Events not yet published (sampled).", registry=registry)
        self._stop = asyncio.Event()

    async def run(self) -> None:
        last_sample = 0.0
        while not self._stop.is_set():
            try:
                n = await self.publish_once()
                if time.monotonic() - last_sample > 5:
                    async with self.db.connection() as c:
                        self.pending.set(
                            await c.fetchval("SELECT count(*) FROM outbox WHERE published_at IS NULL")
                        )
                    last_sample = time.monotonic()
            except Exception:  # noqa: BLE001 - keep relaying; the rows stay in the outbox
                self.failures.inc()
                log.exception("outbox relay failed")
                n = 0
            if n == 0:
                try:
                    await asyncio.wait_for(self._stop.wait(), 0.2)
                except TimeoutError:
                    pass

    def stop(self) -> None:
        self._stop.set()

    async def publish_once(self) -> int:
        async with self.db.connection() as c, c.transaction():
            rows = await c.fetch(
                "SELECT id, event_id, subject, payload, headers, created_at FROM outbox "
                "WHERE published_at IS NULL ORDER BY id LIMIT $1 FOR UPDATE SKIP LOCKED",
                self.batch,
            )
            for r in rows:
                parent = messaging.extract(json.loads(r["headers"]))
                with tracer.start_as_current_span(
                    f"send {r['subject']}",
                    context=parent,
                    kind=trace.SpanKind.PRODUCER,
                    attributes=messaging.messaging_attributes(r["subject"], str(r["event_id"]), "send"),
                ):
                    headers = messaging.inject({"Nats-Msg-Id": str(r["event_id"])})
                    await self.js.publish(r["subject"], r["payload"].encode(), headers=headers, timeout=2)
                self.delay.observe(max(time.time() - r["created_at"].timestamp(), 0))
            if rows:
                await c.execute(
                    "UPDATE outbox SET published_at = now() WHERE id = ANY($1::bigint[])",
                    [r["id"] for r in rows],
                )
                self.published.inc(len(rows))
        return len(rows)
