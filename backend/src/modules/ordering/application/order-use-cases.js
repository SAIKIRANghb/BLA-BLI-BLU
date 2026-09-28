import { randomUUID } from 'node:crypto';
import { UseCase } from '../../../shared/application/use-case.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Money } from '../../../shared/domain/money.js';
import { PricingService, StandardPricingStrategy } from '../../../shared/domain/pricing.js';
import { env } from '../../../config/env.js';
import { Order, OrderItem, ShippingAddress } from '../domain/index.js';

/**
 * PlaceOrder - the checkout use case.
 *
 * Transactional (Unit of Work): the order is persisted and the cart cleared in
 * one atomic step. Prices are re-read from the catalogue right before charging
 * (never trust a client-side snapshot), then the pricing domain service
 * computes totals so cart and checkout always agree.
 */
export class PlaceOrder extends UseCase {
  /**
   * @param {object} deps
   * @param {import('../../cart/domain/index.js').CartRepository} deps.cartRepo
   * @param {import('../../catalog/domain/repositories.js').ProductRepository} deps.productRepo
   * @param {import('../../cart/infrastructure/pg-cart-repository.js').CouponRepository} deps.couponRepo
   * @param {import('../../../shared/application/unit-of-work.js').UnitOfWork} deps.uow
   * @param {import('../../../shared/infrastructure/event-bus.js').EventBus} deps.eventBus
   */
  constructor({ cartRepo, productRepo, couponRepo, addressRepo, uow, eventBus }) {
    super();
    this.cartRepo = cartRepo;
    this.productRepo = productRepo;
    this.couponRepo = couponRepo;
    this.addressRepo = addressRepo;
    this.uow = uow;
    this.eventBus = eventBus;
    this.pricing = new PricingService(
      new StandardPricingStrategy({
        freeShippingThresholdPaise: env.commerce.freeShippingThresholdPaise,
        shippingFeePaise: env.commerce.shippingFeePaise,
      }),
    );
  }

  async execute({ cartId, address, addressId, paymentMethod = 'cod', email, phone, actor, name }) {
    const cart = await this.cartRepo.findById(cartId);
    if (!cart) throw DomainError.notFound('Cart not found');
    if (cart.userId && cart.userId !== actor?.id) throw DomainError.forbidden('This cart belongs to another account');
    if (cart.isEmpty) throw DomainError.validation('Your cart is empty');

    const shipping = await this._resolveAddress({ address, addressId, actor, email, phone, name });

    // 1. refresh prices from the catalogue + verify availability
    const lines = [];
    for (const line of cart.lines) {
      const product = await this.productRepo.findById(line.productId);
      if (!product || !product.available) {
        throw new DomainError(`"${line.title}" is out of stock`, { code: 'OUT_OF_STOCK', status: 409 });
      }
      const variant = line.variantId ? product.variants.find((v) => v.id === line.variantId) : product.primaryVariant();
      lines.push({ line, product, unitPrice: variant?.price ?? product.price });
    }

    const subtotal = lines.reduce((sum, l) => sum.plus(l.unitPrice.times(l.line.quantity.value)), Money.zero());

    // 2. price with coupon (validated by the promotion port)
    const coupon = cart.couponCode ? await this.couponRepo.findActive(cart.couponCode) : null;
    if (cart.couponCode && !coupon) throw DomainError.validation('Your coupon is no longer valid');
    const totals = this.pricing.price({ subtotal, coupon });

    // 3. build the aggregate
    const order = new Order({
      id: randomUUID(),
      orderNumber: Order.generateOrderNumber(),
      userId: actor?.id ?? null,
      email: email ?? actor?.email ?? null,
      phone: shipping.phone,
      paymentMethod,
      paymentStatus: paymentMethod === 'cod' ? 'pending' : 'paid',
      subtotal: subtotal.paise,
      discount: totals.discountPaise,
      shipping: totals.shippingPaise,
      total: totals.totalPaise,
      couponCode: totals.couponCode,
      address: shipping,
      items: lines.map(
        (l) =>
          new OrderItem({
            id: randomUUID(),
            productId: l.product.id,
            handle: l.product.handle.value,
            title: l.product.title,
            imageUrl: l.product.imageUrl,
            variantTitle: l.line.variantTitle,
            unitPrice: l.unitPrice,
            quantity: l.line.quantity.value,
          }),
      ),
    });
    order.markPlaced();

    // 4. atomic write (order + order items + events, cart cleared)
    await this.uow.run(async ({ orders, carts }) => {
      await orders.save(order);
      cart.clear();
      await carts.save(cart);
    });

    this.eventBus.publishAll(order);
    return order.toDto();
  }

