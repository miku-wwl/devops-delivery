CREATE TABLE orders (
  id              uuid PRIMARY KEY,
  idempotency_key text NOT NULL UNIQUE,
  customer_id     text NOT NULL,
  status          text NOT NULL
                  CHECK (status IN ('PENDING', 'CONFIRMED', 'REJECTED', 'PAYMENT_DECLINED', 'FAILED')),
  items           jsonb NOT NULL,
  total_cents     bigint,
  failure_reason  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Transactional outbox: the event is written in the same transaction as the order, and a
-- relay publishes it to NATS afterwards. No event without an order, no order without its event.
CREATE TABLE outbox (
  id           bigserial PRIMARY KEY,
  event_id     uuid NOT NULL UNIQUE,
  subject      text NOT NULL,
  payload      jsonb NOT NULL,
  headers      jsonb NOT NULL DEFAULT '{}',
  created_at   timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
CREATE INDEX outbox_unpublished ON outbox (id) WHERE published_at IS NULL;
