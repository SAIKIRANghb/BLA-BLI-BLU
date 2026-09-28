import { Query } from '../../../shared/application/use-case.js';
import { DomainError } from '../../../shared/domain/domain-error.js';

/**
 * ContentRepository contract (Dependency Inversion).
 */
export class ContentRepository {
  async getConfig(_key) {
    throw new Error('Not implemented');
  }

  async listFaqs() {
    throw new Error('Not implemented');
  }

  async findPage(_handle) {
    throw new Error('Not implemented');
  }
}

/**
 * GetHome - composite query that assembles the home screen in one round trip:
 * static composition (banners/tiles/footer) + hydrated product cards for the
 * featured carousel.
 */
export class GetHome extends Query {
  /** @param {{contentRepo:ContentRepository, productRepo:import('../../catalog/domain/repositories.js').ProductRepository}} deps */
  constructor({ contentRepo, productRepo }) {
    super();
    this.contentRepo = contentRepo;
    this.productRepo = productRepo;
  }

  async execute() {
    const config = await this.contentRepo.getConfig('home');
    if (!config) throw DomainError.notFound('Home configuration missing');

    const payload = config.toDto();
    const handles = payload.featuredHandles ?? [];
    const products = handles.length ? await this.productRepo.findManyByHandles(handles) : [];

    // preserve merchandising order defined in the seed
    const byHandle = new Map(products.map((p) => [p.handle.value, p]));
    const featured = handles.map((h) => byHandle.get(h)).filter(Boolean).map((p) => p.toCardDto());

    const { items: newArrivals } = await this.productRepo.findAll({
      q: null,
      sort: 'newest',
      page: 1,
      limit: 8,
      collection: null,
    });

    return {
      ...payload,
      featured,
      newArrivals: newArrivals.map((p) => p.toCardDto()),
    };
  }
}

/** ListFaqs - FAQ accordion data, grouped by category. */
export class ListFaqs extends Query {
  constructor({ contentRepo }) {
    super();
    this.contentRepo = contentRepo;
  }

  async execute() {
    const faqs = await this.contentRepo.listFaqs();
    const groups = new Map();
    for (const faq of faqs) {
      const list = groups.get(faq.category) ?? [];
      list.push(faq.toDto());
      groups.set(faq.category, list);
    }
    return [...groups.entries()].map(([category, items]) => ({ category, items }));
  }
}

/** GetPage - legal/about content by handle. */
export class GetPage extends Query {
  constructor({ contentRepo }) {
    super();
    this.contentRepo = contentRepo;
  }

  async execute({ handle }) {
    const page = await this.contentRepo.findPage(handle);
    if (!page) throw DomainError.notFound(`Page "${handle}" not found`);
    return page.toDto();
  }
}
