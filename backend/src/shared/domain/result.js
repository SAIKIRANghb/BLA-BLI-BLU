import { DomainError } from './domain-error.js';

/**
 * Result<T> - railway oriented programming (Either/Ok-Fail) for the domain layer.
 *
 * Use it instead of throwing for *expected* failures (out of stock, invalid
 * coupon, ...) so call sites are forced to handle both branches.
 *
 *   const r = cart.addLine(product, 2);
 *   if (r.isFail()) return res.status(r.error.status).json(...)
 */
export class Result {
  constructor(ok, value, error) {
    this._ok = ok;
    this._value = value;
    this._error = error;
    Object.freeze(this);
  }

  static ok(value = undefined) {
    return new Result(true, value, undefined);
  }

  static fail(error) {
    const err = error instanceof DomainError ? error : new DomainError(String(error?.message ?? error));
    return new Result(false, undefined, err);
  }

  /** @returns {boolean} whether the operation succeeded */
  isOk() {
    return this._ok;
  }

  /** @returns {boolean} whether the operation failed */
  isFail() {
    return !this._ok;
  }

  get value() {
    if (!this._ok) throw new Error('Result has no value (it is a failure)');
    return this._value;
  }

  get error() {
    if (this._ok) throw new Error('Result has no error (it succeeded)');
    return this._error;
  }

  /** @param {(v:any)=>Result} fn */
  chain(fn) {
    return this._ok ? fn(this._value) : this;
  }

  /** @param {(v:any)=>any} fn */
  map(fn) {
    return this._ok ? Result.ok(fn(this._value)) : this;
  }

  unwrapOr(fallback) {
    return this._ok ? this._value : fallback;
  }
}
