"""OpenTelemetry wiring: traces and logs over OTLP/HTTP, auto-instrumented libraries.

Switched on by the standard OTEL_EXPORTER_OTLP_ENDPOINT variable; without it the services use
the no-op API, so unit tests need no collector. Sampling follows the standard
OTEL_TRACES_SAMPLER / OTEL_TRACES_SAMPLER_ARG variables (default: always on, parent-based).
"""

from __future__ import annotations

import logging
import os

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from .settings import Settings

EXCLUDED_URLS = "healthz,readyz,metrics"
_installed = False


def configure_telemetry(app: FastAPI, settings: Settings) -> bool:
    global _installed
    if not os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return False
    if not _installed:
        resource = Resource.create(
            {
                "service.name": settings.service,
                "service.namespace": "storefront",
                "service.version": settings.version,
                "deployment.environment.name": settings.environment,
            }
        )  # OTEL_RESOURCE_ATTRIBUTES (pod name, node, zone from the Downward API) is merged in
        provider = TracerProvider(resource=resource)
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(provider)
        logs = LoggerProvider(resource=resource)
        logs.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
        logging.getLogger().addHandler(LoggingHandler(level=logging.INFO, logger_provider=logs))
        HTTPXClientInstrumentor().instrument()
        AsyncPGInstrumentor().instrument()
        RedisInstrumentor().instrument()
        _installed = True
    FastAPIInstrumentor.instrument_app(app, excluded_urls=EXCLUDED_URLS)
    return True


def tracer(name: str) -> trace.Tracer:
    return trace.get_tracer(f"storefront.{name}")
