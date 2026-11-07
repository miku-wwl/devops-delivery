"""OpenTelemetry wiring: traces and logs are exported over OTLP/HTTP.

Telemetry is switched on by the standard OTEL_EXPORTER_OTLP_ENDPOINT variable
(e.g. http://otel-collector.observability.svc:4318). Without it the app runs with
the no-op API - tests and local runs need no collector.
"""

from __future__ import annotations

import logging
import os

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from .config import Settings

# Health checks and metric scrapes would only add noise to the traces.
EXCLUDED_URLS = "healthz,readyz,metrics"

_providers_installed = False


def build_resource(settings: Settings) -> Resource:
    """Attributes that identify this process in every span and log record.
    OTEL_RESOURCE_ATTRIBUTES (e.g. k8s.pod.name from the Downward API) is merged in."""
    return Resource.create(
        {
            "service.name": settings.service_name,
            "service.version": settings.version,
            "deployment.environment.name": os.getenv("DEPLOY_ENV", "local"),
        }
    )


def configure_telemetry(app: FastAPI, settings: Settings) -> bool:
    """Instrument the app. Global providers are installed once per process."""
    global _providers_installed
    if not os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return False
    if not _providers_installed:
        resource = build_resource(settings)
        tracer_provider = TracerProvider(resource=resource)
        tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(tracer_provider)

        logger_provider = LoggerProvider(resource=resource)
        logger_provider.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
        logging.getLogger().addHandler(
            LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
        )
        _providers_installed = True
    FastAPIInstrumentor.instrument_app(app, excluded_urls=EXCLUDED_URLS)
    return True
