"""gateway: the public API (a thin backend-for-frontend in front of catalog and orders).

It owns the request deadline: a client request gets GATEWAY_DEADLINE_S in total (unless the
client sent a shorter X-Deadline-Ms), and every service below spends at most what is left.
In naive mode there is no deadline, which is the baseline of E6.
"""

from __future__ import annotations

import os
import time
from typing import Any

from fastapi import FastAPI, Header, Query, Request
from fastapi.responses import JSONResponse

from ..common import context
from ..common.settings import Settings
from ..common.upstream import Upstream
from ..common.web import create_app


def build(settings: Settings, transport: Any = None) -> FastAPI:
    up: dict[str, Upstream] = {}
    deadline_s = float(os.environ.get("GATEWAY_DEADLINE_S", 3.0))

    async def startup(app: FastAPI) -> None:
        for name in ("catalog", "orders"):
            up[name] = Upstream(
                name,
                settings.upstream_url(name),
                settings.policy(name),
                app.state.metrics,
                transport=transport,
            )

    async def shutdown(app: FastAPI) -> None:
        for u in up.values():
            await u.aclose()

    app = create_app(settings, startup=startup, shutdown=shutdown)

    def start_clock(request: Request) -> None:
        if settings.resilience_mode == "naive":
            return
        ours = time.time() + deadline_s
        theirs = context.current_deadline()
        context.set_request(context.current_request_id() or "", min(ours, theirs or ours))

    def relay(resp: Any) -> JSONResponse:
        try:
            body = resp.json()
        except ValueError:
            body = {"error": resp.text[:200]}
        keep = {k: v for k, v in resp.headers.items() if k.lower() in ("idempotent-replayed", "retry-after")}
        return JSONResponse(body, status_code=resp.status_code, headers=keep)

    @app.get("/api/products")
    async def products(request: Request, limit: int = Query(20, ge=1, le=100)) -> JSONResponse:
        start_clock(request)
        return relay(await up["catalog"].request("GET", f"/products?limit={limit}"))

    @app.get("/api/products/{product_id}")
    async def product(request: Request, product_id: str) -> JSONResponse:
        start_clock(request)
        return relay(await up["catalog"].request("GET", f"/products/{product_id}"))

    @app.post("/api/orders")
    async def place_order(
        request: Request, body: dict[str, Any], idempotency_key: str = Header(...)
    ) -> JSONResponse:
        start_clock(request)
        return relay(
            await up["orders"].request(
                "POST", "/orders", json=body, headers={"Idempotency-Key": idempotency_key}
            )
        )

    @app.get("/api/orders/{order_id}")
    async def get_order(request: Request, order_id: str) -> JSONResponse:
        start_clock(request)
        return relay(await up["orders"].request("GET", f"/orders/{order_id}"))

    return app


app = build(Settings(service="gateway"))
