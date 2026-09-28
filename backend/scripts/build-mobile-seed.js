/**
 * build-mobile-seed.js
 *
 * Pulls the whole public catalogue + content surface out of the running API and
 * writes `mobile/assets/seed/seed.json`, the offline store the Flutter app reads
 * when `kUseLocalSeed` is `true`.
 *
 * Run:  npm run seed:mobile   (server must be up: `npm run dev`)
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const API = process.env.SEED_API ?? 'http://localhost:4000/api';
const OUT = resolve(__dirname, '../../mobile/assets/seed/seed.json');

const PAGE_HANDLES = [
  'about-us',
  'terms-of-service',
  'privacy-policy',
  'shipping-policy',
  'refund-policy',
  'exchange-policy',
  'cashback-terms-conditions',
  'contact',
  'wholesale-contact-form',
];

async function call(path) {
  const res = await fetch(`${API}${path}`, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`${path} -> ${res.status} ${await res.text()}`);
  const body = await res.json();
  if (body.success === false) throw new Error(`${path} -> ${JSON.stringify(body.error)}`);
  return body;
}

/** Pages every `/products` request until the catalogue is exhausted. */
async function allProducts() {
  const items = [];
  const limit = 100;
  for (let page = 1; ; page += 1) {
    const { data, meta } = await call(`/products?limit=${limit}&page=${page}`);
    items.push(...data);
    if (page >= (meta.totalPages ?? 1) || data.length === 0) break;
  }
  return items;
}

async function collectionHandles() {
  const { data: collections } = await call('/collections');
  const byHandle = {};
  for (const collection of collections) {
    const { data } = await call(`/products?collection=${collection.handle}&limit=100`);
    byHandle[collection.handle] = data.map((p) => p.handle);
  }
  return { collections, byHandle };
}

async function detailsFor(products) {
  const details = {};
  const reviews = {};
  // modest concurrency so the dev server is not flooded
  const queue = [...products];
  const workers = Array.from({ length: 6 }, async () => {
    for (;;) {
      const product = queue.shift();
      if (!product) return;
      const { data } = await call(`/products/${product.handle}`);
      details[product.handle] = data.product;
      if (data.reviews) reviews[product.handle] = data.reviews;
      else {
        const r = await call(`/products/${product.handle}/reviews?limit=50`);
        reviews[product.handle] = r.data;
      }
    }
  });
  await Promise.all(workers);
  return { details, reviews };
}

async function main() {
  console.log(`→ reading ${API}`);

  const [home, products, { collections, byHandle }, faqs] = await Promise.all([
    call('/home'),
    allProducts(),
    collectionHandles(),
    call('/faqs'),
  ]);
  console.log(`  home, ${products.length} products, ${collections.length} collections`);

  const { details, reviews } = await detailsFor(products);
  console.log(`  ${Object.keys(details).length} details, ${Object.keys(reviews).length} review sets`);

  const pages = {};
  for (const handle of PAGE_HANDLES) {
    try {
      pages[handle] = (await call(`/pages/${handle}`)).data;
    } catch (err) {
      console.warn(`  ! page ${handle}: ${err.message}`);
    }
  }
  console.log(`  ${Object.keys(pages).length} pages`);

  const seed = {
    generatedAt: new Date().toISOString(),
    source: API,
    home: home.data,
    collections,
    collectionProducts: byHandle,
    products,
    details,
    reviews,
    faqs: faqs.data,
    pages,
  };

  await mkdir(dirname(OUT), { recursive: true });
  await writeFile(OUT, JSON.stringify(seed), 'utf8');
  const kb = Math.round((JSON.stringify(seed).length / 1024) * 10) / 10;
  console.log(`✓ ${OUT} (${kb} KB)`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
