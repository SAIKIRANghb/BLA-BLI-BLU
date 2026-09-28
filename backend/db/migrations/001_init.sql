-- =====================================================================
-- 001_init.sql - Bla Bli Blu commerce schema (PostgreSQL 14+)
-- Bounded contexts: identity, catalog, cart, ordering, content
-- Money columns are integer paise to avoid floating point drift.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------- identity
CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text        NOT NULL,
  email         text        NOT NULL UNIQUE,
  password_hash text        NOT NULL,
  phone         text,
  role          text        NOT NULL DEFAULT 'customer',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS addresses (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label      text NOT NULL DEFAULT 'Home',
  line1      text NOT NULL,
  line2      text NOT NULL DEFAULT '',
  city       text NOT NULL,
  state      text NOT NULL,
  pincode    text NOT NULL,
  phone      text NOT NULL,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_addresses_user ON addresses(user_id);

-- ---------------------------------------------------------------- catalog
CREATE TABLE IF NOT EXISTS collections (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handle      text NOT NULL UNIQUE,
  title       text NOT NULL,
  description text NOT NULL DEFAULT '',
  image_url   text,
  position    int  NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handle            text NOT NULL UNIQUE,
  title             text NOT NULL,
  description       text NOT NULL DEFAULT '',
  tagline           text NOT NULL DEFAULT '',
  vendor            text NOT NULL DEFAULT 'Bla Bli Blu',
  product_type      text NOT NULL DEFAULT '',
  price_paise       int  NOT NULL CHECK (price_paise >= 0),
  compare_at_paise  int,
  available         boolean NOT NULL DEFAULT true,
  rating            numeric(2,1) NOT NULL DEFAULT 0,
  rating_count      int NOT NULL DEFAULT 0,
  notes_summary     text NOT NULL DEFAULT '',
  audience          text NOT NULL DEFAULT 'Unisex',
  badge             text,
  oil_concentration text,
  tags              jsonb NOT NULL DEFAULT '[]'::jsonb,
  image_url         text,
  position          int  NOT NULL DEFAULT 0,
  hidden            boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_position ON products(position);
CREATE INDEX IF NOT EXISTS idx_products_price    ON products(price_paise);
CREATE INDEX IF NOT EXISTS idx_products_tags     ON products USING gin (tags jsonb_path_ops);

CREATE TABLE IF NOT EXISTS product_images (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  image_url  text NOT NULL,
  alt        text NOT NULL DEFAULT '',
  position   int  NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_product_images_product ON product_images(product_id);

CREATE TABLE IF NOT EXISTS product_variants (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id       uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  title            text NOT NULL DEFAULT 'Default Title',
  sku              text,
  price_paise      int  NOT NULL,
  compare_at_paise int,
  available        boolean NOT NULL DEFAULT true,
  position         int  NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product ON product_variants(product_id);

CREATE TABLE IF NOT EXISTS product_notes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  note_type  text NOT NULL CHECK (note_type IN ('head','heart','base')),
  name       text NOT NULL,
  icon_url   text,
  position   int  NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_product_notes_product ON product_notes(product_id);

CREATE TABLE IF NOT EXISTS product_collections (
  product_id    uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  collection_id uuid NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  position      int  NOT NULL DEFAULT 0,
  PRIMARY KEY (product_id, collection_id)
);

CREATE TABLE IF NOT EXISTS product_reviews (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  author     text NOT NULL,
  rating     int  NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title      text NOT NULL DEFAULT '',
  body       text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_reviews_product ON product_reviews(product_id);

-- -------------------------------------------------------------------- cart
CREATE TABLE IF NOT EXISTS carts (
  id          uuid PRIMARY KEY,
  user_id     uuid REFERENCES users(id) ON DELETE SET NULL,
  coupon_code text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_carts_user ON carts(user_id);

CREATE TABLE IF NOT EXISTS cart_items (
  id              uuid PRIMARY KEY,
  cart_id         uuid NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  product_id      uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  variant_id      uuid,
  handle          text NOT NULL,
  title           text NOT NULL,
  image_url       text,
  variant_title   text,
  unit_price_paise int NOT NULL,
  quantity        int  NOT NULL CHECK (quantity > 0),
  available       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cart_items_cart ON cart_items(cart_id);

-- --------------------------------------------------------------- ordering
CREATE TABLE IF NOT EXISTS coupons (
  code              text PRIMARY KEY,
  coupon_type       text NOT NULL CHECK (coupon_type IN ('percent','flat','free_shipping')),
  value             int  NOT NULL DEFAULT 0,
  min_order_paise   int  NOT NULL DEFAULT 0,
  max_discount_paise int,
  active            boolean NOT NULL DEFAULT true,
  expires_at        timestamptz,
  description       text NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS orders (
  id              uuid PRIMARY KEY,
  order_number    text NOT NULL UNIQUE,
  user_id         uuid REFERENCES users(id) ON DELETE SET NULL,
  email           text,
  phone           text,
  status          text NOT NULL DEFAULT 'placed',
  payment_method  text NOT NULL DEFAULT 'cod',
  payment_status  text NOT NULL DEFAULT 'pending',
  subtotal_paise  int  NOT NULL DEFAULT 0,
  discount_paise  int  NOT NULL DEFAULT 0,
  shipping_paise  int  NOT NULL DEFAULT 0,
  total_paise     int  NOT NULL DEFAULT 0,
  coupon_code     text,
  address         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);

CREATE TABLE IF NOT EXISTS order_items (
  id              uuid PRIMARY KEY,
  order_id        uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id      uuid,
  handle          text NOT NULL,
  title           text NOT NULL,
  image_url       text,
  variant_title   text,
  unit_price_paise int NOT NULL,
  quantity        int  NOT NULL,
  total_paise     int  NOT NULL,
  position        int  NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS order_events (
  id         uuid PRIMARY KEY,
  order_id   uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  status     text NOT NULL,
  note       text NOT NULL DEFAULT '',
  position   int  NOT NULL DEFAULT 0,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_events_order ON order_events(order_id);

-- ---------------------------------------------------------------- content
CREATE TABLE IF NOT EXISTS site_config (
  key        text PRIMARY KEY,
  payload    jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS faqs (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category  text NOT NULL DEFAULT 'General',
  question  text NOT NULL,
  answer    text NOT NULL,
  position  int  NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS pages (
  handle     text PRIMARY KEY,
  title      text NOT NULL,
  body       text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
