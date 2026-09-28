import { AggregateRoot, Entity } from '../../../shared/domain/entity.js';
import { ValueObject } from '../../../shared/domain/value-object.js';
import { Money } from '../../../shared/domain/money.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Result } from '../../../shared/domain/result.js';
import { Repository } from '../../../shared/domain/repository.js';

/** Quantity - constrained value object (1..10 per line, storefront rule). */
export class Quantity extends ValueObject {
  constructor(value) {
    super({ value: Number(value) });
  }

  validate() {
    if (!Number.isInteger(this.value) || this.value < 1) throw DomainError.validation('Quantity must be a positive integer');
    if (this.value > 10) throw DomainError.validation('You can add at most 10 units of an item');
  }
}

/**
 * CartLine - child entity of the cart aggregate. Holds a price snapshot taken
 * when the line was added (the pricing service re-reads live prices at checkout).
 */
export class CartLine extends Entity {
  constructor({ id, productId, handle, title, imageUrl, variantId, variantTitle, unitPrice, quantity, available = true }) {
    super(id);
    this.productId = productId;
    this.handle = handle;
    this.title = title;
    this.imageUrl = imageUrl;
    this.variantId = variantId ?? null;
    this.variantTitle = variantTitle ?? null;
    this.unitPrice = unitPrice instanceof Money ? unitPrice : new Money(unitPrice ?? 0);
    this.quantity = quantity instanceof Quantity ? quantity : new Quantity(quantity);
    this.available = available;
  }

  get lineTotal() {
    return this.unitPrice.times(this.quantity.value);
  }

  withQuantity(quantity) {
    return new CartLine({ ...this, id: this.id, quantity });
  }

  /** Same line, fresh identity (used when a line moves between carts). */
  withNewId() {
    const id = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
    return new CartLine({ ...this, id });
  }

  toDto() {
    return {
      id: this.id,
      productId: this.productId,
      handle: this.handle,
      title: this.title,
      imageUrl: this.imageUrl,
      variantId: this.variantId,
      variantTitle: this.variantTitle,
      unitPrice: this.unitPrice.paise,
      quantity: this.quantity.value,
      lineTotal: this.lineTotal.paise,
      available: this.available,
    };
  }
}

/**
 * Cart - aggregate root enforcing cart invariants:
 *  - one line per product/variant
 *  - quantity bounds (Quantity VO)
 *  - max 30 distinct lines
 *
 * Mutations return `Result` (railway oriented) instead of throwing so the
 * application layer can decide HTTP semantics.
 */
export class Cart extends AggregateRoot {
  constructor({ id, userId = null, lines = [], couponCode = null, createdAt, updatedAt }) {
    super(id, { createdAt });
    this.userId = userId;
    /** @type {CartLine[]} */
    this.lines = lines;
    this.couponCode = couponCode;
    this.updatedAt = updatedAt ? new Date(updatedAt) : this.createdAt;
  }

  static create(id, userId = null) {
    return new Cart({ id, userId });
  }

  static MAX_LINES = 30;

  get isEmpty() {
    return this.lines.length === 0;
  }

  get itemCount() {
    return this.lines.reduce((sum, line) => sum + line.quantity.value, 0);
  }

  get subtotal() {
    return this.lines.reduce((sum, line) => sum.plus(line.lineTotal), Money.zero());
  }

  /** @param {import('../../catalog/domain/index.js').Product} product */
  addLine(product, variant, quantity) {
    if (!product.available || !variant?.available) {
      return Result.fail(new DomainError('This item is currently out of stock', { code: 'OUT_OF_STOCK', status: 409 }));
    }
    const qty = new Quantity(quantity);
    const key = (l) => `${l.productId}:${l.variantId ?? ''}`;
    const existing = this.lines.find((l) => key(l) === `${product.id}:${variant?.id ?? ''}`);

    if (existing) {
      const merged = new Quantity(Math.min(10, existing.quantity.value + qty.value));
      this._replaceLine(existing.withQuantity(merged));
      return Result.ok(this);
    }
    if (this.lines.length >= Cart.MAX_LINES) {
      return Result.fail(
        new DomainError(`A cart can hold at most ${Cart.MAX_LINES} different items`, { code: 'CART_FULL', status: 409 }),
      );
    }
    this.lines.push(
      new CartLine({
        id: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
        productId: product.id,
        handle: product.handle.value,
        title: product.title,
        imageUrl: product.imageUrl,
        variantId: variant?.id ?? null,
        variantTitle: variant?.title ?? null,
        unitPrice: variant?.price ?? product.price,
        quantity: qty,
        available: product.available,
      }),
    );
    this._touch();
    return Result.ok(this);
  }

  changeQuantity(lineId, quantity) {
    const line = this.lines.find((l) => l.id === lineId);
    if (!line) return Result.fail(DomainError.notFound('Cart item not found'));
    // `PATCH .../items/:lineId { qty: 0 }` is documented as "remove this line"
    // (the route schema allows 0), so the zero check has to run *before*
    // constructing a Quantity - that VO rejects 0 by design and would turn a
    // removal into a 422.
    if (Number(quantity) === 0) return this.removeLine(lineId);
    const qty = new Quantity(quantity);
    this._replaceLine(line.withQuantity(qty));
    return Result.ok(this);
  }

  removeLine(lineId) {
    const before = this.lines.length;
    this.lines = this.lines.filter((l) => l.id !== lineId);
    if (this.lines.length === before) return Result.fail(DomainError.notFound('Cart item not found'));
    this._touch();
    return Result.ok(this);
  }

  applyCoupon(code) {
    this.couponCode = code ? String(code).toUpperCase().trim() : null;
    this._touch();
    return Result.ok(this);
  }

  clear() {
    this.lines = [];
    this.couponCode = null;
    this._touch();
  }

  attachTo(userId) {
    this.userId = userId;
    this._touch();
  }

  /** Merges `other` into this cart (guest cart -> user cart on login). */
  mergeFrom(other) {
    for (const line of other.lines) {
      const existing = this.lines.find((l) => l.productId === line.productId && l.variantId === line.variantId);
      if (existing) {
        const merged = new Quantity(Math.min(10, existing.quantity.value + line.quantity.value));
        this._replaceLine(existing.withQuantity(merged));
      } else if (this.lines.length < Cart.MAX_LINES) {
        // re-key the line so both carts can be persisted before the donor is deleted
        this.lines.push(line.withNewId());
      }
    }
    other.clear();
    this._touch();
    return this;
  }

  _replaceLine(next) {
    this.lines = this.lines.map((l) => (l.id === next.id ? next : l));
    this._touch();
  }

  _touch() {
    this.updatedAt = new Date();
  }

  toDto(totals = undefined) {
    return {
      id: this.id,
      userId: this.userId,
      items: this.lines.map((l) => l.toDto()),
      itemCount: this.itemCount,
      subtotal: this.subtotal.paise,
      couponCode: this.couponCode,
      ...(totals ? { totals } : {}),
      updatedAt: this.updatedAt.toISOString(),
    };
  }
}

export class CartRepository extends Repository {
  /** @returns {Promise<Cart|null>} */
  async findById(_id) {
    throw new Error('Not implemented');
  }

  /** @param {string} _userId @returns {Promise<Cart|null>} */
  async findByUser(_userId) {
    throw new Error('Not implemented');
  }

  async save(_cart) {
    throw new Error('Not implemented');
  }
}
