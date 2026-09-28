import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { db } from '../src/config/database.js';
import { createLogger } from '../src/shared/infrastructure/logger.js';
import { env } from '../src/config/env.js';

/**
 * migrate.js - applies every `db/migrations/*.sql` in lexical order inside a
 * single transaction per file, tracked in `schema_migrations`.
 *
 *   npm run migrate
 */
const logger = createLogger(env.nodeEnv);
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'db', 'migrations');

async function ensureTrackingTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()
  )`);
}

async function main() {
  await ensureTrackingTable();
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  const applied = new Set((await db.rows('SELECT name FROM schema_migrations')).map((r) => r.name));

  for (const file of files) {
    if (applied.has(file)) {
      logger.info(`skip  ${file} (already applied)`);
      continue;
    }
    const sql = await readFile(path.join(dir, file), 'utf8');
    logger.info(`apply ${file}`);
    await db.transaction(async (client) => {
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    });
  }
  logger.info('Migrations complete');
  await db.close();
}

main().catch(async (err) => {
  logger.error('Migration failed', { message: err.message });
  console.error(err);
  await db.close();
  process.exit(1);
});
