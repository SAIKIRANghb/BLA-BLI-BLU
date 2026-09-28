import 'dotenv/config';

/**
 * Env - configuration root (Singleton + Factory Method).
 *
 * Reads process.env once, validates it, and exposes a frozen typed object.
 * Every other module receives its config through constructor injection, so
 * nothing reaches into `process.env` outside this file.
 */
function int(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function bool(value, fallback) {
  if (value === undefined || value === '') return fallback;
  return String(value).toLowerCase() === 'true';
}

/** @returns {Readonly<{server:object, db:object, security:object, commerce:object}>} */
export function loadEnv(source = process.env) {
  const nodeEnv = source.NODE_ENV ?? 'development';
  const env = {
    nodeEnv,
    isProduction: nodeEnv === 'production',
    isTest: nodeEnv === 'test',
    server: {
      port: int(source.PORT, 4000),
      corsOrigins: (source.CORS_ORIGINS ?? '*').split(',').map((s) => s.trim()).filter(Boolean),
    },
    db: {
      host: source.DB_HOST ?? '127.0.0.1',
      port: int(source.DB_PORT, 5432),
      name: source.DB_NAME ?? 'blabliblu',
      user: source.DB_USER ?? 'postgres',
      password: source.DB_PASSWORD ?? '',
      poolMax: int(source.DB_POOL_MAX, 10),
    },
    security: {
      jwtSecret: source.JWT_SECRET ?? 'dev-only-secret-change-me',
      accessTtl: source.JWT_ACCESS_TTL ?? '15m',
      refreshTtl: source.JWT_REFRESH_TTL ?? '30d',
      bcryptRounds: int(source.BCRYPT_ROUNDS, 10),
      adminKey: source.ADMIN_KEY ?? 'blabliblu-admin',
    },
    commerce: {
      freeShippingThresholdPaise: int(source.FREE_SHIPPING_THRESHOLD_PAISE, 39900),
      shippingFeePaise: int(source.SHIPPING_FEE_PAISE, 4900),
      codAvailable: bool(source.COD_AVAILABLE, true),
    },
  };
  return Object.freeze(env);
}

/** Singleton accessor */
export const env = loadEnv();
