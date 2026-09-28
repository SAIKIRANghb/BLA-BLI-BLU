import { ValueObject } from '../domain/value-object.js';
import { DomainError } from '../domain/domain-error.js';

/**
 * PageRequest / PageResult - reusable pagination value objects (DTO pattern).
 * Keeps `page`, `limit`, `sort` validation in one place for every query use case.
 */
export class PageRequest extends ValueObject {
  /**
   * @param {object} [opts]
   * @param {number} [opts.page]   1-based page number
   * @param {number} [opts.limit]  page size
   * @param {string} [opts.sort]   one of the allowed sort keys
   * @param {string} [opts.q]      free text search
   * @param {string[]} [opts.allowedSorts]
   */
  constructor({ page = 1, limit = 24, sort = 'featured', q = '', allowedSorts = ['featured'] } = {}) {
    super({ page: Number(page), limit: Number(limit), sort: String(sort), q: String(q ?? '').trim(), allowedSorts });
  }

  validate() {
    if (!Number.isInteger(this.page) || this.page < 1) throw DomainError.validation('page must be >= 1');
    if (!Number.isInteger(this.limit) || this.limit < 1 || this.limit > 100) {
      throw DomainError.validation('limit must be between 1 and 100');
    }
    if (!this.allowedSorts.includes(this.sort)) {
      throw DomainError.validation(`sort must be one of: ${this.allowedSorts.join(', ')}`);
    }
  }

  get offset() {
    return (this.page - 1) * this.limit;
  }
}

/** Generic paginated envelope returned by every list endpoint. */
export class PageResult {
  /**
   * @param {any[]} items
   * @param {number} total
   * @param {PageRequest} page
   */
  constructor(items, total, page) {
    this.items = items;
    this.page = page.page;
    this.limit = page.limit;
    this.total = total;
    this.totalPages = Math.max(1, Math.ceil(total / page.limit));
    this.hasNext = page.page < this.totalPages;
    this.hasPrev = page.page > 1;
  }
}