  async _resolveAddress({ address, addressId, actor, email, phone, name }) {
    if (addressId) {
      if (!actor) throw DomainError.unauthorized('Sign in to use a saved address');
      const saved = await this.addressRepo.findById(addressId);
      if (!saved || saved.userId !== actor.id) throw DomainError.notFound('Address not found');
      return new ShippingAddress({
        name: name ?? actor.name,
        phone: saved.phone ?? phone,
        line1: saved.line1,
        line2: saved.line2,
        city: saved.city,
        state: saved.state,
        pincode: saved.pincode,
        label: saved.label,
      });
    }
    if (!address) throw DomainError.validation('Shipping address is required');
    if (!email && !phone && !actor) throw DomainError.validation('Email or phone is required for order updates');
    return new ShippingAddress({ name: name ?? actor?.name ?? address.name, ...address, phone: address.phone ?? phone });
  }
}

/** ListOrders - the signed-in customer's order history (paged). */
export class ListOrders extends UseCase {
  constructor({ orderRepo }) {
    super();
    this.orderRepo = orderRepo;
  }

  async execute({ actor, page = 1, limit = 10 }) {
    if (!actor) throw DomainError.unauthorized();
    const { items, total } = await this.orderRepo.listByUser(actor.id, { page: Number(page), limit: Number(limit) });
    return { items: items.map((o) => o.toSummaryDto()), total, page: Number(page), limit: Number(limit) };
  }
}

/** GetOrder - full order detail (owner only). */
export class GetOrder extends UseCase {
  constructor({ orderRepo }) {
    super();
    this.orderRepo = orderRepo;
  }

  async execute({ id, actor }) {
    const order = await this.orderRepo.findById(id);
    if (!order) throw DomainError.notFound('Order not found');
    // Owner OR a guest checkout (no user attached) made with the caller's email.
    const owns = Boolean(actor) && (order.userId === actor.id || (!order.userId && order.email && order.email === actor.email));
    if (!owns) throw DomainError.forbidden('Not your order');
    return order.toDto();
  }
}

/**
 * TrackOrder - public tracking by order number + email/phone (guest checkout
 * friendly: no token needed, but two factors must match).
 */
export class TrackOrder extends UseCase {
  constructor({ orderRepo }) {
    super();
    this.orderRepo = orderRepo;
  }

  async execute({ orderNumber, email, phone }) {
    const order = await this.orderRepo.findByOrderNumber(String(orderNumber ?? '').trim().toUpperCase());
    if (!order) throw DomainError.notFound('No order found with that order number');
    const matches =
      (email && order.email && order.email.toLowerCase() === String(email).toLowerCase()) ||
      (phone && order.phone === String(phone));
    if (!matches) throw DomainError.forbidden('Order number does not match the email/phone on the order');

    return {
      orderNumber: order.orderNumber,
      status: order.status.value,
      paymentMethod: order.paymentMethod.value,
      total: order.total.paise,
      items: order.items.map((i) => i.toDto()),
      events: order.events.map((e) => e.toDto()),
      address: order.address.toDto(),
      createdAt: order.createdAt.toISOString(),
    };
  }
}

/** UpdateOrderStatus - fulfilment transition (guarded by the admin middleware). */
export class UpdateOrderStatus extends UseCase {
  constructor({ orderRepo, eventBus }) {
    super();
    this.orderRepo = orderRepo;
    this.eventBus = eventBus;
  }

  async execute({ id, status, note }) {
    const order = await this.orderRepo.findById(id);
    if (!order) throw DomainError.notFound('Order not found');
    order.transitionTo(status, note);
    await this.orderRepo.save(order);
    this.eventBus.publishAll(order);
    return order.toDto();
  }
}
