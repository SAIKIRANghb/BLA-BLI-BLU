import { AggregateRoot, Entity } from '../../../shared/domain/entity.js';
import { ValueObject } from '../../../shared/domain/value-object.js';
import { Money } from '../../../shared/domain/money.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Repository } from '../../../shared/domain/repository.js';

/**
 * OrderStatus - value object implementing a small state machine so an order
 * can only move along the shipping lifecycle.
 */
export class OrderStatus extends ValueObject {
  static FLOW = ['placed', 'confirmed', 'packed', 'shipped', 'delivered'];
  static TERMINAL = ['delivered', 'cancelled'];

  constructor(value) {
    super({ value: String(value ?? 'placed') });
  }

  validate() {
    const allowed = [...OrderStatus.FLOW, 'cancelled'];
    if (!allowed.includes(this.value)) throw DomainError.validation(`Unknown order status: ${this.value}`);
  }

  isTerminal() {
    return OrderStatus.TERMINAL.includes(this.value);
  }

  /** @param {OrderStatus} next */
  canTransitionTo(next) {
    if (this.value === next.value) return true;
    if (this.isTerminal()) return false;
    const from = OrderStatus.FLOW.indexOf(this.value);
    const to = OrderStatus.FLOW.indexOf(next.value);
    if (next.value === 'cancelled') return from < OrderStatus.FLOW.indexOf('delivered');
    return to === from + 1;
  }

  advance() {
    const index = OrderStatus.FLOW.indexOf(this.value);
    if (index < 0 || index >= OrderStatus.FLOW.length - 1) return this;
    return new OrderStatus(OrderStatus.FLOW[index + 1]);
  }
}

/** PaymentMethod - value object; 'cod' handled locally, others are mocked gateways. */
export class PaymentMethod extends ValueObject {
  constructor(value) {
    super({ value: String(value ?? 'cod').toLowerCase() });
  }

  validate() {
    if (!['cod', 'upi', 'card'].includes(this.value)) throw DomainError.validation('Unsupported payment method');
  }
}

/** ShippingAddress - immutable snapshot stored with the order. */
export class ShippingAddress extends ValueObject {
  constructor({ name, phone, line1, line2 = '', city, state, pincode, label = 'Home' }) {
    super({ name, phone, line1, line2, city, state, pincode, label });
  }

  validate() {
    if (!this.name || !this.line1 || !this.city || !this.state) throw DomainError.validation('Incomplete shipping address');
    if (!/^\d{6}$/.test(String(this.pincode))) throw DomainError.validation('Pincode must be 6 digits');
    if (!/^\d{10}$/.test(String(this.phone))) throw DomainError.validation('Phone must be 10 digits');
  }

  toDto() {
    return { ...this };
  }

  singleLine() {
    return [this.line1, this.line2, this.city, this.state, this.pincode].filter(Boolean).join(', ');
  }
}

/** OrderItem - immutable line captured at purchase time. */
export class OrderItem extends Entity {
  constructor({ id, productId, handle, title, imageUrl, variantTitle, unitPrice, quantity }) {
    super(id);
    this.productId = productId;
    this.handle = handle;
    this.title = title;
    this.imageUrl = imageUrl;
    this.variantTitle = variantTitle ?? null;
    this.unitPrice = unitPrice instanceof Money ? unitPrice : new Money(unitPrice);
    this.quantity = Number(quantity);
  }

  get total() {
    return this.unitPrice.times(this.quantity);
  }

  toDto() {
    return {
      id: this.id,
      productId: this.productId,
      handle: this.handle,
      title: this.title,
      imageUrl: this.imageUrl,
      variantTitle: this.variantTitle,
      unitPrice: this.unitPrice.paise,
      quantity: this.quantity,
      total: this.total.paise,
    };
  }
}

/** OrderEvent - timeline entry (Observer-style audit trail). */
export class OrderEvent extends Entity {
  constructor({ id, status, note, occurredAt, position = 0 }) {
    super(id, { createdAt: occurredAt });
    this.status = status;
    this.note = note;
    this.position = position;
  }

  toDto() {
    return { status: this.status, note: this.note, at: this.createdAt.toISOString(), position: this.position };
  }
}

/**
 * Order - aggregate root of the Ordering bounded context.
 * Money math is delegated to the shared PricingService; this aggregate only
 * enforces lifecycle and integrity invariants.
 */
