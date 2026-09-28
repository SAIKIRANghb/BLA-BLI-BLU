import { createApp } from './app.js';
import { env } from './config/env.js';
import { db } from './config/database.js';

/**
 * Server bootstrap: build the app, verify connectivity, listen, and shut down
 * gracefully (SIGINT/SIGTERM) so PG connections are released.
 */
async function main() {
  const { app, logger } = createApp();

  try {
    await db.query('SELECT 1');
    logger.info('PostgreSQL connection OK', { database: env.db.name, host: env.db.host });
  } catch (err) {
    logger.error('Could not reach PostgreSQL', { message: err.message, hint: 'Run `npm run db:setup`' });
    process.exitCode = 1;
    return;
  }

  const server = app.listen(env.server.port, () => {
    logger.info(`Bla Bli Blu API listening on http://localhost:${env.server.port}/api`, { env: env.nodeEnv });
  });

  const shutdown = async (signal) => {
    logger.info(`${signal} received, shutting down`);
    server.close(async () => {
      await db.close();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 5000).unref();
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('Fatal startup error', err);
  process.exit(1);
});
