import { UseCase, Query } from '../../../shared/application/use-case.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { RiderPosition, TRACKING_LIMITS } from '../domain/index.js';

/**
 * ReportPosition - rider device posts one GPS fix for an order.
 *
 * The order must exist (FK), so the aggregate is loaded first; the fix is
 * then validated by the domain and appended. No state machine here: a trail
 * is history, not a transition - orders keep their own lifecycle in ordering.
 */
export class ReportPosition extends UseCase {
  /**
   * @param {object} deps
   * @param {import('../domain/index.js').TrackingRepository} deps.trackingRepo
   * @param {import('../../ordering/domain/index.js').OrderRepository} deps.orderRepo
   */
  constructor({ trackingRepo, orderRepo }) {
    super();
    this.trackingRepo = trackingRepo;
    this.orderRepo = orderRepo;
  }

  /**
   * @param {object} input {id, lat, lng, accuracyM?, speedMps?, headingDeg?, recordedAt?}
   */
  async execute({ id, ...fix }) {
    const order = await this.orderRepo.findById(id);
    if (!order) throw DomainError.notFound('Order not found');
    if (order.status.isTerminal()) {
      throw DomainError.conflict(`Order is ${order.status.value} - no longer tracking`);
    }
    const position = new RiderPosition({ orderId: order.id, ...fix });
    await this.trackingRepo.save(position);
    return position.toDto();
  }
}

/**
 * GetTrack - the customer's read of a live trail (owner only, mirroring
 * GetOrder's ownership rule: account owner or guest checkout by that email).
 */
export class GetTrack extends UseCase {
  /**
   * @param {object} deps
   * @param {import('../domain/index.js').TrackingRepository} deps.trackingRepo
   * @param {import('../../ordering/domain/index.js').OrderRepository} deps.orderRepo
   */
  constructor({ trackingRepo, orderRepo }) {
    super();
    this.trackingRepo = trackingRepo;
    this.orderRepo = orderRepo;
  }

  /** @param {object} input {id, actor, limit?} */
  async execute({ id, actor, limit }) {
    const order = await this.orderRepo.findById(id);
    if (!order) throw DomainError.notFound('Order not found');
    const owns =
      Boolean(actor) && (order.userId === actor.id || (!order.userId && order.email && order.email === actor.email));
    if (!owns) throw DomainError.forbidden('Not your order');

    const size = clampInt(limit, TRACKING_LIMITS.trailDefault, TRACKING_LIMITS.trailMax);
    const trail = await this.trackingRepo.listTrail(order.id, size);
    return {
      orderId: order.id,
      orderNumber: order.orderNumber,
      status: order.status.value,
      latest: trail.length ? trail[trail.length - 1] : null,
      trail,
      updatedAt: trail.length ? trail[trail.length - 1].recordedAt : null,
    };
  }
}

/**
 * ListActiveDeliveries - the rider's queue: orders still on the road that
 * carry a map pin (a read model - no aggregate hydration).
 */
export class ListActiveDeliveries extends Query {
  /** @param {object} deps @param {import('../domain/index.js').TrackingRepository} deps.trackingRepo */
  constructor({ trackingRepo }) {
    super();
    this.trackingRepo = trackingRepo;
  }

  /** @param {object} input {limit?} */
  async execute({ limit } = {}) {
    const size = clampInt(limit, TRACKING_LIMITS.deliveriesDefault, TRACKING_LIMITS.deliveriesMax);
    const items = await this.trackingRepo.listActiveDeliveries({ limit: size });
    return { items, total: items.length, limit: size };
  }
}

/** Coerce an untrusted query value into an int within (0, max]; garbage falls back. */
function clampInt(value, fallback, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(Math.trunc(n), max);
}
