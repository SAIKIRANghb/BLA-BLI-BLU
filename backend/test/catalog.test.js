import test from 'node:test';
import assert from 'node:assert/strict';
import { Product, ProductVariant, ProductNote, Collection, ProductReview } from '../src/modules/catalog/domain/index.js';
import { Slug } from '../src/shared/domain/identifiers.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

function makeProduct(props = {}) {
  return new Product({
    id: 'p-1',
    handle: 'Love Drunk 100ml',
    title: 'Love Drunk - 100ml',
    description: 'A long lasting unisex fragrance.',
    price: 70000,
    compareAtPrice: 100000,
    imageUrl: 'https://cdn.shopify.com/love-drunk.jpg',
    images: [{ url: 'https://cdn.shopify.com/love-drunk.jpg', alt: 'bottle' }],
    variants: [
      new ProductVariant({ id: 'v-1', title: '100ml', price: 70000, compareAtPrice: 100000 }),
      new ProductVariant({ id: 'v-2', title: '50ml', price: 39500, available: false }),
    ],
    notes: [
      new ProductNote({ id: 'n-1', type: 'head', name: 'Bergamot', position: 0 }),
      new ProductNote({ id: 'n-2', type: 'heart', name: 'Jasmine', position: 1 }),
      new ProductNote({ id: 'n-3', type: 'base', name: 'Musk', position: 2 }),
    ],
    collectionHandles: ['best-perfumes-for-men'],
    rating: 4.6,
    ratingCount: 128,
    ...props,
  });
}

const invalid = (re) => (e) => e instanceof DomainError && e.status === 422 && re.test(e.message);

test('a product keeps its handle slug-safe', () => {
  const p = makeProduct();
  assert.ok(p.handle instanceof Slug);
  assert.equal(p.handle.value, 'love-drunk-100ml');
  assert.equal(p.toCardDto().handle, 'love-drunk-100ml');
});

test('discountPercent reproduces the "% OFF" badge', () => {
  assert.equal(makeProduct().discountPercent(), 30);
  assert.equal(makeProduct({ compareAtPrice: null }).discountPercent(), 0);
  assert.equal(makeProduct({ compareAtPrice: 0 }).discountPercent(), 0);
  assert.equal(makeProduct({ price: 100000, compareAtPrice: 100000 }).discountPercent(), 0);
});

test('primaryVariant prefers an available one', () => {
  const p = makeProduct();
  assert.equal(p.primaryVariant().id, 'v-1');

  const soldOutFirst = makeProduct({
    variants: [
      new ProductVariant({ id: 'v-1', title: '100ml', price: 70000, available: false }),
      new ProductVariant({ id: 'v-2', title: '50ml', price: 39500, available: false }),
      new ProductVariant({ id: 'v-3', title: '10ml', price: 9900 }),
    ],
  });
  assert.equal(soldOutFirst.primaryVariant().id, 'v-3');

  const allGone = makeProduct({
    variants: [new ProductVariant({ id: 'v-1', title: '100ml', price: 70000, available: false })],
  });
  assert.equal(allGone.primaryVariant().id, 'v-1'); // falls back to the first for display
});

test('product invariants are enforced by validate()', () => {
  // Aggregates are validated explicitly (repositories/use cases), not in the ctor.
  assert.doesNotThrow(() => makeProduct().validate());

  assert.throws(() => makeProduct({ title: ' ' }).validate(), invalid(/title is required/));
  assert.throws(() => makeProduct({ price: 0 }).validate(), invalid(/greater than zero/));
  assert.throws(() => makeProduct({ variants: [] }).validate(), invalid(/at least one variant/));
});

test('toCardDto is the compact grid/search payload', () => {
  const card = makeProduct().toCardDto();
  assert.equal(card.id, 'p-1');
  assert.equal(card.price, 70000);
  assert.equal(card.compareAtPrice, 100000);
  assert.equal(card.discountPercent, 30);
  assert.equal(card.imageUrl, 'https://cdn.shopify.com/love-drunk.jpg');
  assert.equal(card.available, true);
  assert.equal(card.rating, 4.6);
  assert.equal(card.ratingCount, 128);
  assert.ok(!('description' in card)); // detail-only fields stay out of the card
});