export class Order extends AggregateRoot {
  constructor(props) {
    super(props.id, props);
    this.orderNumber = props.orderNumber;
    this.userId = props.userId ?? null;
    this.email = props.email;
    this.phone = props.phone;
    this.status = props.status instanceof OrderStatus ? props.status : new OrderStatus(props.status ?? 'placed');
    this.paymentMethod = props.paymentMethod instanceof PaymentMethod ? props.paymentMethod : new PaymentMethod(props.paymentMethod);
    this.paymentStatus = props.paymentStatus ?? 'pending';
    this.subtotal = toMoney(props.subtotal);
    this.discount = toMoney(props.discount);
    this.shipping = toMoney(props.shipping);
    this.total = toMoney(props.total);
    this.couponCode = props.couponCode ?? null;
    this.address = props.address instanceof ShippingAddress ? props.address : new ShippingAddress(props.address ?? {});
    /** @type {OrderItem[]} */
    this.items = props.items ?? [];
    /** @type {OrderEvent[]} */
    this.events = props.events ?? [];
    this.updatedAt = props.updatedAt ? new Date(props.updatedAt) : this.createdAt;
  }

  validate() {
    if (this.items.length === 0) throw DomainError.validation('An order needs at least one item');
    if (this.total.isGreaterThan(Money.zero()) === false && this.subtotal.paise === 0) {
      throw DomainError.validation('Order total cannot be empty');
    }
  }

  static generateOrderNumber() {
    const now = new Date();
    const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
    const suffix = Math.floor(1000 + Math.random() * 9000);
    return `BBL-${stamp}-${suffix}`;
  }

  /** Records the initial timeline entry and domain event. */
  markPlaced() {
    this._addEvent('placed', 'Order placed successfully');
    this.record('order.placed', {
      orderId: this.id,
      orderNumber: this.orderNumber,
      email: this.email,
      total: this.total.paise,
      itemCount: this.items.length,
    });
    return this;
  }

  /** @param {string} status @param {string} [note] */
  transitionTo(status, note) {
    const next = new OrderStatus(status);
    if (!this.status.canTransitionTo(next)) {
      throw DomainError.conflict(`Cannot move order from "${this.status.value}" to "${next.value}"`);
    }
    this.status = next;
    this.paymentStatus = status === 'delivered' ? 'paid' : this.paymentStatus;
    this._addEvent(next.value, note ?? defaultNote(next.value));
    this.updatedAt = new Date();
    this.record('order.status_changed', { orderId: this.id, status: next.value, orderNumber: this.orderNumber });
    return this;
  }

  _addEvent(status, note) {
    const id = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${this.events.length}`;
    this.events.push(new OrderEvent({ id, status, note, occurredAt: new Date(), position: this.events.length }));
  }

  toDto() {
    return {
      id: this.id,
      orderNumber: this.orderNumber,
      status: this.status.value,
      paymentMethod: this.paymentMethod.value,
      paymentStatus: this.paymentStatus,
      subtotal: this.subtotal.paise,
      discount: this.discount.paise,
      shipping: this.shipping.paise,
      total: this.total.paise,
      couponCode: this.couponCode,
      address: this.address.toDto(),
      items: this.items.map((i) => i.toDto()),
      events: this.events.map((e) => e.toDto()),
      email: this.email,
      phone: this.phone,
      createdAt: this.createdAt.toISOString(),
      updatedAt: this.updatedAt.toISOString(),
    };
  }

  /** Compact projection for list screens. */
  toSummaryDto() {
    return {
      id: this.id,
      orderNumber: this.orderNumber,
      status: this.status.value,
      total: this.total.paise,
      itemCount: this.items.reduce((sum, i) => sum + i.quantity, 0),
      thumbnail: this.items[0]?.imageUrl ?? null,
      createdAt: this.createdAt.toISOString(),
    };
  }
}

function toMoney(value) {
  if (value instanceof Money) return value;
  if (value === undefined || value === null) return Money.zero();
  return new Money(value);
}

function defaultNote(status) {
  const notes = {
    confirmed: 'Order confirmed by our team',
    packed: 'Packed and ready to ship',
    shipped: 'Handed over to the courier',
    delivered: 'Delivered. Enjoy your fragrance!',
    cancelled: 'Order cancelled',
  };
  return notes[status] ?? 'Status updated';
}

export class OrderRepository extends Repository {
  /** @param {string} _userId @param {{page:number,limit:number}} [_page] */
  async listByUser(_userId, _page) {
    throw new Error('Not implemented');
  }

  /** @param {string} _orderNumber */
  async findByOrderNumber(_orderNumber) {
    throw new Error('Not implemented');
  }
}
