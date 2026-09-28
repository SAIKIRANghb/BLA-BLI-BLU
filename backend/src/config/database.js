import pg from 'pg';
import { env } from './env.js';
import { createLogger } from '../shared/infrastructure/logger.js';

const { Pool } = pg;
const logger = createLogger(env.nodeEnv);

/**
 * Database - Singleton connection pool + Unit of Work helper.
 *
 * All SQL lives in infrastructure adapters; domain/application layers only see
 * the `query()` / `transaction()` surface through injected repositories.
 */
class Database {
  constructor(config = env.db) {
    this.pool = new Pool({
      host: config.host,
      port: config.port,
      database: config.name,
      user: config.user,
      password: config.password,
      max: config.poolMax,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
    });
    this.pool.on('error', (err) => logger.error('Unexpected PG pool error', { message: err.message }));
  }

  /**
   * @param {string} text SQL with $1 placeholders
   * @param {any[]} params
   * @returns {Promise<{rows:any[], rowCount:number}>}
   */
  query(text, params = []) {
    return this.pool.query(text, params);
  }

  /** @returns {Promise<any[]>} */
  async rows(text, params = []) {
    const res = await this.query(text, params);
    return res.rows;
  }

  /** @returns {Promise<any|null>} */
  async one(text, params = []) {
    const res = await this.query(text, params);
    return res.rows[0] ?? null;
  }

  /**
   * Unit of Work: runs `fn(client => ...)` inside a transaction and commits /
   * rolls back automatically (Decorator-ish behaviour around the pool).
   *
   * The client handed to `fn` is a facade with the same `query/one/rows`
   * surface as the database object, so repositories can be constructed on top
   * of either a pool connection or the pool itself.
   *
   * @template T
   * The facade also exposes `transaction()`, so a repository works unchanged
   * whether it is built on the pool (nested calls open a SAVEPOINT-free inner
   * transaction) or on an existing Unit-of-Work transaction (which re-enters
   * the same transaction instead of opening a second connection).
   *
   * @param {(client:{query:Function, one:Function, rows:Function, transaction:Function})=>Promise<T>} fn
   * @returns {Promise<T>}
   */
  async transaction(fn) {
    const client = await this.pool.connect();
    const tx = this.wrap(client);
    tx.transaction = (inner) => inner(tx);
    try {
      await client.query('BEGIN');
      const result = await fn(tx);
      await client.query('COMMIT');
      return result;
    } catch (err) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* connection already broken */
      }
      throw err;
    } finally {
      client.release();
    }
  }

  /** Wraps a pool client (or this database) into the query/one/rows facade. */
  wrap(client) {
    return {
      query: (text, params = []) => client.query(text, params),
      one: async (text, params = []) => (await client.query(text, params)).rows[0] ?? null,
      rows: async (text, params = []) => (await client.query(text, params)).rows,
      raw: client,
    };
  }

  async close() {
    await this.pool.end();
  }
}

/** Singleton instance */
export const db = new Database();
export { Database };
