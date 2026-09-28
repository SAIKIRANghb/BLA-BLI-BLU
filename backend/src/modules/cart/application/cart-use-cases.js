import { randomUUID } from 'node:crypto';
import { UseCase } from '../../../shared/application/use-case.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Money } from '../../../shared/domain/money.js';
import { PricingService, StandardPricingStrategy } from '../../../shared/domain/pricing.js';
import { env } from '../../../config/env.js';
import { Cart } from '../domain/index.js';

/**
 * Cart use cases (application layer).
 *
 * Shared collaborators are constructor injected:
 *   - cartRepo    (CartRepository)
 *   - productRepo (catalog read model)
 *   - couponRepo  (promotion port)
 *   - pricing     (PricingService domain service)
 */
export class CartUseCases {
  constructor({ cartRepo, productRepo, couponRepo }) {
    this.cartRepo = cartRepo;
    this.productRepo = productRepo;
    this.couponRepo = couponRepo;
    this.pricing = new PricingService(
      new StandardPricingStrategy({
        freeShippingThresholdPaise: env.commerce.freeShippingThresholdPaise,
        shippingFeePaise: env.commerce.shippingFeePaise,
      }),
    );
  }

  /** Access rule: anonymous carts are open to whoever holds the (unguessable) id. */
  _assertAccess(cart, actor) {
    if (!cart) throw DomainError.notFound('Cart not found');
    if (cart.userId && cart.userId !== actor?.id) throw DomainError.forbidden('This cart belongs to another account');
    return cart;
  }

  async _resolveCoupon(code) {
    if (!code) return null;
    const coupon = await this.couponRepo.findActive(code);
    if (!coupon) throw DomainError.validation('Invalid or expired coupon code');
    return coupon;
  }

  /** Totals are always computed by the domain pricing service, never in SQL. */
  async _withTotals(cart) {
    const coupon = await this._resolveCoupon(cart.couponCode).catch((err) => {
      if (err instanceof DomainError) return null;
      throw err;
    });
    const totals = this.pricing.price({ subtotal: cart.subtotal, coupon });
    return cart.toDto(totals.toDto());
  }

  /** CreateCart - mints an empty guest cart. */
  async createCart({ actor } = {}) {
    const cart = Cart.create(randomUUID(), actor?.id ?? null);
    await this.cartRepo.save(cart);
    return this._withTotals(cart);
  }

  /** GetCart - by id, or the caller's own cart when authenticated and no id given. */
  async getCart({ cartId, actor } = {}) {
    let cart = null;
    if (cartId) cart = await this.cartRepo.findById(cartId);
    else if (actor) cart = await this.cartRepo.findByUser(actor.id);
    if (!cart) return this.createCart({ actor });
    this._assertAccess(cart, actor);
    return this._withTotals(cart);
  }

  async addItem({ cartId, productId, variantId = null, qty = 1, actor } = {}) {
    const cart = this._assertAccess(await this.cartRepo.findById(cartId), actor);
    const product = await this.productRepo.findById(productId);
    if (!product) throw DomainError.notFound('Product not found');
    const variant = variantId ? product.variants.find((v) => v.id === variantId) : product.primaryVariant();

    const result = cart.addLine(product, variant ?? product.primaryVariant(), qty);
    if (result.isFail()) throw result.error;

    await this.cartRepo.save(cart);
    return this._withTotals(cart);
  }

  async updateItem({ cartId, lineId, qty, actor }) {
    const cart = this._assertAccess(await this.cartRepo.findById(cartId), actor);
    const result = cart.changeQuantity(lineId, qty);
    if (result.isFail()) throw result.error;
    await this.cartRepo.save(cart);
    return this._withTotals(cart);
  }

  async removeItem({ cartId, lineId, actor }) {
    const cart = this._assertAccess(await this.cartRepo.findById(cartId), actor);
    const result = cart.removeLine(lineId);
    if (result.isFail()) throw result.error;
    await this.cartRepo.save(cart);
    return this._withTotals(cart);
  }

  async clearCart({ cartId, actor }) {
    const cart = this._assertAccess(await this.cartRepo.findById(cartId), actor);
    cart.clear();
    await this.cartRepo.save(cart);
    return this._withTotals(cart);
  }

  async setCoupon({ cartId, code, actor }) {
    const cart = this._assertAccess(await this.cartRepo.findById(cartId), actor);
    await this._resolveCoupon(code || null);
    cart.applyCoupon(code || null);
    await this.cartRepo.save(cart);
    return this._withTotals(cart);
  }

  /** QuoteTotals - price a coupon against a subtotal without persisting (checkout preview). */
  async quote({ subtotalPaise, code, actor } = {}) {
    const coupon = await this._resolveCoupon(code || null);
    const totals = this.pricing.price({ subtotal: new Money(subtotalPaise ?? 0), coupon });
    return totals.toDto();
  }

  /**
   * MergeGuestCart - guest cart is folded into the signed-in user's cart and
   * then attached to the account (cart merge strategy on login).
   */
  async mergeCart({ cartId, actor }) {
    if (!actor) throw DomainError.unauthorized('Sign in to sync your cart');
    const guestCart = this._assertAccess(await this.cartRepo.findById(cartId), actor);
    const userCart = (await this.cartRepo.findByUser(actor.id)) ?? Cart.create(randomUUID(), actor.id);

    if (guestCart.id !== userCart.id) {
      userCart.mergeFrom(guestCart);
      userCart.attachTo(actor.id);
      await this.cartRepo.save(userCart);
      await this.cartRepo.delete(guestCart.id);
      return this._withTotals(userCart);
    }
    guestCart.attachTo(actor.id);
    await this.cartRepo.save(guestCart);
    return this._withTotals(guestCart);
  }
}
