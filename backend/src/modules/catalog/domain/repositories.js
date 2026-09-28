import { Repository } from '../../../shared/domain/repository.js';

/**
 * Repository contracts for the Catalog bounded context (Dependency Inversion).
 * Application services depend on these; pg adapters implement them.
 *
 * @typedef {object} ProductListQuery
 * @property {string} [collection] collection handle (null => all visible)
 * @property {string} [q]          free text
 * @property {string} [sort]       whitelist key (PageRequest validated)
 * @property {number} [page]
 * @property {number} [limit]
 * @property {boolean} [excludeHidden] drop SKUs tagged `hide-from-search` (search only)
 * @property {string[]} [audiences] optional audience filter
 */

export class ProductRepository extends Repository {
  /** @param {string} handle @returns {Promise<import('./index.js').Product|null>} */
  async findByHandle(_handle) {
    throw new Error('Not implemented');
  }

  /** @param {ProductListQuery} _query @returns {Promise<{items:import('./index.js').Product[], total:number}>} */
  async findAll(_query) {
    throw new Error('Not implemented');
  }

  /** @param {string[]} _handles @returns {Promise<import('./index.js').Product[]>} */
  async findManyByHandles(_handles) {
    throw new Error('Not implemented');
  }
}

export class CollectionRepository extends Repository {
  /** @returns {Promise<import('./index.js').Collection[]>} */
  async findAll() {
    throw new Error('Not implemented');
  }

  /** @param {string} _handle @returns {Promise<import('./index.js').Collection|null>} */
  async findByHandle(_handle) {
    throw new Error('Not implemented');
  }

  /** @param {string} _handle @returns {Promise<number>} */
  async countProducts(_handle) {
    throw new Error('Not implemented');
  }
}

export class ReviewRepository extends Repository {
  /** @param {string} _productId @param {{page:number,limit:number}} _page @returns {Promise<{items:import('./index.js').ProductReview[], total:number}>} */
  async listByProduct(_productId, _page) {
    throw new Error('Not implemented');
  }

  /** @param {string} _productId @param {import('./index.js').ProductReview} _review @returns {Promise<void>} */
  async add(_productId, _review) {
    throw new Error('Not implemented');
  }
}

/** Sort whitelist -> SQL ORDER BY (never interpolate user input directly). */
export const SORT_SQL = {
  featured: 'p.position ASC, p.rating_count DESC',
  best_selling: 'p.rating_count DESC',
  price_asc: 'p.price_paise ASC',
  price_desc: 'p.price_paise DESC',
  rating: 'p.rating DESC, p.rating_count DESC',
  newest: 'p.created_at DESC',
  title_asc: 'p.title ASC',
  title_desc: 'p.title DESC',
};

export const PRODUCT_SORTS = Object.keys(SORT_SQL);
