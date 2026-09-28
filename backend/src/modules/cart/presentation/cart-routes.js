import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { optionalAuth } from '../../../shared/presentation/http/middlewares.js';
import { CartUseCases } from '../application/cart-use-cases.js';
import { PgCartRepository, PgCouponRepository } from '../infrastructure/pg-cart-repository.js';
import { PgProductRepository } from '../../catalog/infrastructure/pg-repositories.js';

export const cartSchemas = {
  cartId: z.object({ cartId: z.string().uuid() }),
  lineId: z.object({ cartId: z.string().uuid(), lineId: z.string().min(6) }),
  addItem: z.object({
    productId: z.string().uuid(),
    variantId: z.string().uuid().optional().nullable(),
    qty: z.coerce.number().int().min(1).max(10).optional(),
  }),
  updateItem: z.object({ qty: z.coerce.number().int().min(0).max(10) }),
  coupon: z.object({ code: z.string().max(40).optional().nullable() }),
  quote: z.object({
    subtotalPaise: z.coerce.number().int().min(0),
    code: z.string().max(40).optional().nullable(),
  }),
  merge: z.object({ cartId: z.string().uuid() }),
};

/** CartController - presentation facade for cart operations. */
export class CartController {
  constructor(useCases) {
    this.useCases = useCases;
  }

  create = asyncHandler(async (req, res) => respond.created(res, await this.useCases.createCart({ actor: req.user })));

  get = asyncHandler(async (req, res) =>
    respond.ok(res, await this.useCases.getCart({ cartId: req.params.cartId, actor: req.user })),
  );

  addItem = asyncHandler(async (req, res) =>
    respond.ok(res, await this.useCases.addItem({ cartId: req.params.cartId, actor: req.user, ...req.body })),
  );

  updateItem = asyncHandler(async (req, res) =>
    respond.ok(res, await this.useCases.updateItem({ cartId: req.params.cartId, lineId: req.params.lineId, actor: req.user, ...req.body })),
  );

  removeItem = asyncHandler(async (req, res) =>
    respond.ok(res, await this.useCases.removeItem({ cartId: req.params.cartId, lineId: req.params.lineId, actor: req.user })),
  );

  clear = asyncHandler(async (req, res) => respond.ok(res, await this.useCases.clearCart({ cartId: req.params.cartId, actor: req.user })));

  setCoupon = asyncHandler(async (req, res) =>
    respond.ok(res, await this.useCases.setCoupon({ cartId: req.params.cartId, actor: req.user, ...req.body })),
  );

  quote = asyncHandler(async (req, res) => respond.ok(res, await this.useCases.quote({ actor: req.user, ...req.body })));

  merge = asyncHandler(async (req, res) => respond.ok(res, await this.useCases.mergeCart({ cartId: req.body.cartId, actor: req.user })));
}

/**
 * createCartRouter - composition root for the cart context.
 * @param {object} [overrides] DI overrides for tests
 */
export function createCartRouter({ tokens, ...overrides } = {}) {
  const useCases = new CartUseCases({
    cartRepo: overrides.cartRepo ?? new PgCartRepository(),
    productRepo: overrides.productRepo ?? new PgProductRepository(),
    couponRepo: overrides.couponRepo ?? new PgCouponRepository(),
  });
  const controller = new CartController(useCases);
  const auth = optionalAuth(tokens);

  const table = new Router()
    .post('/carts', { middleware: [auth], handler: controller.create })
    .post('/carts/quote', { middleware: [auth], schemas: { body: cartSchemas.quote }, handler: controller.quote })
    .post('/carts/merge', { middleware: [auth], schemas: { body: cartSchemas.merge }, handler: controller.merge })
    .get('/carts/:cartId', { middleware: [auth], schemas: { params: cartSchemas.cartId }, handler: controller.get })
    .post('/carts/:cartId/items', {
      middleware: [auth],
      schemas: { params: cartSchemas.cartId, body: cartSchemas.addItem },
      handler: controller.addItem,
    })
    .patch('/carts/:cartId/items/:lineId', {
      middleware: [auth],
      schemas: { params: cartSchemas.lineId, body: cartSchemas.updateItem },
      handler: controller.updateItem,
    })
    .delete('/carts/:cartId/items/:lineId', {
      middleware: [auth],
      schemas: { params: cartSchemas.lineId },
      handler: controller.removeItem,
    })
    .delete('/carts/:cartId', { middleware: [auth], schemas: { params: cartSchemas.cartId }, handler: controller.clear })
    .post('/carts/:cartId/coupon', {
      middleware: [auth],
      schemas: { params: cartSchemas.cartId, body: cartSchemas.coupon },
      handler: controller.setCoupon,
    });

  return bindRoutes(table);
}
