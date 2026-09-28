import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { db } from '../src/config/database.js';
import { createLogger } from '../src/shared/infrastructure/logger.js';
import { env } from '../src/config/env.js';
import { COLLECTIONS, COLLECTION_RULES, FEATURED_HANDLES, HOME, FAQS, PAGES, COUPONS } from '../db/seed/content.js';

/**
 * seed.js - loads the recreated Bla Bli Blu catalogue (db/seed/catalog.json,
 * exported from the storefront) plus content/collections/coupons into
 * PostgreSQL. Idempotent: it truncates the seed-owned tables first.
 *
 *   npm run db:setup   (migrate + seed)
 */
const logger = createLogger(env.nodeEnv);
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Real ratings scraped from the storefront (handle -> [rating, count]). */
const RATINGS = {
  'love-drunk-best-unisex-perfume': [4.8, 1148],
  'watermelon-buddy': [4.7, 165],
  'old-money-long-lasting-perfume-for-men': [4.8, 1212],
  'perfume-gift-set-for-men': [4.8, 771],
  'perfume-gift-set-for-women': [4.6, 857],
  'mango-so-goated': [4.4, 199],
  'berry-baddie': [4.4, 196],
  'happy-bananana': [4.7, 166],
  'billionaire-vibes-men-perfume': [4.7, 281],
  'lil-black-dress-perfume-for-women': [4.9, 714],
  'habibi-unisex-perfume': [4.9, 550],
  'habibi': [4.9, 550],
  'love-drunk-body-wash': [4.8, 846],
  'bla-bli-blu-ultimate-experience-set': [4.8, 82],
  'old-money-body-wash': [4.8, 637],
  'self-made-perfume-body-wash-for-men': [4.8, 622],
  'by-the-beach': [4.8, 1199],
  'vetiver-oud': [4.8, 1238],
  'backseat-confessions-car-perfume': [4.7, 222],
  'best-perfume-trial-pack-for-men': [4.8, 1326],
  'passenger-princess-car-parfum': [4.6, 269],
  'my-wingman-men-pefume': [4.8, 857],
  'hot-af-women-perfume': [4.8, 882],
  'oud-unisex-perfume-gift-set': [4.9, 801],
  'love-drunk-with-eau-de-oil-75ml-8ml': [4.9, 580],
  'self-made-long-lasting-men-perfume': [4.8, 812],
  'cookie-crush-perfume-for-women': [4.9, 725],
  'ivory-oud': [4.8, 704],
  'golden-oud': [4.8, 688],
  'oud-honey-unisex-perfume': [4.7, 512],
  'lights-off-unisex-perfume': [4.7, 466],
  'white-jazz': [4.7, 489],
  'peaches': [4.6, 402],
  'build-your-own-box': [4.8, 344],
};

/** "Candied nutes | Cinnamon | Dates" style summaries shown on product cards. */
const NOTES_SUMMARY = {
  'love-drunk-best-unisex-perfume': 'Candied nutes | Cinnamon | Dates',
  'watermelon-buddy': 'Watermelon | Coconut | Vanilla',
  'old-money-long-lasting-perfume-for-men': 'Chamomile | Cedar | Vanilla',
  'perfume-gift-set-for-men': 'My Wingman | By The Beach | Old Money',
  'perfume-gift-set-for-women': 'White Jazz | Hot AF | Cookie Crush',
  'mango-so-goated': 'Mango | Frangipani | Cashmere',
  'berry-baddie': 'Strawberry, Jam, Cream',
  'happy-bananana': 'Banana, Praline, Caramel',
  'billionaire-vibes-men-perfume': 'Grapefruit | Cedar | Oakmoss',
  'lil-black-dress-perfume-for-women': 'Pear | Coffee | Vanilla',
  'habibi-unisex-perfume': 'Coffee | Rose | Leather',
  'habibi': 'Coffee | Rose | Leather',
  'love-drunk-body-wash': 'Candied nutes | Cinnamon | Dates',
  'bla-bli-blu-ultimate-experience-set': 'Old Money | By the Beach | My Wingman | Selfmade | Golden Oud | Vetiver Oud',
  'self-made-perfume-body-wash-for-men': 'Bourbon | Vanilla | Bergamot',
  'old-money-body-wash': 'Chamomile | Cedar | Vanilla',
  'by-the-beach': 'Lemon | Bergamot | Apple',
  'my-wingman-men-pefume': 'Cardamom | Tobacco | Cedar',
  'hot-af-women-perfume': 'Blackcurrant | Lily | Truffle',
  'self-made-long-lasting-men-perfume': 'Bourbon Vanilla | Bergamot',
  'cookie-crush-perfume-for-women': 'Berries | Lilac | Vanilla',
  'vetiver-oud': 'Moroccan Rose | Amber | Oud',
  'oud-unisex-perfume-gift-set': 'Vetiver Oud | Oud Honey | Golden Oud',
  'love-drunk-with-eau-de-oil-75ml-8ml': 'Candied nutes | Cinnamon | Dates',
  'one-hand-drive-car-perfume': 'Leather | Woody | Musk',
  'passenger-princess-car-parfum': 'Plum | Chamomile | Vanilla',
  'backseat-confessions-car-perfume': 'Pear | Muguet | Vanilla',
  'midnight-cruise-car-perfume': 'Amber | Oud | Leather',
  'oud-honey-unisex-perfume': 'Honey | Oud | Amber',
  'golden-oud': 'Saffron | Rose | Oud',
  'ivory-oud': 'Iris | Vanilla | Oud',
  'lights-off-unisex-perfume': 'Tobacco | Leather | Tonka',
  'white-jazz': 'Jasmine | Sandalwood | Musk',
  'peaches': 'Peach | Jasmine | Vanilla',
  'hot-af-75ml-8ml': 'Blackcurrant | Lily | Truffle',
  'my-wingman-two-scents-one-feeling-75ml-8ml': 'Cardamom | Tobacco | Cedar',
  'by-the-beach-two-scents-one-feeling-75ml-8ml': 'Lemon | Bergamot | Apple',
  'lights-off-75ml-8ml': 'Tobacco | Leather | Tonka',
};

