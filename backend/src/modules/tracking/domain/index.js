import { Entity } from '../../../shared/domain/entity.js';
import { Repository } from '../../../shared/domain/repository.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { assertGeoPair } from '../../../shared/domain/geo.js';

/**
 * Tracking limits - single source of truth for what a rider fix may contain
 * and how much trail a caller can ask for (mirrors ROUTING_LIMITS).
 */
export const TRACKING_LIMITS = {
  /** GPS accuracy worse than this (metres) carries no road information. */
  maxAccuracyM: 1000,
  /** ~288 km/h - faster than any delivery vehicle, so a glitch not a ride. */
  maxSpeedMps: 80,
  /** How far a device clock may run ahead of the server (seconds). */
  maxFutureSkewSec: 300,
  /** Trail points one read may return (newest slice, chronological order). */
  trailMax: 500,
  trailDefault: 120,
  /** Active-delivery queue page size for the rider screen. */
  deliveriesMax: 50,
  deliveriesDefault: 20,
  /** Fixes older than this are pruned for the order on the next insert. */
  pruneAfterDays: 7,
};

/**
 * RiderPosition - one GPS fix reported by a rider device for an order.
 *
 * Append-only: the trail is the history, so the entity carries no mutation
 * methods - validation happens once at construction (fixes are immutable
 * facts from the device, never edited afterwards).
 */
export class RiderPosition extends Entity {
  /**
   * @param {object} props
   * @param {string} [props.id] uuid (mints one when absent)
   * @param {string} props.orderId
   * @param {number} props.lat
   * @param {number} props.lng
   * @param {number} [props.accuracyM] GPS accuracy in metres
   * @param {number} [props.speedMps] speed in m/s
   * @param {number} [props.headingDeg] compass heading 0..360
   * @param {Date|string} [props.recordedAt] device time of the fix
   * @param {Date|string} [props.receivedAt] server time of arrival
   */
  constructor({ id, orderId, lat, lng, accuracyM, speedMps, headingDeg, recordedAt, receivedAt }) {
    super(id, { createdAt: receivedAt });
    this.orderId = orderId;
    this.lat = lat == null ? null : Number(lat);
    this.lng = lng == null ? null : Number(lng);
    this.accuracyM = accuracyM == null ? null : Number(accuracyM);
    this.speedMps = speedMps == null ? null : Number(speedMps);
    this.headingDeg = headingDeg == null ? null : Number(headingDeg);
    this.recordedAt = new Date(recordedAt ?? Date.now());
    this.receivedAt = this.createdAt;
    this.validate();
  }

  validate() {
    if (!this.orderId) throw DomainError.validation('orderId is required');
    if (this.lat == null || this.lng == null) throw DomainError.validation('lat and lng are required');
    assertGeoPair(this.lat, this.lng); // ranges shared with addresses/orders

    const { maxAccuracyM, maxSpeedMps, maxFutureSkewSec } = TRACKING_LIMITS;
    if (this.accuracyM != null && (!Number.isFinite(this.accuracyM) || this.accuracyM < 0 || this.accuracyM > maxAccuracyM)) {
      throw DomainError.validation(`accuracyM must be between 0 and ${maxAccuracyM}`);
    }
    if (this.speedMps != null && (!Number.isFinite(this.speedMps) || this.speedMps < 0 || this.speedMps > maxSpeedMps)) {
      throw DomainError.validation(`speedMps must be between 0 and ${maxSpeedMps}`);
    }
    if (this.headingDeg != null && (!Number.isFinite(this.headingDeg) || this.headingDeg < 0 || this.headingDeg > 360)) {
      throw DomainError.validation('headingDeg must be between 0 and 360');
    }
    if (Number.isNaN(this.recordedAt.getTime())) throw DomainError.validation('recordedAt must be a valid timestamp');
    const skew = this.recordedAt.getTime() - Date.now();
    if (skew > maxFutureSkewSec * 1000) {
      throw DomainError.validation(`recordedAt cannot be more than ${maxFutureSkewSec}s in the future`);
    }
  }

  toDto() {
    return {
      id: this.id,
      orderId: this.orderId,
      lat: this.lat,
      lng: this.lng,
      accuracyM: this.accuracyM,
      speedMps: this.speedMps,
      headingDeg: this.headingDeg,
      recordedAt: this.recordedAt.toISOString(),
      receivedAt: this.receivedAt.toISOString(),
    };
  }
}

/**
 * TrackingRepository (abstract) - persistence contract for the append-only
 * fix trail plus the active-deliveries read model (CQRS-lite: the queue is a
 * projection, never an aggregate).
 */
export class TrackingRepository extends Repository {
  /** @param {RiderPosition} _position @returns {Promise<void>} */
  async save(_position) {
    throw new Error('Not implemented');
  }

  /**
   * Newest `_limit` fixes for the order, returned in chronological order.
   * @param {string} _orderId
   * @param {number} _limit
   * @returns {Promise<object[]>} position DTOs
   */
  async listTrail(_orderId, _limit) {
    throw new Error('Not implemented');
  }

  /**
   * Deliveries still on the road that have a map pin (rider queue).
   * @param {{limit: number}} _query
   * @returns {Promise<object[]>} delivery job DTOs
   */
  async listActiveDeliveries(_query) {
    throw new Error('Not implemented');
  }
}
