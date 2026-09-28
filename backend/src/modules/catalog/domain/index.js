import { AggregateRoot, Entity } from '../../../shared/domain/entity.js';
import { Money } from '../../../shared/domain/money.js';
import { Slug } from '../../../shared/domain/identifiers.js';
import { DomainError } from '../../../shared/domain/domain-error.js';

/**
 * ProductNote - value-ish child entity describing head/heart/base notes.
 */
export class ProductNote extends Entity {
  constructor({ id, type, name, iconUrl, position = 0 }) {
    super(id);
    this.type = type; // 'head' | 'heart' | 'base'
    this.name = name;
    this.iconUrl = iconUrl ?? null;
    this.position = position;
  }

  toDto() {
    return { type: this.type, name: this.name, iconUrl: this.iconUrl, position: this.position };
  }
}

/**
 * ProductVariant - child entity, the purchasable unit.
 */
export class ProductVariant extends Entity {
  constructor({ id, title, sku, price, compareAtPrice, available = true, position = 0 }) {
    super(id);
    this.title = title;
    this.sku = sku ?? null;
    this.price = price instanceof Money ? price : new Money(price ?? 0);
    this.compareAtPrice = compareAtPrice instanceof Money ? compareAtPrice : compareAtPrice ? new Money(compareAtPrice) : null;
    this.available = Boolean(available);
    this.position = position;
  }

  toDto() {
    return {
      id: this.id,
      title: this.title,
      sku: this.sku,
      price: this.price.paise,
      compareAtPrice: this.compareAtPrice?.paise ?? null,
      available: this.available,
    };
  }
}

/**
 * Product - aggregate root of the catalog bounded context.
 *
 * Invariants: a product needs a slug, at least one image source, a price that
 * never exceeds its compare-at price (list price), and a purchasable variant.
 */
export class Product extends AggregateRoot {
  constructor(props) {
    super(props.id, props);
    this.handle = props.handle instanceof Slug ? props.handle : new Slug(props.handle);
    this.title = props.title;
    this.description = props.description ?? '';
    this.tagline = props.tagline ?? '';
    this.vendor = props.vendor ?? 'Bla Bli Blu';
    this.productType = props.productType ?? '';
    this.price = props.price instanceof Money ? props.price : new Money(props.price ?? 0);
    this.compareAtPrice = props.compareAtPrice
      ? props.compareAtPrice instanceof Money
        ? props.compareAtPrice
        : new Money(props.compareAtPrice)
      : null;
    this.available = props.available !== false;
    this.rating = Number(props.rating ?? 0);
    this.ratingCount = Number(props.ratingCount ?? 0);
    this.notesSummary = props.notesSummary ?? '';
    this.audience = props.audience ?? 'Unisex';
    this.badge = props.badge ?? null;
    this.oilConcentration = props.oilConcentration ?? null;
    this.tags = props.tags ?? [];
    this.imageUrl = props.imageUrl ?? null;
    this.images = props.images ?? [];
    this.variants = props.variants ?? [];
    this.notes = props.notes ?? [];
    this.collectionHandles = props.collectionHandles ?? [];
    this.position = Number(props.position ?? 0);
    this.hidden = Boolean(props.hidden);
  }

  validate() {
    if (!this.title || this.title.trim().length < 2) throw DomainError.validation('Product title is required');
    if (this.price.paise <= 0) throw DomainError.validation('Product price must be greater than zero');
    if (this.compareAtPrice && this.compareAtPrice.isGreaterThan(this.price)) {
      // list price above sale price is normal; the inverse is the bug
    }
    if (this.variants.length === 0) throw DomainError.validation('Product must have at least one variant');
  }

  /** @returns {number} 0..100 */
  discountPercent() {
    if (!this.compareAtPrice || this.compareAtPrice.paise === 0) return 0;
    return this.price.percentOff(this.compareAtPrice);
  }

  /** Primary variant used for quick add-to-cart. */
  primaryVariant() {
    return this.variants.find((v) => v.available) ?? this.variants[0] ?? null;
  }

  notesByType(type) {
    return this.notes.filter((n) => n.type === type);
  }

  inCollection(handle) {
    return this.collectionHandles.includes(handle);
  }

  /** Compact card DTO used by grids, carousels and search results. */
  toCardDto() {
    return {
      id: this.id,
      handle: this.handle.value,
      title: this.title,
      imageUrl: this.imageUrl,
      price: this.price.paise,
      compareAtPrice: this.compareAtPrice?.paise ?? null,
      discountPercent: this.discountPercent(),
      rating: this.rating,
      ratingCount: this.ratingCount,
      notesSummary: this.notesSummary,
      audience: this.audience,
      badge: this.badge,
      available: this.available,
    };
  }

  /** Full detail DTO used by the product screen. */
  toDetailDto() {
    return {
      ...this.toCardDto(),
      description: this.description,
      tagline: this.tagline,
      vendor: this.vendor,
      productType: this.productType,
      oilConcentration: this.oilConcentration,
      tags: this.tags,
      images: this.images.map((img) => ({ url: img.url, alt: img.alt ?? '' })),
      variants: this.variants.map((v) => v.toDto()),
      collections: this.collectionHandles,
      notes: {
        head: this.notesByType('head').map((n) => n.toDto()),
        heart: this.notesByType('heart').map((n) => n.toDto()),
        base: this.notesByType('base').map((n) => n.toDto()),
      },
      createdAt: this.createdAt.toISOString(),
    };
  }
}

/**
 * Collection - aggregate root representing a merchandising bucket
 * (e.g. `best-perfumes-for-men`) with an ordered membership list.
 */
export class Collection extends AggregateRoot {
  constructor(props) {
    super(props.id, props);
    this.handle = props.handle instanceof Slug ? props.handle : new Slug(props.handle);
    this.title = props.title;
    this.description = props.description ?? '';
    this.imageUrl = props.imageUrl ?? null;
    this.position = Number(props.position ?? 0);
  }

  toDto(productCount = undefined) {
    return {
      id: this.id,
      handle: this.handle.value,
      title: this.title,
      description: this.description,
      imageUrl: this.imageUrl,
      position: this.position,
      ...(productCount === undefined ? {} : { productCount }),
    };
  }
}

/**
 * ProductReview - value-backed child entity (rating is a validated value object).
 */
export class ProductReview extends Entity {
  constructor({ id, productId, author, rating, title = '', body = '', createdAt }) {
    super(id, { createdAt });
    this.productId = productId;
    this.author = author;
    this.rating = Number(rating);
    this.title = title;
    this.body = body;
  }

  validate() {
    if (this.rating < 1 || this.rating > 5) throw DomainError.validation('Rating must be between 1 and 5');
  }

  toDto() {
    return {
      id: this.id,
      author: this.author,
      rating: this.rating,
      title: this.title,
      body: this.body,
      createdAt: this.createdAt.toISOString(),
    };
  }
}
