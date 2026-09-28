import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { optionalAuth, requireAuth } from '../../../shared/presentation/http/middlewares.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { PlaceOrder, ListOrders, GetOrder, TrackOrder, UpdateOrderStatus } from '../application/order-use-cases.js';
import { PgOrderRepository } from '../infrastructure/pg-order-repository.js';
import { PgCartRepository, PgCouponRepository } from '../../cart/infrastructure/pg-cart-repository.js';
import { PgProductRepository } from '../../catalog/infrastructure/pg-repositories.js';
import { PgAddressRepository } from '../../identity/infrastructure/pg-repositories.js';
import { PostgresUnitOfWork } from '../../../shared/infrastructure/postgres-unit-of-work.js';
import { EventBus } from '../../../shared/infrastructure/event-bus.js';
import { env } from '../../../config/env.js';

const addressSchema = z.object({
  name: z.string().min(2).max(60),
  phone: z.string().regex(/^\d{10}$/),
  line1: z.string().min(3).max(120),
  line2: z.string().max(120).optional(),
  city: z.string().min(2).max(60),
  state: z.string().min(2).max(60),
  pincode: z.string().regex(/^\d{6}$/),
  label: z.string().max(30).optional(),
});

export const orderSchemas = {
  place: z.object({
    cartId: z.string().uuid(),
    paymentMethod: z.enum(['cod', 'upi', 'card']).default('cod'),
    email: z.string().email().optional(),
    name: z.string().min(2).max(60).optional(),
    addressId: z.string().uuid().optional(),
    address: addressSchema.optional(),
  }),
  listQuery: z.object({
    page: z.coerce.number().int().min(1).optional(),
    limit: z.coerce.number().int().min(1).max(50).optional(),
  }),
  idParam: z.object({ id: z.string().uuid() }),
  trackQuery: z.object({
    orderNumber: z.string().min(6).max(40),
    email: z.string().email().optional(),
    phone: z.string().regex(/^\d{10}$/).optional(),
  }),
  status: z.object({
    status: z.enum(['confirmed', 'packed', 'shipped', 'delivered', 'cancelled']),
    note: z.string().max(160).optional(),
  }),
};

/** OrderController - checkout / history / tracking presentation facade. */
export class OrderController {
  constructor(useCases) {
    this.useCases = useCases;
  }

  place = asyncHandler(async (req, res) => respond.created(res, await this.useCases.place.execute({ ...req.body, actor: req.user })));
  list = asyncHandler(async (req, res) => {
    const result = await this.useCases.list.execute({ actor: req.user, ...req.query });
    respond.ok(res, result.items, { total: result.total, page: result.page, limit: result.limit });
  });
  detail = asyncHandler(async (req, res) => respond.ok(res, await this.useCases.get.execute({ id: req.params.id, actor: req.user })));
  track = asyncHandler(async (req, res) => respond.ok(res, await this.useCases.track.execute(req.query)));
  updateStatus = asyncHandler(async (req, res) =>
    respond.ok(res, await this.useCases.update.execute({ id: req.params.id, ...req.body })),
  );
}

/**
 * createOrderRouter - composition root for the ordering context.
 * @param {object} [overrides]
 */
export function createOrderRouter({ tokens, eventBus = new EventBus(), ...overrides } = {}) {
  const orderRepo = overrides.orderRepo ?? new PgOrderRepository();
  const cartRepo = overrides.cartRepo ?? new PgCartRepository();
  const productRepo = overrides.productRepo ?? new PgProductRepository();
  const couponRepo = overrides.couponRepo ?? new PgCouponRepository();
  const addressRepo = overrides.addressRepo ?? new PgAddressRepository();

  const uow =
    overrides.uow ??
    new PostgresUnitOfWork(undefined, (client) => ({
      orders: new PgOrderRepository(client),
      carts: new PgCartRepository(client),
    }));

  const useCases = {
    place: new PlaceOrder({ cartRepo, productRepo, couponRepo, addressRepo, uow, eventBus }),
    list: new ListOrders({ orderRepo }),
    get: new GetOrder({ orderRepo }),
    track: new TrackOrder({ orderRepo }),
    update: new UpdateOrderStatus({ orderRepo, eventBus }),
  };

  const controller = new OrderController(useCases);
  const auth = requireAuth(tokens);
  const guest = optionalAuth(tokens);
  const admin = requireAdmin();

  const table = new Router()
    .post('/orders', { middleware: [guest], schemas: { body: orderSchemas.place }, handler: controller.place })
    .get('/orders', { middleware: [auth], schemas: { query: orderSchemas.listQuery }, handler: controller.list })
    .get('/orders/track', { schemas: { query: orderSchemas.trackQuery }, handler: controller.track })
    .get('/orders/:id', { middleware: [auth], schemas: { params: orderSchemas.idParam }, handler: controller.detail })
    .patch('/admin/orders/:id/status', {
      middleware: [admin],
      schemas: { params: orderSchemas.idParam, body: orderSchemas.status },
      handler: controller.updateStatus,
    });

  return bindRoutes(table);
}

/**
 * requireAdmin - Decorator guarding the fulfilment endpoints with a shared
 * `x-api-key` header (demo stand-in for a real admin console).
 */
function requireAdmin() {
  const key = env.security.adminKey;
  return (req, _res, next) => {
    if (!key || req.headers['x-api-key'] === key) return next();
    next(DomainError.forbidden('Admin key required'));
  };
}
