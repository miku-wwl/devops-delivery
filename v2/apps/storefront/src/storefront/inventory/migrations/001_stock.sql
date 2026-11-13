CREATE TABLE stock (
  product_id text PRIMARY KEY,
  available  integer NOT NULL CHECK (available >= 0),
  reserved   integer NOT NULL DEFAULT 0 CHECK (reserved >= 0)
);

CREATE TABLE reservations (
  order_id   uuid PRIMARY KEY,
  items      jsonb NOT NULL,
  status     text NOT NULL CHECK (status IN ('RESERVED', 'RELEASED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- sku-001 .. sku-018 practically unlimited; sku-019 and sku-020 run out after 5 units
INSERT INTO stock (product_id, available)
SELECT 'sku-' || lpad(i::text, 3, '0'), CASE WHEN i <= 18 THEN 100000000 ELSE 5 END
FROM generate_series(1, 20) AS i;
