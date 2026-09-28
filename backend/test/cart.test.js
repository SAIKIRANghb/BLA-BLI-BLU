import test from 'node:test';
import assert from 'node:assert/strict';
import { Cart, CartLine, Quantity } from '../src/modules/cart/domain/index.js';
import { Product, ProductVariant } from '../src/modules/catalog/domain/index.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

function makeProduct({ id = 'p-1', handle = 'love-drunk-100ml', price = 70000, available = true, variants } = {}) {
  return new Product({
    id,
    handle,
    title: 'Love Drunk - 100ml',
    price,
    imageUrl: 'https://cdn.shopify.com/love-drunk.jpg',
    available,
    variants:
      variants ??
      [
        new ProductVariant({ id: 'v-1', title: '100ml', price }),
        new ProductVariant({ id: 'v-2', title: '50ml', price: 39500 }),
      ],
  });
}

const invalidQuantity = (re) => (e) => e instanceof DomainError && e.status === 422 && re.test(e.message);

test('a new cart is empty and counts what it holds', () => {
  const cart = Cart.create('c-1', 'u-1');
  assert.equal(cart.isEmpty, true);
  assert.equal(cart.itemCount, 0);
  assert.equal(cart.subtotal.paise, 0);
  assert.equal(cart.userId, 'u-1');
  assert.equal(cart.couponCode, null);

  const product = makeProduct();
  assert.ok(cart.addLine(product, product.variants[0], 2).isOk());
  assert.equal(cart.isEmpty, false);
  assert.equal(cart.itemCount, 2);
  assert.equal(cart.subtotal.paise, 140000);
});

test('the same product+variant merges into one line, clamped at 10', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 6);
  cart.addLine(product, product.variants[0], 6);

  assert.equal(cart.lines.length, 1);
  assert.equal(cart.lines[0].quantity.value, 10); // 12 would break the storefront cap

  cart.addLine(product, product.variants[0], 1);
  assert.equal(cart.lines[0].quantity.value, 10); // stays capped
  assert.equal(cart.itemCount, 10);
});

test('distinct variants stay on distinct lines', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 1);
  cart.addLine(product, product.variants[1], 1);
  assert.equal(cart.lines.length, 2);
  assert.equal(cart.subtotal.paise, 70000 + 39500);
});

test('out-of-stock items are refused with a 409, not an exception', () => {
  const cart = Cart.create('c-1');

  const soldOut = cart.addLine(makeProduct({ available: false }), makeProduct().variants[0], 1);
  assert.ok(soldOut.isFail());
  assert.equal(soldOut.error.code, 'OUT_OF_STOCK');
  assert.equal(soldOut.error.status, 409);

  const product = makeProduct();
  const variantGone = cart.addLine(product, { id: 'v-x', available: false, price: 100 }, 1);
  assert.ok(variantGone.isFail());
  assert.equal(variantGone.error.status, 409);
  assert.equal(cart.lines.length, 0);
});

test('Quantity is a constrained value object (1..10, whole numbers)', () => {
  assert.equal(new Quantity(10).value, 10);
  assert.throws(() => new Quantity(0), invalidQuantity(/positive integer/));
  assert.throws(() => new Quantity(-2), invalidQuantity(/positive integer/));
  assert.throws(() => new Quantity(2.5), invalidQuantity(/positive integer/));
  assert.throws(() => new Quantity(11), invalidQuantity(/at most 10 units/));

  const cart = Cart.create('c-1');
  const product = makeProduct();
  assert.throws(() => cart.addLine(product, product.variants[0], 11), invalidQuantity(/at most 10 units/));
  assert.throws(() => cart.addLine(product, product.variants[0], 0), invalidQuantity(/positive integer/));
  assert.equal(cart.lines.length, 0);
});

test('changeQuantity rewrites the line in place', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 1);
  const lineId = cart.lines[0].id;

  assert.ok(cart.changeQuantity(lineId, 3).isOk());
  assert.equal(cart.lines.length, 1);
  assert.equal(cart.lines[0].id, lineId); // identity survives the state change
  assert.equal(cart.lines[0].quantity.value, 3);
  assert.equal(cart.subtotal.paise, 3 * 70000);
});

test('changeQuantity(0) removes the line (the PATCH {qty:0} contract)', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 2);
  const lineId = cart.lines[0].id;

  // Regression: the Quantity VO rejects 0, so this used to 422 instead of
  // removing the line - the route schema documents qty:0 as "remove".
  const result = cart.changeQuantity(lineId, 0);
  assert.ok(result.isOk());
  assert.equal(cart.lines.length, 0);
  assert.equal(cart.isEmpty, true);
});

