-- 003_rider_positions.sql - rider GPS trail for live delivery tracking.
-- One row per fix reported by the rider device (POST /api/tracking/...).
-- The customer's map reads the newest slice of this trail; rows are pruned
-- per order after `TRACKING_LIMITS.pruneAfterDays` days on insert.
CREATE TABLE IF NOT EXISTS rider_positions (
  id          uuid PRIMARY KEY,
  order_id    uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  lat         double precision NOT NULL,
  lng         double precision NOT NULL,
  accuracy_m  real,
  speed_mps   real,
  heading_deg real,
  recorded_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rider_positions_order_time
  ON rider_positions (order_id, recorded_at DESC);
