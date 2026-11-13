from __future__ import annotations

from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI


@asynccontextmanager
async def running(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    """Run the app's lifespan (startup/shutdown) and give a client bound to it."""
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


class HostRouter(httpx.AsyncBaseTransport):
    """Send each request to the in-process app named by its host (catalog, inventory, ...)
    or to a handler function: lets one test wire several services together without a network."""

    def __init__(self, routes: dict[str, FastAPI | Callable[[httpx.Request], httpx.Response]]) -> None:
        self.routes = {
            host: (
                httpx.ASGITransport(app=target)
                if isinstance(target, FastAPI)
                else httpx.MockTransport(target)
            )
            for host, target in routes.items()
        }

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        return await self.routes[request.url.host].handle_async_request(request)


def metric(app: FastAPI, name: str, labels: dict[str, str] | None = None) -> float:
    value = app.state.metrics.registry.get_sample_value(name, labels or {})
    return value or 0.0