test('toDetailDto adds variants, images and notes grouped by type', () => {
  const detail = makeProduct().toDetailDto();
  assert.equal(detail.description, 'A long lasting unisex fragrance.');
  assert.equal(detail.variants.length, 2);
  assert.equal(detail.variants[0].price, 70000);
  assert.equal(detail.variants[0].compareAtPrice, 100000);
  assert.equal(detail.variants[1].available, false);
  assert.deepEqual(detail.images, [{ url: 'https://cdn.shopify.com/love-drunk.jpg', alt: 'bottle' }]);
  assert.deepEqual(detail.notes.head.map((n) => n.name), ['Bergamot']);
  assert.deepEqual(detail.notes.heart.map((n) => n.name), ['Jasmine']);
  assert.deepEqual(detail.notes.base.map((n) => n.name), ['Musk']);
  assert.deepEqual(detail.collections, ['best-perfumes-for-men']);
  assert.ok(typeof detail.createdAt === 'string');
});

test('membership checks are by handle', () => {
  const p = makeProduct();
  assert.ok(p.inCollection('best-perfumes-for-men'));
  assert.ok(!p.inCollection('new-arrivals'));
  assert.equal(p.notesByType('head').length, 1);
  assert.equal(p.notesByType('heart').length, 1);
});

test('a Collection carries its image through toDto (Shop rail regression)', () => {
  const c = new Collection({
    id: 'col-1',
    handle: 'Best Perfumes For Men',
    title: 'Best Perfumes For Men',
    description: 'Our most gifted picks.',
    imageUrl: 'https://blabliblulife.com/cdn/shop/collection.jpg',
    position: 3,
  });

  const dto = c.toDto();
  assert.equal(dto.handle, 'best-perfumes-for-men');
  assert.equal(dto.title, 'Best Perfumes For Men');
  // Regression: the pg row mapper used to drop this, leaving the Shop rail blank.
  assert.equal(dto.imageUrl, 'https://blabliblulife.com/cdn/shop/collection.jpg');
  assert.equal(dto.position, 3);
  assert.ok(!('productCount' in dto)); // optional - only present when asked
  assert.equal(c.toDto(12).productCount, 12);
});

test('a review needs a 1..5 rating and serialises an ISO date', () => {
  const r = new ProductReview({
    id: 'r-1',
    productId: 'p-1',
    author: 'Aarav Sharma',
    rating: 5,
    title: 'Incredible longevity',
    body: 'Still going strong at dinner.',
    createdAt: new Date('2026-01-02T10:30:00.000Z'),
  });
  assert.doesNotThrow(() => r.validate());

  const dto = r.toDto();
  assert.equal(dto.rating, 5);
  assert.equal(dto.author, 'Aarav Sharma');
  assert.equal(dto.createdAt, '2026-01-02T10:30:00.000Z');
  assert.ok(!('productId' in dto));

  const tooHigh = new ProductReview({ id: 'r-2', productId: 'p-1', author: 'x', rating: 6, createdAt: new Date() });
  assert.throws(() => tooHigh.validate(), invalid(/between 1 and 5/));
  const tooLow = new ProductReview({ id: 'r-3', productId: 'p-1', author: 'x', rating: 0, createdAt: new Date() });
  assert.throws(() => tooLow.validate(), invalid(/between 1 and 5/));
});

test('a variant DTO exposes price and compare-at in paise', () => {
  const full = new ProductVariant({ id: 'v-1', title: '100ml', price: 70000, compareAtPrice: 100000, sku: 'BBB-100' });
  assert.equal(full.toDto().price, 70000);
  assert.equal(full.toDto().compareAtPrice, 100000);
  assert.equal(full.toDto().sku, 'BBB-100');
  assert.equal(full.toDto().available, true);

  const bare = new ProductVariant({ id: 'v-2', title: '50ml', price: 39500 });
  assert.equal(bare.toDto().compareAtPrice, null);
  assert.equal(bare.toDto().sku, null);
});
