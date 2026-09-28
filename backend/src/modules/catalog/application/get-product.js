import { Query } from '../../../shared/application/use-case.js';
import { PageRequest, PageResult } from '../../../shared/domain/pagination.js';
import { DomainError } from '../../../shared/domain/domain-error.js';

/**
 * GetProduct - product detail query.
 * Returns the detail DTO plus merchandising context (siblings in the same
 * collections) so the client can render "You may also like" without extra calls.
 */
export class GetProduct extends Query {
  /** @param {{productRepo:import('../domain/repositories.js').ProductRepository}} deps */
  constructor({ productRepo }) {
    super();
    this.productRepo = productRepo;
  }

  async execute({ handle, relatedLimit = 8 } = {}) {
    const product = await this.productRepo.findByHandle(String(handle ?? ''));
    if (!product) throw DomainError.notFound('Product not found');

    const related = [];
    const seen = new Set([product.handle.value]);
    for (const collectionHandle of product.collectionHandles) {
      if (related.length >= relatedLimit) break;
      const { items } = await this.productRepo.findAll({
        collection: collectionHandle,
        page: 1,
        limit: relatedLimit + 5,
        sort: 'best_selling',
      });
      for (const item of items) {
        if (related.length >= relatedLimit) break;
        if (seen.has(item.handle.value)) continue;
        seen.add(item.handle.value);
        related.push(item.toCardDto());
      }
    }

    return { product: product.toDetailDto(), related };
  }
}

/**
 * ListCollections - navigation / "Our Collection" tiles.
 */
export class ListCollections extends Query {
  /** @param {{collectionRepo:import('../domain/repositories.js').CollectionRepository}} deps */
  constructor({ collectionRepo }) {
    super();
    this.collectionRepo = collectionRepo;
  }

  async execute({ withCounts = true } = {}) {
    const collections = await this.collectionRepo.findAll();
    const counts = withCounts ? await this.collectionRepo.countPerCollection() : {};
    return collections.map((c) => c.toDto(counts[c.handle.value]));
  }
}

/**
 * ListReviews - paged product reviews (rating summary comes from the product).
 */
export class ListReviews extends Query {
  /** @param {{productRepo:import('../domain/repositories.js').ProductRepository, reviewRepo:import('../domain/repositories.js').ReviewRepository}} deps */
  constructor({ productRepo, reviewRepo }) {
    super();
    this.productRepo = productRepo;
    this.reviewRepo = reviewRepo;
  }

  async execute({ handle, page = 1, limit = 10 } = {}) {
    const product = await this.productRepo.findByHandle(String(handle ?? ''));
    if (!product) throw DomainError.notFound('Product not found');

    const pageRequest = new PageRequest({ page, limit, allowedSorts: ['featured'] });
    const { items, total } = await this.reviewRepo.listByProduct(product.id, pageRequest);

    return {
      rating: product.rating,
      ratingCount: product.ratingCount,
      ...new PageResult(items.map((r) => r.toDto()), total, pageRequest),
    };
  }
}
