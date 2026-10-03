import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { env } from './config/env.js';
import { createLogger } from './shared/infrastructure/logger.js';
import { EventBus } from './shared/infrastructure/event-bus.js';
import { requestLogger, errorHandler, notFound } from './shared/presentation/http/middlewares.js';
import { createCatalogRouter } from './modules/catalog/presentation/catalog-routes.js';
import { createContentRouter } from './modules/content/presentation/content-routes.js';
import { createIdentityRouter } from './modules/identity/presentation/identity-routes.js';
import { createCartRouter } from './modules/cart/presentation/cart-routes.js';
import { createOrderRouter } from './modules/ordering/presentation/order-routes.js';
import { createRoutingRouter } from './modules/routing/presentation/routing-routes.js';
import { createTrackingRouter } from './modules/tracking/presentation/tracking-routes.js';
import { TokenService } from './shared/infrastructure/security.js';

/**
 * App composition root (Composition over inheritance).
 *
 * One shared TokenService + EventBus instance is injected into every bounded
 * context so auth and domain events behave consistently across the API.
 */
export function createApp(overrides = {}) {
  const logger = overrides.logger ?? createLogger(env.nodeEnv);
  const eventBus = overrides.eventBus ?? new EventBus();
  const tokens =
    overrides.tokens ??
    new TokenService({
      secret: env.security.jwtSecret,
      accessTtl: env.security.accessTtl,
      refreshTtl: env.security.refreshTtl,
    });

  const app = express();
  app.disable('x-powered-by');
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(
    cors({
      origin: env.server.corsOrigins.includes('*') ? true : env.server.corsOrigins,
      credentials: false,
    }),
  );
  app.use(express.json({ limit: '1mb' }));
  app.use(requestLogger(logger));

  app.get('/api/health', (_req, res) =>
    res.json({ success: true, data: { status: 'up', time: new Date().toISOString(), service: 'blabliblu-api' } }),
  );

  // ---- bounded contexts -------------------------------------------------
  app.use('/api', createCatalogRouter(overrides.catalog));
  app.use('/api', createContentRouter(overrides.content));
  app.use('/api', createIdentityRouter({ tokens, ...(overrides.identity ?? {}) }).router);
  app.use('/api', createCartRouter({ tokens, ...(overrides.cart ?? {}) }));
  app.use('/api', createOrderRouter({ tokens, eventBus, ...(overrides.order ?? {}) }));
  // OpenStreetMap / OSRM: nearest, route, table, match, trip, tile.
  app.use('/api', createRoutingRouter(overrides.routing ?? {}));
  // Rider GPS trail: report a fix (rider key), read the trail (order owner).
  app.use('/api', createTrackingRouter({ tokens, ...(overrides.tracking ?? {}) }));

  // ---- cross-cutting listeners (Observer) ------------------------------
  registerDomainListeners(eventBus, logger);

  app.use(notFound);
  app.use(errorHandler(logger));
  return { app, logger, eventBus, tokens };
}

/**
 * Domain event reactions - the ordering context stays unaware of them
 * (Open/Closed: add a listener without touching the publisher).
 */
function registerDomainListeners(eventBus, logger) {
  eventBus.on('order.placed', (payload) => {
    logger.info(`Order placed ${payload.orderNumber}`, { total: payload.total, items: payload.itemCount });
  });
  eventBus.on('order.status_changed', (payload) => {
    logger.info(`Order ${payload.orderNumber} -> ${payload.status}`);
  });
  eventBus.on('user.registered', (payload) => {
    logger.info('New account created', { userId: payload.userId });
  });
}