test('changeQuantity on an unknown line fails with 404', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 1);

  const missing = cart.changeQuantity('nope-line-id', 2);
  assert.ok(missing.isFail());
  assert.equal(missing.error.code, 'NOT_FOUND');
  assert.equal(missing.error.status, 404);

  // unknown line loses even against qty 0 (id check runs first)
  assert.ok(cart.changeQuantity('nope-line-id', 0).isFail());

  // quantities outside the VO bounds still raise a validation error
  assert.throws(() => cart.changeQuantity(cart.lines[0].id, 11), invalidQuantity(/at most 10 units/));
});

test('removeLine drops exactly one line and 404s afterwards', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 1);
  cart.addLine(product, product.variants[1], 1);
  const first = cart.lines[0].id;

  assert.ok(cart.removeLine(first).isOk());
  assert.equal(cart.lines.length, 1);

  const again = cart.removeLine(first);
  assert.ok(again.isFail());
  assert.equal(again.error.status, 404);
});

test('a cart holds at most 30 distinct lines', () => {
  const cart = Cart.create('c-1');
  for (let i = 0; i < Cart.MAX_LINES; i += 1) {
    const product = makeProduct({ id: `p-${i}`, handle: `item-${i}` });
    assert.ok(cart.addLine(product, product.variants[0], 1).isOk());
  }
  assert.equal(cart.lines.length, Cart.MAX_LINES);

  const overflow = makeProduct({ id: 'p-31', handle: 'item-31' });
  const full = cart.addLine(overflow, overflow.variants[0], 1);
  assert.ok(full.isFail());
  assert.equal(full.error.code, 'CART_FULL');
  assert.equal(full.error.status, 409);
  assert.equal(cart.lines.length, Cart.MAX_LINES);
});

test('coupon codes are normalised, clear() resets the cart', () => {
  const cart = Cart.create('c-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 1);

  assert.ok(cart.applyCoupon('  welcome10 ').isOk());
  assert.equal(cart.couponCode, 'WELCOME10');
  assert.ok(cart.applyCoupon(null).isOk());
  assert.equal(cart.couponCode, null);

  cart.applyCoupon('FLAT100');
  cart.clear();
  assert.equal(cart.couponCode, null);
  assert.equal(cart.lines.length, 0);
  assert.equal(cart.isEmpty, true);
});

test('a guest cart merges into the user cart on sign-in', () => {
  const user = Cart.create('c-user', 'u-1');
  const guest = Cart.create('c-guest');
  const productA = makeProduct({ id: 'p-a' });
  const productB = makeProduct({ id: 'p-b', handle: 'habibi-100ml' });

  user.addLine(productA, productA.variants[0], 2);
  guest.addLine(productA, productA.variants[0], 6); // same line -> merges
  guest.addLine(productB, productB.variants[1], 1); // new line -> moves across
  guest.applyCoupon('WELCOME10');
  const donorIds = guest.lines.map((l) => l.id);

  user.mergeFrom(guest);

  assert.equal(user.lines.length, 2);
  assert.equal(user.lines.find((l) => l.productId === 'p-a').quantity.value, 8);
  const moved = user.lines.find((l) => l.productId === 'p-b');
  assert.equal(moved.quantity.value, 1);
  assert.ok(!donorIds.includes(moved.id)); // re-keyed so both carts can persist
  assert.equal(guest.isEmpty, true); // donor drained
  assert.equal(guest.couponCode, null);
  assert.equal(user.subtotal.paise, 8 * 70000 + 39500);
});

test('toDto serialises paise amounts and includes totals when given', () => {
  const cart = Cart.create('c-1', 'u-1');
  const product = makeProduct();
  cart.addLine(product, product.variants[0], 2);

  const bare = cart.toDto();
  assert.equal(bare.itemCount, 2);
  assert.equal(bare.subtotal, 140000);
  assert.equal(bare.items[0].unitPrice, 70000);
  assert.equal(bare.items[0].lineTotal, 140000);
  assert.equal(bare.items[0].handle, 'love-drunk-100ml');
  assert.ok(!('totals' in bare));
  assert.ok(!Number.isNaN(Date.parse(bare.updatedAt)));

  const priced = cart.toDto({ total: 140000 });
  assert.equal(priced.totals.total, 140000);
});

test('CartLine snapshots the price and computes its own total', () => {
  const line = new CartLine({
    id: 'l-1',
    productId: 'p-1',
    handle: 'love-drunk-100ml',
    title: 'Love Drunk - 100ml',
    imageUrl: 'https://cdn.shopify.com/love-drunk.jpg',
    unitPrice: 70000,
    quantity: 3,
  });
  assert.equal(line.lineTotal.paise, 210000);
  assert.equal(line.available, true);

  const bumped = line.withQuantity(5);
  assert.equal(bumped.quantity.value, 5);
  assert.equal(line.quantity.value, 3); // original untouched
  assert.equal(bumped.id, line.id); // identity preserved

  const rekeyed = line.withNewId();
  assert.notEqual(rekeyed.id, line.id);
});
