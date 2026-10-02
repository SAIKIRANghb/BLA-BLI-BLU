import { DomainError } from './domain-error.js';

/**
 * assertGeoPair - shared invariant for the optional WGS84 coordinate pair
 * carried by saved addresses and the shipping snapshot on an order.
 *
 * Both fields must arrive together (or be entirely absent - "not picked
 * yet"); ranges follow EPSG:4326.
 *
 * @param {unknown} lat
 * @param {unknown} lng
 * @throws {DomainError} when the pair is half-set or out of range
 */
export function assertGeoPair(lat, lng) {
  if (lat == null && lng == null) return;
  if (lat == null || lng == null) {
    throw DomainError.validation('lat and lng must be provided together');
  }
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    throw DomainError.validation('lat must be a number between -90 and 90');
  }
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    throw DomainError.validation('lng must be a number between -180 and 180');
  }
}
