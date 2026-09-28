import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { GetHome, ListFaqs, GetPage } from '../application/content-queries.js';
import { PgContentRepository } from '../infrastructure/pg-content-repository.js';
import { PgProductRepository } from '../../catalog/infrastructure/pg-repositories.js';

export const contentSchemas = {
  pageHandle: z.object({ handle: z.string().min(2).max(80) }),
};

/** ContentController - home composition, FAQs and CMS pages. */
class ContentController {
  constructor(useCases) {
    this.getHome = useCases.getHome;
    this.listFaqs = useCases.listFaqs;
    this.getPage = useCases.getPage;
  }

  home = asyncHandler(async (_req, res) => respond.ok(res, await this.getHome.execute()));
  faqs = asyncHandler(async (_req, res) => respond.ok(res, await this.listFaqs.execute()));
  page = asyncHandler(async (req, res) => respond.ok(res, await this.getPage.execute(req.params)));
}

/**
 * createContentRouter - composition root for the content context.
 * @param {object} [overrides]
 */
export function createContentRouter(overrides = {}) {
  const contentRepo = overrides.contentRepo ?? new PgContentRepository();
  const productRepo = overrides.productRepo ?? new PgProductRepository();

  const controller = new ContentController({
    getHome: new GetHome({ contentRepo, productRepo }),
    listFaqs: new ListFaqs({ contentRepo }),
    getPage: new GetPage({ contentRepo }),
  });

  const table = new Router()
    .get('/home', { handler: controller.home })
    .get('/faqs', { handler: controller.faqs })
    .get('/pages/:handle', { schemas: { params: contentSchemas.pageHandle }, handler: controller.page });

  return bindRoutes(table);
}
