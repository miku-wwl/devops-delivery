"""One-line JSON logs on stdout, correlated with traces and requests."""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime

from opentelemetry import trace

from .context import current_request_id

_RESERVED = set(vars(logging.makeLogRecord({})))


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str) -> None:
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname.lower(),
            "service": self.service,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            payload["trace_id"] = format(ctx.trace_id, "032x")
            payload["span_id"] = format(ctx.span_id, "016x")
        if rid := current_request_id():
            payload["request_id"] = rid
        payload.update(
            {k: v for k, v in vars(record).items() if k not in _RESERVED and not k.startswith("otel")}
        )
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str, ensure_ascii=False)


def configure_logging(service: str, level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(service))
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
    # uvicorn's own access log is replaced by the sampled access log in web.py
    logging.getLogger("uvicorn.access").disabled = True
    # httpx logs every outgoing request at INFO: 4 log lines per order (E1 baseline), i.e. a
    # log line per dependency call at any load. Failures still surface as WARNING/ERROR.
    logging.getLogger("httpx").setLevel(logging.WARNING)
