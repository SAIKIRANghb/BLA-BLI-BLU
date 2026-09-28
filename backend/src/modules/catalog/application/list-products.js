import { Query } from '../../../shared/application/use-case.js';
import { PageRequest, PageResult } from '../../../shared/domain/pagination.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { PRODUCT_SORTS } from '../domain/repositories.js';

/**
 * ListProducts - catalogue browsing query (grid, collection pages, filters).
 * Input: { collection?, q?, page, limit, sort, audiences? }
 * Output: PageResult<{items: CardDto[], ...}>
 */
export class ListProducts extends Query {
  /** @param {{productRepo:import('../domain/repositories.js').ProductRepository, collectionRepo:import('../domain/repositories.js').CollectionRepository}} deps */
  constructor({ productRepo, collectionRepo }) {
    super();
    this.productRepo = productRepo;
    this.collectionRepo = collectionRepo;
  }

  async execute(input = {}) {
    const page = new PageRequest({ ...input, allowedSorts: PRODUCT_SORTS, limit: Number(input.limit ?? 24) });

    let collection = input.collection ?? null;
    if (collection && collection !== 'all') {
      const exists = await this.collectionRepo.findByHandle(collection);
      if (!exists) throw DomainError.notFound(`Collection "${collection}" not found`);
    }
    if (collection === 'all') collection = null;

    const { items, total } = await this.productRepo.findAll({
      collection,
      q: input.q ?? null,
      sort: page.sort,
      page: page.page,
      limit: page.limit,
      // Browsing a collection mirrors Shopify: every SKU in it is listed.
      excludeHidden: false,
    });

    return new PageResult(items.map((p) => p.toCardDto()), total, page);
  }
}

/**
 * SearchProducts - free text search returning light cards + counts per facet.
 */
export class SearchProducts extends Query {
  constructor({ productRepo }) {
    super();
    this.productRepo = productRepo;
  }

  async execute({ q = '', limit = 20 } = {}) {
    const query = String(q).trim();
    if (query.length < 2) return { items: [], total: 0, query };
    const { items, total } = await this.productRepo.findAll({
      q: query,
      page: 1,
      limit: Number(limit),
      sort: 'featured',
      // `hide-from-search` SKUs are invisible to search but stay browsable.
      excludeHidden: true,
    });
    return { items: items.map((p) => p.toCardDto()), total, query };
  }
}
