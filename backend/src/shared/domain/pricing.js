import { ValueObject } from './value-object.js';
import { Money } from './money.js';
import { DomainError } from './domain-error.js';

/**
 * Coupon - validated value object describing a price adjustment.
 * @typedef {{code:string, type:'percent'|'flat'|'free_shipping', value:number,
 *            minOrderPaise?:number, maxDiscountPaise?:number}} CouponInput
 */
export class Coupon extends ValueObject {
  constructor({ code, type, value = 0, minOrderPaise = 0, maxDiscountPaise = null }) {
    super({
      code: String(code ?? '').toUpperCase().trim(),
      type,
      value: Number(value),
      minOrderPaise: Number(minOrderPaise ?? 0),
      maxDiscountPaise: maxDiscountPaise === null ? null : Number(maxDiscountPaise),
    });
  }

  validate() {
    if (!['percent', 'flat', 'free_shipping'].includes(this.type)) {
      throw DomainError.validation(`Unknown coupon type: ${this.type}`);
    }
    if (this.type === 'percent' && (this.value <= 0 || this.value > 100)) {
      throw DomainError.validation('Percent coupon must be between 1 and 100');
    }
  }

  /** @param {Money} subtotal */
  appliesTo(subtotal) {
    return subtotal.paise >= this.minOrderPaise;
  }
}

/**
 * CartTotals - immutable value object produced by the pricing service.
 */
export class CartTotals extends ValueObject {
  constructor({ subtotal, discount, shipping, total, couponCode, freeShipping, savings }) {
    super({
      subtotalPaise: subtotal,
      discountPaise: discount,
      shippingPaise: shipping,
      totalPaise: total,
      couponCode,
      freeShipping,
      savingsPaise: savings,
    });
  }

  toDto() {
    return {
      subtotal: this.subtotalPaise,
      discount: this.discountPaise,
      shipping: this.shippingPaise,
      total: this.totalPaise,
      couponCode: this.couponCode,
      freeShipping: this.freeShipping,
      savings: this.savingsPaise,
    };
  }
}

/**
 * PricingStrategy (Strategy pattern) - swappable promotion/shipping policy.
 * `StandardPricingStrategy` reproduces the storefront rules:
 *   - free shipping above ₹399, otherwise ₹49
 *   - percent/flat/free-shipping coupons
 */
export class PricingStrategy {
  /** @param {Coupon|null} _coupon @param {Money} _subtotal @returns {CartTotals} */
  price(_coupon, _subtotal) {
    throw new Error('Not implemented');
  }
}

export class StandardPricingStrategy extends PricingStrategy {
  /** @param {{freeShippingThresholdPaise:number, shippingFeePaise:number}} rules */
  constructor(rules) {
    super();
    this.freeShippingThresholdPaise = rules.freeShippingThresholdPaise;
    this.shippingFeePaise = rules.shippingFeePaise;
  }

  price(coupon, subtotal) {
    let discount = Money.zero();
    let freeShipping = subtotal.paise >= this.freeShippingThresholdPaise;

    if (coupon && coupon.appliesTo(subtotal)) {
      if (coupon.type === 'percent') {
        const raw = subtotal.times(coupon.value / 100);
        discount = coupon.maxDiscountPaise !== null ? Money.zero().plus(raw) : raw;
        if (coupon.maxDiscountPaise !== null && discount.paise > coupon.maxDiscountPaise) {
          discount = new Money(coupon.maxDiscountPaise);
        }
        if (discount.paise > subtotal.paise) discount = subtotal;
      } else if (coupon.type === 'flat') {
        discount = new Money(Math.min(coupon.value, subtotal.paise));
      } else if (coupon.type === 'free_shipping') {
        freeShipping = true;
      }
    }

    const shipping = subtotal.paise === 0 ? Money.zero() : freeShipping ? Money.zero() : new Money(this.shippingFeePaise);
    const payable = subtotal.minus(discount);
    const total = payable.plus(shipping);
    // "you saved" = coupon discount + waived shipping (only when it would have applied)
    const shippingSaving = freeShipping && subtotal.paise > 0 && subtotal.paise < this.freeShippingThresholdPaise ? this.shippingFeePaise : 0;
    const savings = new Money(discount.paise + shippingSaving);

    return new CartTotals({
      subtotal: subtotal.paise,
      discount: discount.paise,
      shipping: shipping.paise,
      total: total.paise,
      couponCode: coupon && coupon.appliesTo(subtotal) ? coupon.code : null,
      freeShipping,
      savings: savings.paise,
    });
  }
}

/**
 * PricingService - domain service (stateless) shared by the cart and ordering
 * contexts so both compute identical amounts.
 */
export class PricingService {
  /** @param {PricingStrategy} strategy */
  constructor(strategy) {
    this.strategy = strategy;
  }

  /**
   * @param {object} input
   * @param {Money} input.subtotal
   * @param {Coupon|null} [input.coupon]
   * @returns {CartTotals}
   */
  price({ subtotal, coupon = null }) {
    return this.strategy.price(coupon, subtotal);
  }
}