/** Full pyramid (head/heart/base) with real icon assets. */
const NOTES_Pyramid = {
  'love-drunk-best-unisex-perfume': {
    head: ['Cinnamon', 'Nutmeg', 'Bergamot'],
    heart: ['Dates', 'Praline', 'Tuberose'],
    base: ['Vanilla', 'Tonka Bean', 'Benzoin'],
  },
};
const NOTE_ICONS = {
  Cinnamon: 'cinnamon.jpg?v=1751971585',
  Nutmeg: 'nutmeg.jpg?v=1751976704',
  Bergamot: 'bergamot.jpg?v=1751974924',
  Dates: 'dates.jpg?v=1751976703',
  Praline: 'praline.jpg?v=1751976703',
  Tuberose: 'tuberose_0b261ef1-bd78-4ca7-8038-242eaeea907c.jpg?v=1754921177',
  Vanilla: 'vanilla.jpg?v=1751971586',
  'Tonka Bean': 'tonka-bean.jpg?v=1751972166',
  Benzoin: 'benzoin-icon.jpg?v=1754297399',
};

const REVIEW_TEMPLATES = [
  ['Incredible longevity', 'Wore it from morning meetings to a late dinner and it was still going strong.'],
  ['Compliment magnet', 'Three people asked what I was wearing on the very first day.'],
  ['Exactly as described', 'The notes open up exactly like the description says. Worth every rupee.'],
  ['Great value', 'Honestly better than perfumes I have paid double for. Packaging was spotless too.'],
  ['My new signature', 'Bought the trial pack, full sized this one immediately after.'],
  ['Projection is strong', 'Two sprays are more than enough. Do not over spray!'],
];
const REVIEWERS = ['Aarav Sharma', 'Priya Nair', 'Rohan Mehta', 'Sneha Iyer', 'Kabir Singh', 'Ananya Rao', 'Dev Patel', 'Ishita Bose'];

/** Deterministic pseudo-random from a string (stable across runs). */
function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

