"""Trace context across NATS JetStream messages.

HTTP instrumentation propagates `traceparent` automatically; messaging does not, so producer
and consumer do it by hand with the same W3C propagator, writing it into message headers.
Spans follow the OpenTelemetry messaging conventions: PRODUCER "send <subject>" and
CONSUMER "process <subject>", so one trace shows the order request, the outbox relay and the
notification - including the time the event spent waiting in the outbox and in the stream.
"""

from __future__ import annotations

from collections.abc import Mapping

from opentelemetry import context as otel_context
from opentelemetry import propagate
from opentelemetry.context import Context


def inject(carrier: dict[str, str] | None = None, ctx: Context | None = None) -> dict[str, str]:
    carrier = carrier if carrier is not None else {}
    propagate.inject(carrier, context=ctx)
    return carrier


def extract(headers: Mapping[str, str] | None) -> Context:
    return propagate.extract(dict(headers or {}))


def attach(ctx: Context) -> object:
    return otel_context.attach(ctx)


def detach(token: object) -> None:
    otel_context.detach(token)  # type: ignore[arg-type]


def messaging_attributes(subject: str, message_id: str, operation: str) -> dict[str, str]:
    return {
        "messaging.system": "nats",
        "messaging.destination.name": subject,
        "messaging.message.id": message_id,
        "messaging.operation.type": operation,
    }
