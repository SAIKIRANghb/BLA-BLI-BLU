-- 002_address_geo.sql - map-picked coordinates on a saved address.
-- Both nullable: addresses created before the map picker (or saved from the
-- plain form) simply have no pin yet.
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS lat double precision;
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS lng double precision;
