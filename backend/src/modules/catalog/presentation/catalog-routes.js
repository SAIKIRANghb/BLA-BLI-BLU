import express from 'express';
import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { validate } from '../../../shared/presentation/http/middlewares.js';
import { ListProducts, SearchProducts } from '../application/list-products.js';
import { GetProduct, ListCollections, ListReviews } from '../application/get-product.js';
import { PgProductRepository, PgCollectionRepository, PgReviewRepository } from '../infrastructure/pg-repositories.js';

/** Shared zod schemas (single source of truth for the catalog contract). */
export const catalogSchemas = {
  listQuery: z.object({
    collection: z.string().min(1).optional(),
    q: z.string().max(120).optional(),
    page: z.coerce.number().int().min(1).optional(),
    limit: z.coerce.number().int().min(1).max(100).optional(),
    sort: z.string().optional(),
    audiences: z.string().optional(),
  }),
  searchQuery: z.object({
    q: z.string().max(120).optional(),
    limit: z.coerce.number().int().min(1).max(50).optional(),
  }),
  handleParam: z.object({ handle: z.string().min(2).max(160) }),
  reviewsQuery: z.object({
    page: z.coerce.number().int().min(1).optional(),
    limit: z.coerce.number().int().min(1).max(50).optional(),
  }),
};

/**
 * CatalogController - thin presentation facade: validates (via route schema),
 * delegates to query use cases, shapes the response.
 */
export class CatalogController {
  constructor(deps) {
    this.listProducts = new ListProducts(deps);
    this.getProduct = new GetProduct(deps);
    this.listCollections = new ListCollections(deps);
    this.listReviews = new ListReviews(deps);
    this.searchProducts = new SearchProducts(deps);
  }

  list = asyncHandler(async (req, res) => {
    const page = await this.listProducts.execute(req.query);
    respond.ok(res, page.items, { page: page.page, limit: page.limit, total: page.total, totalPages: page.totalPages });
  });

  search = asyncHandler(async (req, res) => {
    const result = await this.searchProducts.execute(req.query);
    respond.ok(res, result.items, { total: result.total, query: result.query });
  });

  detail = asyncHandler(async (req, res) => {
    const result = await this.getProduct.execute(req.params);
    respond.ok(res, result);
  });

  collections = asyncHandler(async (_req, res) => {
    const items = await this.listCollections.execute();
    respond.ok(res, items);
  });

  reviews = asyncHandler(async (req, res) => {
    const result = await this.listReviews.execute({ ...req.params, ...req.query });
    respond.ok(res, result.items, {
      rating: result.rating,
      ratingCount: result.ratingCount,
      page: result.page,
      total: result.total,
      totalPages: result.totalPages,
    });
  });
}

/**
 * CatalogRouter - declarative route table bound to the controller.
 * @param {object} [deps] inject custom repositories (tests/DI container)
 * @returns {express.Router}
 */
export function createCatalogRouter(deps = {}) {
  const repositories = {
    productRepo: deps.productRepo ?? new PgProductRepository(),
    collectionRepo: deps.collectionRepo ?? new PgCollectionRepository(),
    reviewRepo: deps.reviewRepo ?? new PgReviewRepository(),
  };
  const controller = new CatalogController(repositories);

  // `schemas` = { params?, query?, body? } applied by the validate middleware.
  const table = new Router()
    .get('/collections', { handler: controller.collections })
    .get('/products', { schemas: { query: catalogSchemas.listQuery }, handler: controller.list })
    .get('/products/search', { schemas: { query: catalogSchemas.searchQuery }, handler: controller.search })
    .get('/products/:handle', { schemas: { params: catalogSchemas.handleParam }, handler: controller.detail })
    .get('/products/:handle/reviews', {
      schemas: { params: catalogSchemas.handleParam, query: catalogSchemas.reviewsQuery },
      handler: controller.reviews,
    });

  return bindRoutes(table);
}

