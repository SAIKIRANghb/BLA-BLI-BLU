import { db } from '../../../config/database.js';
import { Cart, CartLine, CartRepository, Quantity } from '../domain/index.js';
import { Money } from '../../../shared/domain/money.js';
import { Coupon } from '../../../shared/domain/pricing.js';
import { DomainError } from '../../../shared/domain/domain-error.js';

/**
 * PgCartRepository - Infrastructure adapter for the Cart aggregate.
 * Persistence is line-oriented inside a single transaction (Unit of Work).
 */
export class PgCartRepository extends CartRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async _loadLines(cartId) {
    const rows = await this.db.rows('SELECT * FROM cart_items WHERE cart_id = $1 ORDER BY created_at ASC', [cartId]);
    return rows.map(
      (r) =>
        new CartLine({
          id: r.id,
          productId: r.product_id,
          handle: r.handle,
          title: r.title,
          imageUrl: r.image_url,
          variantId: r.variant_id,
          variantTitle: r.variant_title,
          unitPrice: new Money(r.unit_price_paise),
          quantity: new Quantity(r.quantity),
          available: r.available,
        }),
    );
  }

  async findById(id) {
    const row = await this.db.one('SELECT * FROM carts WHERE id = $1', [id]);
    if (!row) return null;
    return new Cart({
      id: row.id,
      userId: row.user_id,
      couponCode: row.coupon_code,
      lines: await this._loadLines(row.id),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    });
  }

  async findByUser(userId) {
    const row = await this.db.one('SELECT * FROM carts WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 1', [userId]);
    if (!row) return null;
    return new Cart({
      id: row.id,
      userId: row.user_id,
      couponCode: row.coupon_code,
      lines: await this._loadLines(row.id),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    });
  }

  async save(cart) {
    await this.db.transaction(async (client) => {
      await client.query(
        `INSERT INTO carts (id, user_id, coupon_code, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (id) DO UPDATE SET
           user_id = EXCLUDED.user_id, coupon_code = EXCLUDED.coupon_code, updated_at = EXCLUDED.updated_at`,
        [cart.id, cart.userId, cart.couponCode, cart.createdAt, cart.updatedAt],
      );
      await client.query('DELETE FROM cart_items WHERE cart_id = $1', [cart.id]);
      for (const line of cart.lines) {
        await client.query(
          `INSERT INTO cart_items
             (id, cart_id, product_id, variant_id, handle, title, image_url, variant_title,
              unit_price_paise, quantity, available, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
          [
            line.id,
            cart.id,
            line.productId,
            line.variantId,
            line.handle,
            line.title,
            line.imageUrl,
            line.variantTitle,
            line.unitPrice.paise,
            line.quantity.value,
            line.available,
            line.createdAt,
          ],
        );
      }
    });
    return cart;
  }

  async delete(id) {
    await this.db.query('DELETE FROM carts WHERE id = $1', [id]);
  }
}

/**
 * CouponRepository - read side for promotion codes (port implemented in the
 * ordering context, injected into cart/order use cases by the composition root).
 */
export class CouponRepository {
  /** @param {string} _code @returns {Promise<import('../../../shared/domain/pricing.js').Coupon|null>} */
  async findActive(_code) {
    throw new Error('Not implemented');
  }
}

/** PgCouponRepository */
export class PgCouponRepository extends CouponRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async findActive(code) {
    const row = await this.db.one(
      `SELECT * FROM coupons
       WHERE UPPER(code) = UPPER($1) AND active = TRUE
         AND (expires_at IS NULL OR expires_at > now())`,
      [code],
    );
    if (!row) return null;
    return new Coupon({
      code: row.code,
      type: row.coupon_type,
      value: row.value,
      minOrderPaise: row.min_order_paise,
      maxDiscountPaise: row.max_discount_paise,
    });
  }

  async listAll() {
    const rows = await this.db.rows('SELECT * FROM coupons ORDER BY code');
    return rows.map((r) => ({
      code: r.code,
      type: r.coupon_type,
      value: r.value,
      minOrderPaise: r.min_order_paise,
      maxDiscountPaise: r.max_discount_paise,
      expiresAt: r.expires_at,
    }));
  }
}

/** Thrown when a guest tries to mutate somebody else's cart. */
export function assertCartAccess(cart, actor) {
  if (!cart) throw DomainError.notFound('Cart not found');
  if (cart.userId && cart.userId !== actor?.id) throw DomainError.forbidden('This cart belongs to another account');
}
