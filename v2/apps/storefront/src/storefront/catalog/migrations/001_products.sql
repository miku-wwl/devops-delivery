CREATE TABLE products (
  id          text PRIMARY KEY,
  name        text NOT NULL,
  price_cents integer NOT NULL CHECK (price_cents > 0),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 20 products: sku-001 .. sku-020 (inventory seeds the same ids)
INSERT INTO products (id, name, price_cents)
SELECT 'sku-' || lpad(i::text, 3, '0'), 'Product ' || i, 500 + i * 125
FROM generate_series(1, 20) AS i;
