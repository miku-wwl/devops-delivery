"""FastAPI app factory: the operational surface every service shares.

  /healthz   liveness: the process can answer (never checks dependencies)
  /readyz    readiness: startup finished, not draining, own readiness checks pass
  /metrics   Prometheus text format
  /admin/faults  GET/PUT the injected fault ([注入]: latency, error rate, status code)
Middleware (plain ASGI): request ID and deadline, RED metrics by route template, sampled access
log, fault injection. UpstreamError and pool timeouts become 502/503/504 with a JSON body.
"""

from __future__ import annotations

import asyncio
import logging
import os
import random
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field
from starlette.datastructures import Headers
from starlette.routing import Match
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from . import context
from .db import PoolTimeoutError
from .logs import configure_logging
from .loopwatch import LoopWatch
from .metrics import Metrics
from .settings import Settings
from .telemetry import configure_telemetry
from .upstream import UpstreamError

log = logging.getLogger("storefront.access")
OPERATIONAL = ("/healthz", "/readyz", "/metrics", "/admin/")
STATUS_FOR_KIND = {
    "circuit_open": 503,
    "bulkhead_full": 503,
    "retry_budget": 503,
    "timeout": 504,
    "deadline": 504,
    "connect_error": 502,
    "bad_status": 502,
}

Hook = Callable[[FastAPI], Awaitable[None]]


class Faults(BaseModel):
    latency_ms: float = Field(0, ge=0, le=60_000)
    error_rate: float = Field(0, ge=0, le=1)
    # 500 by default; 503 lets experiments check whether a proxy retries on status codes
    # (Istio's default route policy does not - it retries only connection failures; chapter 3)
    status: int = Field(500, ge=500, le=599)


def route_template(app: FastAPI, scope: Scope) -> str:
    """The route's path template ("/orders/{order_id}"), never the raw path: raw paths would
    create one time series per order id. Also correct when a fault answered before routing."""
    route = scope.get("route")
    if route is not None:
        return route.path
    for r in app.router.routes:
        if r.matches(scope)[0] is Match.FULL:
            return getattr(r, "path", "unmatched")
    return "unmatched"


