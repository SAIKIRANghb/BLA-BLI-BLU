import { ValueObject } from '../domain/value-object.js';
import { DomainError } from '../domain/domain-error.js';

/**
 * Money - value object storing amounts as integer paise (minor units) so
 * prices are never subject to floating point drift.
 *
 * Display helpers mirror the storefront: ₹695, ₹1,000, "30% OFF".
 */
export class Money extends ValueObject {
  /** @param {number} paise integer, >= 0 */
  constructor(paise) {
    super({ paise: Math.round(Number(paise)) });
  }

  /** @param {number} rupees */
  static fromRupees(rupees) {
    return new Money(Math.round(Number(rupees) * 100));
  }

  static zero() {
    return new Money(0);
  }

  validate() {
    if (!Number.isFinite(this.paise)) throw DomainError.validation('Money must be a finite number');
    if (this.paise < 0) throw DomainError.validation('Money cannot be negative');
  }

  get rupees() {
    return this.paise / 100;
  }

  /** @param {Money} other */
  plus(other) {
    return new Money(this.paise + other.paise);
  }

  /** @param {Money} other */
  minus(other) {
    return new Money(Math.max(0, this.paise - other.paise));
  }

  /** @param {number} factor */
  times(factor) {
    return new Money(Math.round(this.paise * factor));
  }

  /**
   * Percentage off against a list price, e.g. (695, 1000) => 30
   * @param {Money} listPrice
   */
  percentOff(listPrice) {
    if (listPrice.paise === 0) return 0;
    return Math.round(((listPrice.paise - this.paise) / listPrice.paise) * 100);
  }

  isGreaterThan(other) {
    return this.paise > other.paise;
  }

  format() {
    return `₹${this.rupees.toLocaleString('en-IN')}`;
  }
}