function stripHtml(html) {
  return String(html ?? '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|h[1-6]|li|div)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/\n{2,}/g, '\n')
    .trim();
}

function absoluteUrl(src) {
  if (!src) return null;
  if (src.startsWith('//')) return `https:${src}`;
  return src;
}

function audienceOf(tags) {
  const t = tags.map((x) => x.toLowerCase());
  if (t.includes('car-fragrance')) return 'Car Fragrance';
  if (t.includes('body-wash')) {
    if (t.includes('bodywash - men')) return 'Perfumed Body Wash For Men';
    if (t.includes('bodywash - women')) return 'Perfumed Body Wash For Women';
    return 'Perfumed Body Wash Unisex';
  }
  if (t.includes('gift set men')) return 'For Men';
  if (t.includes('gift set women')) return 'For Women';
  if (t.includes('gift set oud')) return 'Oud Unisex';
  if (t.includes('kit') || t.includes('reedeemable') || t.includes('reedeemable449')) {
    if (t.includes('men')) return 'For Him';
    if (t.includes('women')) return 'For Her';
    return 'Trial Set';
  }
  if (t.includes('for men') || t.includes('men')) return 'For Men';
  if (t.includes('for women') || t.includes('women')) return 'For Women';
  if (t.includes('oud')) return 'Oud Unisex';
  return 'Unisex';
}

function notesSummaryOf(handle) {
  return NOTES_SUMMARY[handle] ?? '';
}

async function main() {
  const catalog = JSON.parse(await readFile(path.join(root, 'db', 'seed', 'catalog.json'), 'utf8'));
  const products = catalog.products ?? [];
  logger.info(`Seeding ${products.length} products`);

  await db.transaction(async (client) => {
    // ---- wipe (seed-owned tables only) --------------------------------
    await client.query(
      `TRUNCATE product_reviews, product_collections, product_notes, product_variants, product_images,
                products, collections, faqs, pages, coupons, site_config CASCADE`,
    );

    // ---- collections ---------------------------------------------------
    const collectionIds = {};
    for (const c of COLLECTIONS) {
      const id = randomUUID();
      collectionIds[c.handle] = id;
      await client.query(
        'INSERT INTO collections (id, handle, title, description, image_url, position) VALUES ($1,$2,$3,$4,$5,$6)',
        [id, c.handle, c.title, c.description, c.imageUrl, c.position],
      );
    }

    // ---- products ------------------------------------------------------
    const featuredRank = new Map(FEATURED_HANDLES.map((h, i) => [h, i]));
    const sorted = [...products].sort((a, b) => {
      const ra = featuredRank.has(a.handle) ? featuredRank.get(a.handle) : 9999;
      const rb = featuredRank.has(b.handle) ? featuredRank.get(b.handle) : 9999;
      return ra - rb || a.title.localeCompare(b.title);
    });

    const productIdByHandle = {};
    const memberships = [];

    for (const [index, p] of sorted.entries()) {
      const tags = p.tags ?? [];
      const lowerTags = tags.map((t) => t.toLowerCase());
      const variant = p.variants?.[0] ?? {};
      const price = Math.round(Number(variant.price ?? 0) * 100);
      const compareAt = variant.compare_at_price ? Math.round(Number(variant.compare_at_price) * 100) : null;
      const [rating, ratingCount] = RATINGS[p.handle] ?? [4.3 + (hash(p.handle) % 7) / 10, 40 + (hash(p.handle + 'c') % 620)];
      const id = randomUUID();
      productIdByHandle[p.handle] = id;

      const text = stripHtml(p.body_html);
      const [firstLine = '', ...rest] = text.split('\n');
      const tagline = firstLine.length <= 90 ? firstLine : '';
      const description = (tagline ? rest.join('\n') : text).trim() || firstLine;
      const hidden = lowerTags.includes('hide-from-search');
      const isParfum = lowerTags.includes('parfum') || lowerTags.includes('perfume');
      const badge = ratingCount >= 1000 ? 'Bestseller' : lowerTags.includes('new arrivals') ? 'New' : null;
      const imageUrl = absoluteUrl(p.images?.[0]?.src);

      await client.query(
        `INSERT INTO products
           (id, handle, title, description, tagline, vendor, product_type, price_paise, compare_at_paise,
            available, rating, rating_count, notes_summary, audience, badge, oil_concentration, tags,
            image_url, position, hidden, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)`,
        [
          id,
          p.handle,
          p.title,
          description,
          tagline,
          p.vendor || 'Bla Bli Blu',
          p.product_type || '',
          price,
          compareAt,
          (variant.available ?? true),
          Number(rating.toFixed(1)),
          ratingCount,
          notesSummaryOf(p.handle),
          audienceOf(lowerTags),
          badge,
          isParfum ? (p.handle === 'by-the-beach' ? '20% Oil Concentration' : '25% Oil Concentration') : null,
          JSON.stringify(tags),
          imageUrl,
          index,
          hidden,
          p.created_at ? new Date(p.created_at) : new Date(),
        ],
      );

      for (const [pos, img] of (p.images ?? []).entries()) {
        await client.query('INSERT INTO product_images (id, product_id, image_url, alt, position) VALUES ($1,$2,$3,$4,$5)', [
          randomUUID(),
          id,
          absoluteUrl(img.src),
          img.alt ?? '',
          pos,
        ]);
      }

      for (const [pos, v] of (p.variants ?? []).entries()) {
        await client.query(
          `INSERT INTO product_variants (id, product_id, title, sku, price_paise, compare_at_paise, available, position)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
          [
            randomUUID(),
            id,
            v.title ?? 'Default Title',
            v.sku ?? null,
            Math.round(Number(v.price ?? 0) * 100),
            v.compare_at_price ? Math.round(Number(v.compare_at_price) * 100) : null,
            v.available !== false,
            pos,
          ],
        );
      }

      // ---- notes pyramid ------------------------------------------------
      const pyramid = NOTES_Pyramid[p.handle] ?? derivePyramid(NOTES_SUMMARY[p.handle] ?? '');
      let notePosition = 0;
      for (const type of ['head', 'heart', 'base']) {
        for (const name of pyramid[type] ?? []) {
          const icon = NOTE_ICONS[name] ? `https://blabliblulife.com/cdn/shop/files/${NOTE_ICONS[name]}` : null;
          await client.query(
            'INSERT INTO product_notes (id, product_id, note_type, name, icon_url, position) VALUES ($1,$2,$3,$4,$5,$6)',
            [randomUUID(), id, type, name, icon, notePosition++],
          );
        }
      }

      // ---- reviews ------------------------------------------------------
      const reviewCount = ratingCount >= 600 ? 4 : 3;
      for (let r = 0; r < reviewCount; r += 1) {
        const seed = hash(`${p.handle}-review-${r}`);
        const [title, body] = REVIEW_TEMPLATES[seed % REVIEW_TEMPLATES.length];
        const author = REVIEWERS[(seed >> 3) % REVIEWERS.length];
        const stars = Math.min(5, Math.max(4, Math.round(rating)));
        await client.query(
          'INSERT INTO product_reviews (id, product_id, author, rating, title, body, created_at) VALUES ($1,$2,$3,$4,$5,$6,$7)',
          [
            randomUUID(),
            id,
            author,
            stars,
            title,
            body,
            new Date(Date.now() - ((seed % 60) + 1) * 86_400_000),
          ],
        );
      }

      // ---- collection membership ---------------------------------------
      for (const rule of COLLECTION_RULES) {
        const matchesTag = (rule.tags ?? []).some((t) => lowerTags.includes(t.toLowerCase()));
        const matchesHandle = (rule.handles ?? []).includes(p.handle);
        if (matchesTag || matchesHandle) {
          memberships.push([id, collectionIds[rule.handle], memberships.length]);
        }
      }
    }

    for (const [productId, collectionId, position] of memberships) {
      await client.query(
        'INSERT INTO product_collections (product_id, collection_id, position) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING',
        [productId, collectionId, position],
      );
    }

    // ---- content --------------------------------------------------------
    await client.query('INSERT INTO site_config (key, payload) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET payload = EXCLUDED.payload', [
      'home',
      JSON.stringify(HOME),
    ]);

    for (const [i, faq] of FAQS.entries()) {
      await client.query('INSERT INTO faqs (id, category, question, answer, position) VALUES ($1,$2,$3,$4,$5)', [
        randomUUID(),
        faq.category,
        faq.question,
        faq.answer,
        i,
      ]);
    }

    for (const page of PAGES) {
      await client.query(
        'INSERT INTO pages (handle, title, body) VALUES ($1,$2,$3) ON CONFLICT (handle) DO UPDATE SET title = EXCLUDED.title, body = EXCLUDED.body',
        [page.handle, page.title, page.body],
      );
    }

    for (const coupon of COUPONS) {
      await client.query(
        `INSERT INTO coupons (code, coupon_type, value, min_order_paise, max_discount_paise, active, description)
         VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (code) DO UPDATE SET
           coupon_type = EXCLUDED.coupon_type, value = EXCLUDED.value,
           min_order_paise = EXCLUDED.min_order_paise, max_discount_paise = EXCLUDED.max_discount_paise,
           active = EXCLUDED.active, description = EXCLUDED.description`,
        [coupon.code, coupon.coupon_type, coupon.value, coupon.min_order_paise, coupon.max_discount_paise, coupon.active, coupon.description],
      );
    }
  });

  const counts = {
    products: (await db.one('SELECT COUNT(*)::int AS c FROM products')).c,
    collections: (await db.one('SELECT COUNT(*)::int AS c FROM collections')).c,
    memberships: (await db.one('SELECT COUNT(*)::int AS c FROM product_collections')).c,
    reviews: (await db.one('SELECT COUNT(*)::int AS c FROM product_reviews')).c,
    notes: (await db.one('SELECT COUNT(*)::int AS c FROM product_notes')).c,
    faqs: (await db.one('SELECT COUNT(*)::int AS c FROM faqs')).c,
  };
  logger.info('Seed complete', counts);
  await db.close();
}

/** Splits a "Top | Heart | Base" summary into a 3-step pyramid. */
function derivePyramid(summary) {
  const parts = String(summary)
    .split(/[|,]/)
    .map((s) => s.trim())
    .filter(Boolean);
  if (parts.length === 0) return { head: [], heart: [], base: [] };
  if (parts.length === 1) return { head: [parts[0]], heart: [], base: [] };
  if (parts.length === 2) return { head: [parts[0]], heart: [parts[1]], base: [] };
  return { head: parts.slice(0, Math.ceil(parts.length / 3)), heart: parts.slice(Math.ceil(parts.length / 3), Math.ceil((parts.length * 2) / 3)), base: parts.slice(Math.ceil((parts.length * 2) / 3)) };
}

main().catch(async (err) => {
  logger.error('Seed failed', { message: err.message });
  console.error(err);
  await db.close();
  process.exit(1);
});
