/**
 * ValueObject (abstract)
 *
 * DDD building block: an immutable object defined entirely by its attributes.
 * Two value objects of the same type are equal when all their values are equal.
 *
 * Pattern: Immutable Object + Template Method (`validate` runs in the ctor).
 */
export class ValueObject {
  /** @param {object} props */
  constructor(props) {
    Object.freeze(Object.assign(this, props));
    this.validate();
  }

  /** Template method - subclasses throw DomainError when invariants break. */
  validate() {}

  /** @returns {boolean} structural equality with another value object */
  equals(other) {
    if (!(other instanceof ValueObject)) return false;
    if (other.constructor !== this.constructor) return false;
    const a = JSON.stringify(this);
    const b = JSON.stringify(other);
    return a === b;
  }
}
