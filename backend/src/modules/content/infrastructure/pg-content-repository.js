import { db } from '../../../config/database.js';
import { Faq, CmsPage, SiteConfig } from '../domain/index.js';
import { ContentRepository } from '../application/content-queries.js';

/**
 * PgContentRepository - Infrastructure adapter for CMS-like read models.
 */
export class PgContentRepository extends ContentRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async getConfig(key) {
    const row = await this.db.one('SELECT * FROM site_config WHERE key = $1', [key]);
    return row ? new SiteConfig({ id: row.key, key: row.key, payload: row.payload, createdAt: row.created_at }) : null;
  }

  async listFaqs() {
    const rows = await this.db.rows('SELECT * FROM faqs ORDER BY position ASC, id ASC');
    return rows.map((r) => new Faq({ ...r, createdAt: r.created_at }));
  }

  async findPage(handle) {
    const row = await this.db.one('SELECT * FROM pages WHERE handle = $1', [handle]);
    return row ? new CmsPage({ ...row, createdAt: row.created_at }) : null;
  }
}
