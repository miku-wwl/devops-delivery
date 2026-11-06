from __future__ import annotations

import json
import logging

import pytest
from fastapi.testclient import TestClient
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.trace import StatusCode

from demo_api.config import Settings
from demo_api.logs import JsonFormatter
from demo_api.main import create_app
from demo_api.telemetry import build_resource, configure_telemetry

EXPORTER = InMemorySpanExporter()


@pytest.fixture(scope="module", autouse=True)
def tracer_provider():
    # The global provider can be set only once per process; this module owns it.
    provider = TracerProvider()
    provider.add_span_processor(SimpleSpanProcessor(EXPORTER))
    trace.set_tracer_provider(provider)
    return provider


def traced_client(**settings) -> TestClient:
    app = create_app(Settings(**settings))
    FastAPIInstrumentor.instrument_app(app)
    EXPORTER.clear()
    return TestClient(app)


def test_order_request_produces_nested_business_spans():
    client = traced_client()
    assert client.post("/api/v1/orders", json={"sku": "BOOK-001", "quantity": 2}).status_code == 201
    spans = {s.name: s for s in EXPORTER.get_finished_spans()}
    assert {"pricing.calculate", "orders.store", "POST /api/v1/orders"} <= spans.keys()
    pricing, server = spans["pricing.calculate"], spans["POST /api/v1/orders"]
    assert pricing.attributes["order.sku"] == "BOOK-001"
    assert pricing.context.trace_id == server.context.trace_id
    assert pricing.parent.span_id == server.context.span_id


def test_injected_error_is_visible_in_the_trace():
    client = traced_client(fault_error_rate=1.0)
    assert client.get("/api/v1/info").status_code == 500
    spans = EXPORTER.get_finished_spans()
    server = next(s for s in spans if s.name == "GET /api/v1/info")
    assert server.status.status_code is StatusCode.ERROR
    assert any(e.name == "fault.injected" for s in spans for e in s.events)


def test_injected_latency_is_recorded_on_the_pricing_span():
    client = traced_client(fault_latency_ms=20)
    client.post("/api/v1/orders", json={"sku": "PEN-002", "quantity": 1})
    pricing = next(s for s in EXPORTER.get_finished_spans() if s.name == "pricing.calculate")
    assert [e.attributes["fault.latency_ms"] for e in pricing.events] == [20]
    assert (pricing.end_time - pricing.start_time) >= 20_000_000  # nanoseconds


def test_server_span_carries_the_request_id():
    client = traced_client()
    client.get("/api/v1/info", headers={"X-Request-ID": "trace-me-1"})
    server = next(s for s in EXPORTER.get_finished_spans() if s.name == "GET /api/v1/info")
    assert server.attributes["request.id"] == "trace-me-1"


def test_json_logs_carry_the_active_trace_id():
    record = logging.makeLogRecord({"msg": "hello", "levelname": "INFO", "name": "t"})
    with trace.get_tracer("test").start_as_current_span("unit") as span:
        payload = json.loads(JsonFormatter().format(record))
    assert payload["trace_id"] == format(span.get_span_context().trace_id, "032x")
    assert payload["span_id"] == format(span.get_span_context().span_id, "016x")


def test_telemetry_is_off_without_an_otlp_endpoint(monkeypatch):
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_ENDPOINT", raising=False)
    assert configure_telemetry(create_app(Settings()), Settings()) is False


def test_resource_identifies_service_version_and_environment(monkeypatch):
    monkeypatch.setenv("DEPLOY_ENV", "dev")
    attrs = build_resource(Settings(version="9.9.9")).attributes
    assert attrs["service.name"] == "demo-api"
    assert attrs["service.version"] == "9.9.9"
    assert attrs["deployment.environment.name"] == "dev"
