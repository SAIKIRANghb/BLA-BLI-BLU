import { db } from '../../../config/database.js';
import { randomUUID } from 'node:crypto';
import { Money } from '../../../shared/domain/money.js';
import { Order, OrderItem, OrderEvent, OrderStatus, OrderRepository, ShippingAddress } from '../domain/index.js';

/**
 * PgOrderRepository - Infrastructure adapter for the Order aggregate.
 * Accepts either the pool (db) or a transaction facade (Unit of Work).
 */
export class PgOrderRepository extends OrderRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  _map(row) {
    if (!row) return null;
    return new Order({
      id: row.id,
      orderNumber: row.order_number,
      userId: row.user_id,
      email: row.email,
      phone: row.phone,
      status: new OrderStatus(row.status),
      paymentMethod: row.payment_method,
      paymentStatus: row.payment_status,
      subtotal: new Money(row.subtotal_paise),
      discount: new Money(row.discount_paise),
      shipping: new Money(row.shipping_paise),
      total: new Money(row.total_paise),
      couponCode: row.coupon_code,
      address: new ShippingAddress(row.address),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      items: (row.items ?? []).map(
        (i) => new OrderItem({ ...i, unitPrice: new Money(i.unitPrice), id: i.id ?? randomUUID() }),
      ),
      events: (row.events ?? []).map(
        (e) =>
          new OrderEvent({
            id: e.id ?? `${row.id}-${e.position}`,
            status: e.status,
            note: e.note,
            occurredAt: e.at ?? e.occurred_at,
            position: e.position,
          }),
      ),
    });
  }

  _hydrate(row) {
    return row;
  }

  async findById(id) {
    const row = await this.db.one('SELECT * FROM orders WHERE id = $1', [id]);
    if (!row) return null;
    row.items = await this.db.rows('SELECT * FROM order_items WHERE order_id = $1 ORDER BY position', [id]);
    row.events = await this.db.rows('SELECT * FROM order_events WHERE order_id = $1 ORDER BY position', [id]);
    return this._map(joinRow(row));
  }

  async findByOrderNumber(orderNumber) {
    const row = await this.db.one('SELECT * FROM orders WHERE order_number = $1', [orderNumber]);
    if (!row) return null;
    return this.findById(row.id);
  }

  async listByUser(userId, { page = 1, limit = 10 } = {}) {
    const countRow = await this.db.one('SELECT COUNT(*)::int AS count FROM orders WHERE user_id = $1', [userId]);
    const rows = await this.db.rows(
      `SELECT o.*,
         (SELECT json_agg(json_build_object(
            'id', i.id, 'productId', i.product_id, 'handle', i.handle, 'title', i.title,
            'imageUrl', i.image_url, 'variantTitle', i.variant_title,
            'unitPrice', i.unit_price_paise, 'quantity', i.quantity
          ) ORDER BY i.position) FROM order_items i WHERE i.order_id = o.id) AS items
       FROM orders o WHERE o.user_id = $1
       ORDER BY o.created_at DESC LIMIT $2 OFFSET $3`,
      [userId, limit, (page - 1) * limit],
    );
    return { items: rows.map((r) => this._map(joinRow(r))), total: countRow.count };
  }

  async save(order) {
    order.validate();
    await this.db.query(
      `INSERT INTO orders
         (id, order_number, user_id, email, phone, status, payment_method, payment_status,
          subtotal_paise, discount_paise, shipping_paise, total_paise, coupon_code, address,
          created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
       ON CONFLICT (id) DO UPDATE SET
         status = EXCLUDED.status, payment_status = EXCLUDED.payment_status,
         updated_at = EXCLUDED.updated_at`,
      [
        order.id,
        order.orderNumber,
        order.userId,
        order.email,
        order.phone,
        order.status.value,
        order.paymentMethod.value,
        order.paymentStatus,
        order.subtotal.paise,
        order.discount.paise,
        order.shipping.paise,
        order.total.paise,
        order.couponCode,
        JSON.stringify(order.address.toDto()),
        order.createdAt,
        order.updatedAt,
      ],
    );

  // items are immutable snapshots: written on create, refreshed on hydration
  await this.db.query('DELETE FROM order_items WHERE order_id = $1', [order.id]);
    if (order.items.length) {
      let position = 0;
      for (const item of order.items) {
        await this.db.query(
          `INSERT INTO order_items
             (id, order_id, product_id, handle, title, image_url, variant_title,
              unit_price_paise, quantity, total_paise, position)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
          [
            item.id,
            order.id,
            item.productId,
            item.handle,
            item.title,
            item.imageUrl,
            item.variantTitle,
            item.unitPrice.paise,
            item.quantity,
            item.total.paise,
            position++,
          ],
        );
      }
    }

    await this.db.query('DELETE FROM order_events WHERE order_id = $1', [order.id]);
    for (const event of order.events) {
      await this.db.query(
        'INSERT INTO order_events (id, order_id, status, note, position, occurred_at) VALUES ($1,$2,$3,$4,$5,$6)',
        [event.id, order.id, event.status, event.note, event.position, event.createdAt],
      );
    }
    return order;
  }

  async delete(id) {
    await this.db.query('DELETE FROM orders WHERE id = $1', [id]);
  }
}

/** Merges the raw items/events json columns into the shape `_map` expects. */
function joinRow(row) {
  if (!row) return row;
  return {
    ...row,
    items: (row.items ?? []).map((i) => ({
      id: i.id,
      productId: i.productId ?? i.product_id,
      handle: i.handle,
      title: i.title,
      imageUrl: i.imageUrl ?? i.image_url,
      variantTitle: i.variantTitle ?? i.variant_title,
      unitPrice: i.unitPrice ?? i.unit_price_paise,
      quantity: i.quantity,
    })),
    events: (row.events ?? []).map((e) => ({
      // keep the primary key so re-saving an hydrated order never invents a
      // synthetic (`<orderId>-<n>`) value that is not a valid uuid
      id: e.id ?? e.uuid ?? undefined,
      status: e.status,
      note: e.note,
      at: e.occurred_at ?? e.at,
      position: e.position,
    })),
  };
}
