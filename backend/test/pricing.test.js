import test from 'node:test';
import assert from 'node:assert/strict';
import {
  Coupon,
  CartTotals,
  PricingStrategy,
  StandardPricingStrategy,
  PricingService,
} from '../src/shared/domain/pricing.js';
import { Money } from '../src/shared/domain/money.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

/** The storefront rules from env defaults (FREE_SHIPPING_THRESHOLD/SHIPPING_FEE). */
const rules = { freeShippingThresholdPaise: 39900, shippingFeePaise: 4900 };
const pricing = () => new PricingService(new StandardPricingStrategy(rules));

const coupon = (props) => new Coupon(props);

test('free shipping above ₹399, otherwise the ₹49 fee', () => {
  const above = pricing().price({ subtotal: new Money(50000) });
  assert.equal(above.freeShipping, true);
  assert.equal(above.shippingPaise, 0);
  assert.equal(above.totalPaise, 50000);

  const below = pricing().price({ subtotal: new Money(30000) });
  assert.equal(below.freeShipping, false);
  assert.equal(below.shippingPaise, 4900);
  assert.equal(below.totalPaise, 34900);
  assert.equal(below.savingsPaise, 0);

  // exactly on the threshold counts as free
  assert.equal(pricing().price({ subtotal: new Money(39900) }).shippingPaise, 0);
});

test('an empty cart prices to nothing at all', () => {
  const totals = pricing().price({ subtotal: Money.zero() });
  assert.equal(totals.subtotalPaise, 0);
  assert.equal(totals.shippingPaise, 0);
  assert.equal(totals.totalPaise, 0);
  assert.equal(totals.couponCode, null);
});

test('WELCOME10 (10%) discounts the subtotal', () => {
  const c = coupon({ code: ' welcome10 ', type: 'percent', value: 10 });
  assert.equal(c.code, 'WELCOME10'); // normalised on the way in

  const totals = pricing().price({ subtotal: new Money(30000), coupon: c });
  assert.equal(totals.discountPaise, 3000);
  assert.equal(totals.shippingPaise, 4900);
  assert.equal(totals.totalPaise, 31900);
  assert.equal(totals.couponCode, 'WELCOME10');
  assert.equal(totals.savingsPaise, 3000);
});

test('FLAT100 subtracts a flat amount, capped at the subtotal', () => {
  const c = coupon({ code: 'FLAT100', type: 'flat', value: 10000 });
  const totals = pricing().price({ subtotal: new Money(30000), coupon: c });
  assert.equal(totals.discountPaise, 10000);
  assert.equal(totals.totalPaise, 24900);

  // a coupon can never make the payable amount negative
  const greedy = pricing().price({ subtotal: new Money(50000), coupon: coupon({ code: 'HUGE', type: 'flat', value: 999999 }) });
  assert.equal(greedy.discountPaise, 50000);
  assert.equal(greedy.totalPaise, 0);
  assert.equal(greedy.savingsPaise, 50000);
});

test('a percent coupon honours maxDiscountPaise', () => {
  const c = coupon({ code: 'BIG', type: 'percent', value: 50, maxDiscountPaise: 2000 });
  const totals = pricing().price({ subtotal: new Money(30000), coupon: c });
  assert.equal(totals.discountPaise, 2000); // capped, not 15000
  assert.equal(totals.totalPaise, 32900);
});

test('FREESHIP waives the fee and counts it as a saving', () => {
  const c = coupon({ code: 'FREESHIP', type: 'free_shipping' });
  const totals = pricing().price({ subtotal: new Money(30000), coupon: c });
  assert.equal(totals.freeShipping, true);
  assert.equal(totals.shippingPaise, 0);
  assert.equal(totals.totalPaise, 30000);
  assert.equal(totals.savingsPaise, 4900); // the fee they did not pay
  assert.equal(totals.couponCode, 'FREESHIP');
});

test('a coupon below its minimum order is ignored entirely', () => {
  const c = coupon({ code: 'BIGSPENDER', type: 'percent', value: 10, minOrderPaise: 100000 });
  const totals = pricing().price({ subtotal: new Money(30000), coupon: c });
  assert.equal(totals.discountPaise, 0);
  assert.equal(totals.couponCode, null);
  assert.equal(totals.totalPaise, 34900);

  // ...and applies once the threshold is crossed
  const met = pricing().price({ subtotal: new Money(100000), coupon: c });
  assert.equal(met.discountPaise, 10000);
  assert.equal(met.couponCode, 'BIGSPENDER');
});

test('Coupon rejects nonsense definitions', () => {
  const invalid = (re) => (e) => e instanceof DomainError && e.status === 422 && re.test(e.message);
  assert.throws(() => coupon({ code: 'X', type: 'buy_one_get_one', value: 1 }), invalid(/Unknown coupon type/));
  assert.throws(() => coupon({ code: 'X', type: 'percent', value: 0 }), invalid(/between 1 and 100/));
  assert.throws(() => coupon({ code: 'X', type: 'percent', value: 101 }), invalid(/between 1 and 100/));
  assert.doesNotThrow(() => coupon({ code: 'X', type: 'percent', value: 100 }));
  assert.doesNotThrow(() => coupon({ code: 'X', type: 'flat', value: 0 }));
});

test('CartTotals DTO uses paise keys and nothing else', () => {
  const totals = pricing().price({ subtotal: new Money(50000) });
  assert.ok(totals instanceof CartTotals);
  assert.deepEqual(Object.keys(totals.toDto()).sort(), [
    'couponCode',
    'discount',
    'freeShipping',
    'savings',
    'shipping',
    'subtotal',
    'total',
  ]);
  assert.equal(totals.toDto().total, 50000);
});

test('the service is swappable behind the PricingStrategy interface', () => {
  const base = new PricingStrategy();
  assert.throws(() => base.price(null, Money.zero()), /Not implemented/);

  class FlatTenRuppeeStrategy extends PricingStrategy {
    price() {
      return new CartTotals({ subtotal: 100, discount: 0, shipping: 0, total: 100, couponCode: null, freeShipping: true, savings: 0 });
    }
  }
  const totals = new PricingService(new FlatTenRuppeeStrategy()).price({ subtotal: new Money(100) });
  assert.equal(totals.totalPaise, 100);
});
