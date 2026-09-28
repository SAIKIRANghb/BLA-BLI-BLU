import { db } from '../../../config/database.js';
import { Product, Collection, ProductVariant, ProductNote, ProductReview } from '../domain/index.js';
import { ProductRepository, CollectionRepository, ReviewRepository, SORT_SQL } from '../domain/repositories.js';

/**
 * Row -> Entity mappers (Adapter boundary). Keeping mapping here means SQL
 * column names never leak into the domain or application layers.
 */

function mapRow(row) {
  if (!row) return null;
  return new Product({
    id: row.id,
    handle: row.handle,
    title: row.title,
    description: row.description,
    tagline: row.tagline,
    vendor: row.vendor,
    productType: row.product_type,
    price: row.price_paise,
    compareAtPrice: row.compare_at_paise,
    available: row.available,
    rating: row.rating,
    ratingCount: row.rating_count,
    notesSummary: row.notes_summary,
    audience: row.audience,
    badge: row.badge,
    oilConcentration: row.oil_concentration,
    tags: row.tags ?? [],
    imageUrl: row.image_url,
    images: (row.images ?? []).map((i) => ({ url: i.url, alt: i.alt })),
    variants: (row.variants ?? []).map(
      (v) => new ProductVariant({ ...v, price: v.price, compareAtPrice: v.compare_at_price ?? null }),
    ),
    notes: (row.notes ?? []).map((n) => new ProductNote(n)),
    collectionHandles: row.collection_handles ?? [],
    position: row.position,
    hidden: row.hidden,
    createdAt: row.created_at,
  });
}

const FULL_SELECT = `
  SELECT p.*,
    COALESCE((
      SELECT json_agg(json_build_object('url', i.image_url, 'alt', i.alt, 'position', i.position) ORDER BY i.position)
      FROM product_images i WHERE i.product_id = p.id
    ), '[]'::json) AS images,
    COALESCE((
      SELECT json_agg(json_build_object(
        'id', v.id, 'title', v.title, 'sku', v.sku,
        'price', v.price_paise, 'compare_at_price', v.compare_at_paise,
        'available', v.available, 'position', v.position
      ) ORDER BY v.position)
      FROM product_variants v WHERE v.product_id = p.id
    ), '[]'::json) AS variants,
    COALESCE((
      SELECT json_agg(json_build_object(
        'id', n.id, 'type', n.note_type, 'name', n.name,
        'icon_url', n.icon_url, 'position', n.position
      ) ORDER BY CASE n.note_type WHEN 'head' THEN 1 WHEN 'heart' THEN 2 ELSE 3 END, n.position)
      FROM product_notes n WHERE n.product_id = p.id
    ), '[]'::json) AS notes,
    COALESCE((
      SELECT json_agg(c.handle ORDER BY c.position)
      FROM product_collections pc JOIN collections c ON c.id = pc.collection_id
      WHERE pc.product_id = p.id
    ), '[]'::json) AS collection_handles
  FROM products p
`;

/**
 * PgProductRepository - Infrastructure adapter (Repository + Specification).
 */
export class PgProductRepository extends ProductRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async findById(id) {
    const row = await this.db.one(`${FULL_SELECT} WHERE p.id = $1`, [id]);
    return mapRow(row);
  }

  async findByHandle(handle) {
    const row = await this.db.one(`${FULL_SELECT} WHERE p.handle = $1`, [handle]);
    return mapRow(row);
  }

  /**
   * @param {import('../domain/repositories.js').ProductListQuery} query
   */
  async findAll(query = {}) {
    const { collection = null, q = null, sort = 'featured', page = 1, limit = 24, excludeHidden = false } = query;
    const where = [];
    const params = [];

    // `hidden` mirrors Shopify's "hide-from-search" tag: it suppresses a SKU
    // from *search results*, but the product still lives in its collections.
    if (q && excludeHidden) where.push('p.hidden = FALSE');
    if (collection) {
      params.push(collection);
      where.push(
        `EXISTS (SELECT 1 FROM product_collections pc
                 JOIN collections c ON c.id = pc.collection_id
                 WHERE pc.product_id = p.id AND c.handle = $${params.length})`,
      );
    }
    if (q) {
      params.push(`%${q}%`);
      const n = params.length;
      where.push(
        `(p.title ILIKE $${n} OR p.notes_summary ILIKE $${n} OR p.audience ILIKE $${n}
          OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(p.tags::jsonb) t WHERE t ILIKE $${n}))`,
      );
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const orderSql = SORT_SQL[sort] ?? SORT_SQL.featured;

    const countRow = await this.db.one(`SELECT COUNT(*)::int AS count FROM products p ${whereSql}`, params);
    const limitIndex = params.length + 1;
    const offsetIndex = params.length + 2;
    const rows = await this.db.rows(
      `${FULL_SELECT} ${whereSql} ORDER BY ${orderSql} LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
      [...params, limit, (page - 1) * limit],
    );
    return { items: rows.map(mapRow), total: countRow.count };
  }

  async findManyByHandles(handles) {
    if (!handles.length) return [];
    const rows = await this.db.rows(`${FULL_SELECT} WHERE p.handle = ANY($1)`, [handles]);
    return rows.map(mapRow);
  }
}

/** Row -> Collection. SQL stays snake_case, the entity speaks camelCase. */
function mapCollectionRow(row) {
  if (!row) return null;
  return new Collection({
    id: row.id,
    handle: row.handle,
    title: row.title,
    description: row.description,
    imageUrl: row.image_url,
    position: row.position,
  });
}

/** PgCollectionRepository */
export class PgCollectionRepository extends CollectionRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async findAll() {
    const rows = await this.db.rows('SELECT * FROM collections ORDER BY position ASC, title ASC');
    return rows.map(mapCollectionRow);
  }

  async findByHandle(handle) {
    const row = await this.db.one('SELECT * FROM collections WHERE handle = $1', [handle]);
    return mapCollectionRow(row);
  }

  async countProducts(handle) {
    const row = await this.db.one(
      `SELECT COUNT(*)::int AS count
       FROM product_collections pc JOIN collections c ON c.id = pc.collection_id
       JOIN products p ON p.id = pc.product_id
       WHERE c.handle = $1`,
      [handle],
    );
    return row?.count ?? 0;
  }

  async countPerCollection() {
    const rows = await this.db.rows(
      `SELECT c.handle, COUNT(*)::int AS count
       FROM collections c
       LEFT JOIN product_collections pc ON pc.collection_id = c.id
       LEFT JOIN products p ON p.id = pc.product_id
       GROUP BY c.handle`,
    );
    return Object.fromEntries(rows.map((r) => [r.handle, r.count]));
  }
}

/** PgReviewRepository */
export class PgReviewRepository extends ReviewRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async listByProduct(productId, { page = 1, limit = 10 } = {}) {
    const countRow = await this.db.one('SELECT COUNT(*)::int AS count FROM product_reviews WHERE product_id = $1', [
      productId,
    ]);
    const rows = await this.db.rows(
      `SELECT * FROM product_reviews WHERE product_id = $1
       ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [productId, limit, (page - 1) * limit],
    );
    return {
      items: rows.map((r) => new ProductReview({ ...r, createdAt: r.created_at })),
      total: countRow.count,
    };
  }

  async add(productId, review) {
    await this.db.query(
      `INSERT INTO product_reviews (id, product_id, author, rating, title, body, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [review.id, productId, review.author, review.rating, review.title, review.body, review.createdAt],
    );
  }
}