class Observe:
    """Request ID and deadline, in-flight gauge, injected faults, RED metrics, access log.

    A plain ASGI middleware. It was an @app.middleware("http") function until E3: Starlette runs
    such a middleware's downstream app in an extra task with in-memory streams, which cost about
    6 % of the gateway's CPU in the profile (chapter 4). Behaviour is unchanged: operational
    paths are neither counted nor faulted, and every response carries the request ID - and,
    since E8 (chapter 9), the version that answered, which tells a canary from the stable release.
    """

    def __init__(self, app: ASGIApp, *, owner: FastAPI, settings: Settings, metrics: Metrics) -> None:
        self.app, self.owner, self.settings, self.metrics = app, owner, settings, metrics
        self.version_header = (context.VERSION_HEADER.lower().encode("latin-1"), settings.version.encode("latin-1"))

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = Headers(scope=scope)
        rid = context.request_id_from(headers.get(context.REQUEST_ID_HEADER))
        context.set_request(rid, context.deadline_from(headers.get(context.DEADLINE_HEADER)))
        rid_header = (context.REQUEST_ID_HEADER.lower().encode("latin-1"), rid.encode("latin-1"))
        status: int | None = None

        async def send_with_id(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
                message["headers"] = [*message.get("headers", ()), rid_header, self.version_header]
            await send(message)

        # operational requests are not counted: a scrape of /metrics would otherwise always see
        # itself in flight (E3 found the gauge never below 1 - useless for Little's law)
        if scope["path"].startswith(OPERATIONAL):
            await self.app(scope, receive, send_with_id)
            return
        metrics, started = self.metrics, time.perf_counter()
        metrics.inflight.inc()
        try:
            faults: Faults = self.owner.state.faults
            if faults.latency_ms:
                await asyncio.sleep(faults.latency_ms / 1000)
            if faults.error_rate and random.random() < faults.error_rate:  # noqa: S311
                fault = JSONResponse({"error": "injected fault"}, status_code=faults.status)
                await fault(scope, receive, send_with_id)
            else:
                await self.app(scope, receive, send_with_id)
        except Exception:
            status = status or 500  # the server's error handler answers 500 if nothing was sent
            raise
        finally:
            metrics.inflight.dec()
            if status is not None:
                self._record(scope, status, time.perf_counter() - started)

    def _record(self, scope: Scope, status: int, elapsed: float) -> None:
        method, template = scope["method"], route_template(self.owner, scope)
        self.metrics.requests.labels(method, template, str(status)).inc()
        self.metrics.duration.labels(method, template).observe(elapsed)
        sampled = random.random() < self.settings.access_log_sample  # noqa: S311 - not security
        if status >= 500 or elapsed * 1000 >= self.settings.slow_request_ms or sampled:
            log.info(
                "%s %s %s",
                method,
                template,
                status,
                extra={
                    "method": method,
                    "route": template,
                    "status": status,
                    "duration_ms": round(elapsed * 1000, 1),
                },
            )


def create_app(
    settings: Settings,
    *,
    startup: Hook | None = None,
    shutdown: Hook | None = None,
    ready: Callable[[FastAPI], Awaitable[bool]] | None = None,
) -> FastAPI:
    configure_logging(settings.service, settings.log_level)
    metrics = Metrics(settings.service, settings.version, settings.commit)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        if startup:
            await startup(app)
        watch_task = asyncio.create_task(app.state.loopwatch.run(), name="loopwatch")
        app.state.ready = True
        logging.getLogger("storefront").info(
            "started", extra={"version": settings.version, "resilience": settings.resilience_mode}
        )
        yield
        app.state.ready = False  # uvicorn stops accepting first; this covers readiness probes
        if shutdown:
            await shutdown(app)
        app.state.loopwatch.stop()
        watch_task.cancel()

    app = FastAPI(
        title=f"storefront-{settings.service}",
        version=settings.version,
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
    )
    app.state.settings, app.state.metrics, app.state.ready = settings, metrics, False
    app.state.loopwatch = LoopWatch(
        metrics.registry, stall_s=float(os.environ.get("LOOP_STALL_MS", 250)) / 1000
    )
    app.state.faults = Faults(latency_ms=settings.fault_latency_ms, error_rate=settings.fault_error_rate)

    app.add_middleware(Observe, owner=app, settings=settings, metrics=metrics)

    @app.exception_handler(UpstreamError)
    async def upstream_failed(request: Request, exc: UpstreamError) -> JSONResponse:
        code = STATUS_FOR_KIND.get(exc.kind, 502)
        headers = {"Retry-After": "1"} if code == 503 else None
        return JSONResponse(
            {
                "error": "upstream unavailable",
                "upstream": exc.upstream,
                "kind": exc.kind,
                "status": exc.status,
            },
            status_code=code,
            headers=headers,
        )

    @app.exception_handler(PoolTimeoutError)
    async def pool_exhausted(request: Request, exc: PoolTimeoutError) -> JSONResponse:
        return JSONResponse({"error": "database busy"}, status_code=503, headers={"Retry-After": "1"})

    @app.get("/healthz", include_in_schema=False)
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    async def readyz() -> JSONResponse:
        ok = bool(app.state.ready) and (await ready(app) if ready else True)
        return JSONResponse({"ready": ok}, status_code=200 if ok else 503)

    @app.get("/metrics", include_in_schema=False)
    async def prometheus() -> Response:
        return Response(generate_latest(metrics.registry), media_type=CONTENT_TYPE_LATEST)

    @app.get("/admin/faults", include_in_schema=False)
    async def get_faults() -> Faults:
        return app.state.faults

    @app.put("/admin/faults", include_in_schema=False)
    async def set_faults(faults: Faults) -> Faults:
        app.state.faults = faults
        logging.getLogger("storefront").warning("faults changed", extra=faults.model_dump())
        return faults

    configure_telemetry(app, settings)
    return app
