import { ValueObject } from '../domain/value-object.js';
import { DomainError } from '../domain/domain-error.js';

/** Email - validated contact identifier value object. */
export class Email extends ValueObject {
  constructor(value) {
    super({ value: String(value ?? '').trim().toLowerCase() });
  }

  validate() {
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
    if (!re.test(this.value)) throw DomainError.validation('Please provide a valid email address');
  }
}

/** Slug - url safe identifier used by products and collections. */
export class Slug extends ValueObject {
  constructor(value) {
    const slug = String(value ?? '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
    super({ value: slug });
  }

  validate() {
    if (this.value.length < 2) throw DomainError.validation('Slug must be at least 2 characters');
  }
}
