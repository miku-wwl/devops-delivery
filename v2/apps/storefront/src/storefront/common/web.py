"""FastAPI app factory: the operational surface every service shares.

  /healthz   liveness: the process can answer (never checks dependencies)
  /readyz    readiness: startup finished, not draining, own readiness checks pass
  /metrics   Prometheus text format
  /admin/faults  GET/PUT the injected fault ([注入]: latency, error rate, status code)
Middleware: request ID and deadline, RED metrics by route template, sampled access log,
fault injection. UpstreamError and pool timeouts become 502/503/504 with a JSON body.
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
from starlette.routing import Match

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


def route_template(app: FastAPI, request: Request) -> str:
    """The route's path template ("/orders/{order_id}"), never the raw path: raw paths would
    create one time series per order id. Also correct when a fault answered before routing."""
    route = request.scope.get("route")
    if route is not None:
        return route.path
    for r in app.router.routes:
        if r.matches(request.scope)[0] is Match.FULL:
            return getattr(r, "path", "unmatched")
    return "unmatched"


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

    @app.middleware("http")
    async def observe(request: Request, call_next: Callable) -> Response:
        rid = context.request_id_from(request.headers.get(context.REQUEST_ID_HEADER))
        context.set_request(rid, context.deadline_from(request.headers.get(context.DEADLINE_HEADER)))
        operational = request.url.path.startswith(OPERATIONAL)
        started = time.perf_counter()
        # operational requests are not counted: a scrape of /metrics would otherwise always see
        # itself in flight (E3 found the gauge never below 1 - useless for Little's law)
        if not operational:
            metrics.inflight.inc()
        try:
            faults: Faults = app.state.faults
            if not operational and faults.latency_ms:
                await asyncio.sleep(faults.latency_ms / 1000)
            if not operational and faults.error_rate and random.random() < faults.error_rate:  # noqa: S311
                response: Response = JSONResponse({"error": "injected fault"}, status_code=faults.status)
            else:
                response = await call_next(request)
        finally:
            if not operational:
                metrics.inflight.dec()
        elapsed = time.perf_counter() - started
        template = route_template(app, request)
        if not operational:
            metrics.requests.labels(request.method, template, str(response.status_code)).inc()
            metrics.duration.labels(request.method, template).observe(elapsed)
            sampled = random.random() < settings.access_log_sample  # noqa: S311 - not security
            if response.status_code >= 500 or elapsed * 1000 >= settings.slow_request_ms or sampled:
                log.info(
                    "%s %s %s",
                    request.method,
                    template,
                    response.status_code,
                    extra={
                        "method": request.method,
                        "route": template,
                        "status": response.status_code,
                        "duration_ms": round(elapsed * 1000, 1),
                    },
                )
        response.headers[context.REQUEST_ID_HEADER] = rid
        return response

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
