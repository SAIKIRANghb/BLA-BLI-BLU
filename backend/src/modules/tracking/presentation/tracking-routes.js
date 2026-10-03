import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { requireAuth } from '../../../shared/presentation/http/middlewares.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { ReportPosition, GetTrack, ListActiveDeliveries } from '../application/tracking-service.js';
import { PgTrackingRepository } from '../infrastructure/pg-tracking-repository.js';
import { PgOrderRepository } from '../../ordering/infrastructure/pg-order-repository.js';
import { TRACKING_LIMITS } from '../domain/index.js';
import { env } from '../../../config/env.js';

export const trackingSchemas = {
  idParam: z.object({ id: z.string().uuid() }),
  fix: z.object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
    accuracyM: z.number().min(0).max(TRACKING_LIMITS.maxAccuracyM).optional(),
    speedMps: z.number().min(0).max(TRACKING_LIMITS.maxSpeedMps).optional(),
    headingDeg: z.number().min(0).max(360).optional(),
    recordedAt: z.coerce.date().optional(),
  }),
  trackQuery: z.object({
    limit: z.coerce.number().int().min(2).max(TRACKING_LIMITS.trailMax).optional(),
  }),
  deliveriesQuery: z.object({
    limit: z.coerce.number().int().min(1).max(TRACKING_LIMITS.deliveriesMax).optional(),
  }),
};

/** TrackingController - thin: validated input in, DTO out. */
class TrackingController {
  constructor(useCases) {
    this.report = useCases.report;
    this.track = useCases.track;
    this.deliveries = useCases.deliveries;
  }

  reportFix = asyncHandler(async (req, res) =>
    respond.created(res, await this.report.execute({ id: req.params.id, ...req.body })),
  );

  trail = asyncHandler(async (req, res) =>
    respond.ok(
      res,
      await this.track.execute({ id: req.params.id, actor: req.user, limit: req.query.limit }),
    ),
  );

  queue = asyncHandler(async (req, res) => respond.ok(res, await this.deliveries.execute({ limit: req.query.limit })));
}

/**
 * requireRider - Decorator guarding the rider endpoints with a shared
 * `x-rider-key` header (demo stand-in for a real rider login; the same key
 * ships in the rider screen of the demo app).
 */
export function requireRider() {
  const key = env.security.riderKey;
  return (req, _res, next) => {
    if (!key || req.headers['x-rider-key'] === key) return next();
    next(DomainError.forbidden('Rider key required'));
  };
}

/**
 * createTrackingRouter - composition root for the tracking context.
 * @param {object} [overrides] test seams for the repositories
 */
export function createTrackingRouter({ tokens, ...overrides } = {}) {
  const trackingRepo = overrides.trackingRepo ?? new PgTrackingRepository();
  const orderRepo = overrides.orderRepo ?? new PgOrderRepository();

  const controller = new TrackingController({
    report: new ReportPosition({ trackingRepo, orderRepo }),
    track: new GetTrack({ trackingRepo, orderRepo }),
    deliveries: new ListActiveDeliveries({ trackingRepo }),
  });

  const auth = requireAuth(tokens);
  const rider = requireRider();

  const table = new Router()
    .post('/tracking/orders/:id/position', {
      middleware: [rider],
      schemas: { params: trackingSchemas.idParam, body: trackingSchemas.fix },
      handler: controller.reportFix,
    })
    .get('/tracking/orders/:id', {
      middleware: [auth],
      schemas: { params: trackingSchemas.idParam, query: trackingSchemas.trackQuery },
      handler: controller.trail,
    })
    .get('/tracking/deliveries', {
      middleware: [rider],
      schemas: { query: trackingSchemas.deliveriesQuery },
      handler: controller.queue,
    });

  return bindRoutes(table);
}
