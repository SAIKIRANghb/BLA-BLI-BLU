import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { RoutingService } from '../application/routing-service.js';
import { OsrmGateway } from '../infrastructure/osrm-gateway.js';
import { env } from '../../../config/env.js';
import { ROUTING_LIMITS, SUPPORTED_PROFILES } from '../domain/index.js';

const flag = z.string().max(5).optional();
const overview = z.enum(['full', 'simplified', 'false']).optional();
const geometries = z.enum(['polyline', 'polyline6', 'geojson']).optional();

/**
 * Routing schemas - one query contract per OSRM service (single source of
 * truth for the six endpoints; deeper validation happens in the domain).
 */
export const routingSchemas = {
  nearestQuery: z.object({
    profile: z.string().max(20).optional(),
    point: z.string().min(3).max(80),
    number: z.coerce.number().int().min(1).max(ROUTING_LIMITS.nearestNumber).optional(),
  }),
  routeQuery: z.object({
    profile: z.string().max(20).optional(),
    points: z.string().min(3).max(8192),
    overview,
    geometries,
    steps: flag,
    alternatives: flag,
    annotations: flag,
  }),
  tableQuery: z.object({
    profile: z.string().max(20).optional(),
    points: z.string().min(3).max(8192),
    sources: z.string().max(512).optional(),
    destinations: z.string().max(512).optional(),
    annotations: z.string().max(40).optional(),
  }),
  matchQuery: z.object({
    profile: z.string().max(20).optional(),
    points: z.string().min(3).max(16384),
    timestamps: z.string().min(1).max(4096),
    radiuses: z.string().max(2048).optional(),
    overview,
    geometries,
  }),
  tripQuery: z.object({
    profile: z.string().max(20).optional(),
    points: z.string().min(3).max(8192),
    // The engine only supports a trip departing from its first point or
    // arriving at its last one - mirrored here so callers get a clear 422.
    source: z.enum(['any', 'first']).optional(),
    destination: z.enum(['any', 'last']).optional(),
    roundtrip: flag,
    overview,
    geometries,
  }),
  // y accepts both `12345` and `12345.mvt` (the Mapbox convention).
  tileParams: z.object({
    z: z.coerce.number().int().min(ROUTING_LIMITS.tileZoomMin).max(ROUTING_LIMITS.tileZoomMax),
    x: z.coerce.number().int().min(0),
    y: z
      .string()
      .regex(/^\d{1,10}(\.mvt)?$/, 'y must be a tile row, optionally suffixed with .mvt')
      .transform((v) => Number(v.replace('.mvt', ''))),
  }),
};

/** RoutingController - presentation facade for the six OSRM capabilities. */
export class RoutingController {
  constructor(service, { profile = 'driving' } = {}) {
    this.service = service;
    this.profile = profile;
  }

  #meta(service, query) {
    return { service, profile: query?.profile ?? this.profile, upstream: 'osrm' };
  }

  nearest = asyncHandler(async (req, res) =>
    respond.ok(res, await this.service.nearest(req.query), this.#meta('nearest', req.query)),
  );

  route = asyncHandler(async (req, res) => respond.ok(res, await this.service.route(req.query), this.#meta('route', req.query)));

  table = asyncHandler(async (req, res) => respond.ok(res, await this.service.table(req.query), this.#meta('table', req.query)));

  match = asyncHandler(async (req, res) => respond.ok(res, await this.service.match(req.query), this.#meta('match', req.query)));

  trip = asyncHandler(async (req, res) => respond.ok(res, await this.service.trip(req.query), this.#meta('trip', req.query)));

  /** Tiles are binary - they bypass the JSON envelope on purpose. */
  tile = asyncHandler(async (req, res) => {
    const { status, buffer } = await this.service.tile({
      profile: req.query.profile,
      z: Number(req.params.z),
      x: Number(req.params.x),
      y: Number(req.params.y),
    });
    if (status === 204 || buffer.length === 0) return respond.noContent(res);
    res.status(200).set('content-type', 'application/vnd.mapbox-vector-tile').send(buffer);
  });
}

/**
 * createRoutingRouter - composition root for the routing context.
 * @param {object} [overrides] DI overrides for tests (gateway/service)
 */
export function createRoutingRouter(overrides = {}) {
  const gateway =
    overrides.gateway ??
    new OsrmGateway({ baseUrl: env.routing.osrmUrl, timeoutMs: env.routing.timeoutMs });
  const service = overrides.service ?? new RoutingService({ gateway });
  const controller = new RoutingController(service, { profile: env.routing.profile });

  const table = new Router()
    .get('/routing/nearest', { schemas: { query: routingSchemas.nearestQuery }, handler: controller.nearest })
    .get('/routing/route', { schemas: { query: routingSchemas.routeQuery }, handler: controller.route })
    .get('/routing/table', { schemas: { query: routingSchemas.tableQuery }, handler: controller.table })
    .get('/routing/match', { schemas: { query: routingSchemas.matchQuery }, handler: controller.match })
    .get('/routing/trip', { schemas: { query: routingSchemas.tripQuery }, handler: controller.trip })
    .get('/routing/tile/:z/:x/:y', { schemas: { params: routingSchemas.tileParams }, handler: controller.tile });

  return bindRoutes(table);
}

export { SUPPORTED_PROFILES };
