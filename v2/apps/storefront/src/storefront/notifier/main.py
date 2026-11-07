"""notifier: consumes order events from NATS JetStream and "sends" a notification.

A durable pull consumer: replicas share the work, a message that is not acknowledged within
`ack_wait` is delivered again (at most `max_deliver` times). Processing is at-least-once;
an event id already marked done in Valkey is acknowledged without sending again. The number of
unprocessed messages is what KEDA scales this deployment on (E4). NOTIFY_WORK_MS simulates the
cost of sending (an e-mail provider call).
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from typing import Any

from fastapi import FastAPI, Query
from opentelemetry import trace
from prometheus_client import Counter, Histogram

from ..common import cache as cachelib
from ..common import messaging
from ..common.metrics import LATENCY_BUCKETS
from ..common.settings import Settings
from ..common.web import create_app

log = logging.getLogger(__name__)
tracer = trace.get_tracer("storefront.notifier")
STREAM, DURABLE, SUBJECT = "ORDERS", "notifier", "orders.>"
RECENT = "notifier:recent"


class Worker:
    def __init__(self, cache: Any, registry: Any, work_ms: float, concurrency: int) -> None:
        self.cache, self.work_ms = cache, work_ms
        self.sem = asyncio.Semaphore(concurrency)
        self.messages = Counter(
            "notifier_messages_total", "Messages by result.", ["result"], registry=registry
        )
        self.end_to_end = Histogram(
            "notifier_end_to_end_seconds",
            "From order confirmation to notification sent.",
            buckets=LATENCY_BUCKETS,
            registry=registry,
        )
        self._stop = asyncio.Event()

    async def handle(self, subject: str, data: bytes, headers: dict[str, str] | None) -> str:
        event = json.loads(data)
        event_id = (headers or {}).get("Nats-Msg-Id", event.get("event_id", ""))
        with tracer.start_as_current_span(
            f"process {subject}",
            context=messaging.extract(headers),
            kind=trace.SpanKind.CONSUMER,
            attributes=messaging.messaging_attributes(subject, event_id, "process"),
        ):
            done = f"notifier:done:{event_id}"
            if await self.cache.exists(done):
                self.messages.labels("duplicate").inc()
                return "duplicate"
            await asyncio.sleep(self.work_ms / 1000)  # the simulated provider call
            await self.cache.set(done, "1", ex=86_400)
            await self.cache.lpush(
                RECENT,
                json.dumps({"order_id": event.get("order_id"), "event_id": event_id, "sent_at": time.time()}),
            )
            await self.cache.ltrim(RECENT, 0, 999)
            if occurred := event.get("occurred_at"):
                self.end_to_end.observe(max(time.time() - float(occurred), 0))
            self.messages.labels("sent").inc()
            return "sent"

    async def _one(self, msg: Any) -> None:
        try:
            await self.handle(msg.subject, msg.data, msg.headers)
            await msg.ack()
        except Exception:  # noqa: BLE001 - nak: JetStream redelivers after the delay
            self.messages.labels("failed").inc()
            log.exception("notification failed")
            await msg.nak(delay=1)
        finally:
            self.sem.release()

    async def run(self, sub: Any, batch: int) -> None:
        from nats.errors import TimeoutError as NatsTimeout

        tasks: set[asyncio.Task] = set()
        while not self._stop.is_set():
            try:
                msgs = await sub.fetch(batch, timeout=1)
            except NatsTimeout:
                continue
            except Exception:  # noqa: BLE001 - connection trouble: back off, nats reconnects
                log.exception("fetch failed")
                await asyncio.sleep(1)
                continue
            for msg in msgs:
                await self.sem.acquire()
                t = asyncio.create_task(self._one(msg))
                tasks.add(t)
                t.add_done_callback(tasks.discard)
        if tasks:
            await asyncio.wait(tasks, timeout=10)

    def stop(self) -> None:
        self._stop.set()


def build(settings: Settings, cache: Any = None) -> FastAPI:
    nc: Any = None
    worker: Worker | None = None
    tasks: list[asyncio.Task] = []
    subscribed = asyncio.Event()
    work_ms = float(os.environ.get("NOTIFY_WORK_MS", 20))
    concurrency = int(os.environ.get("NOTIFIER_CONCURRENCY", 16))

    async def startup(app: FastAPI) -> None:
        nonlocal nc, worker, cache
        if cache is None:
            cache = (
                cachelib.connect(settings.valkey_url, settings.valkey_timeout_s)
                if settings.valkey_url
                else cachelib.MemoryCache()
            )
        worker = Worker(cache, app.state.metrics.registry, work_ms, concurrency)
        app.state.worker = worker
        if settings.nats_url:
            import nats
            from nats.js.api import AckPolicy, ConsumerConfig
            from nats.js.errors import NotFoundError

            nc = await nats.connect(
                settings.nats_url, name=f"notifier-{settings.version}", max_reconnect_attempts=-1
            )
            js = nc.jetstream()

            async def subscribe_then_run() -> None:
                # The stream belongs to orders (the producer). Until it exists, wait and report
                # not-ready instead of crashing: a crash loop here only adds restart back-off.
                delay = 1.0
                while True:
                    try:
                        sub = await js.pull_subscribe(
                            SUBJECT,
                            durable=DURABLE,
                            stream=STREAM,
                            config=ConsumerConfig(
                                ack_policy=AckPolicy.EXPLICIT,
                                ack_wait=30,
                                max_deliver=5,
                                max_ack_pending=1000,
                            ),
                        )
                        break
                    except NotFoundError:
                        log.warning("stream %s not found yet; retrying in %.0f s", STREAM, delay)
                        await asyncio.sleep(delay)
                        delay = min(delay * 2, 15)
                subscribed.set()
                await worker.run(sub, batch=concurrency)

            tasks.append(asyncio.create_task(subscribe_then_run(), name="consumer"))

    async def shutdown(app: FastAPI) -> None:
        if worker:
            worker.stop()
        for t in tasks:
            done, _ = await asyncio.wait([t], timeout=15)
            if not done:  # still waiting for the stream, or stuck: do not block shutdown
                t.cancel()
        if nc:
            await nc.drain()
        if cache:
            await cache.aclose()

    async def ready(app: FastAPI) -> bool:
        return (nc.is_connected and subscribed.is_set()) if nc else True

    app = create_app(settings, startup=startup, shutdown=shutdown, ready=ready)

    @app.get("/notifications/recent")
    async def recent(limit: int = Query(10, ge=1, le=100)) -> list[dict[str, Any]]:
        return [json.loads(x) for x in await cache.lrange(RECENT, 0, limit - 1)]

    return app


app = build(Settings(service="notifier"))
