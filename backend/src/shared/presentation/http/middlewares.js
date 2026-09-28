import { asyncHandler, respond, toHttpError } from './http.js';
import { DomainError } from '../../domain/domain-error.js';

/**
 * Middlewares for the HTTP presentation layer.
 * Kept dependency free so they can be reused by every module router.
 */

/** 404 for unknown routes. */
export function notFound(req, res) {
  respond.fail(res, 404, `Route not found: ${req.method} ${req.originalUrl}`, 'NOT_FOUND');
}

/**
 * Terminal error translator: DomainError / ZodError / JWT errors -> JSON.
 * (`Respond` + Adapter roles are combined in one place on purpose.)
 */
export function errorHandler(logger) {
  return (err, req, res, _next) => {
    const { status, code, message, details } = toHttpError(err);
    if (status >= 500) logger?.error(message, { path: req.originalUrl, stack: err.stack });
    else logger?.debug(message, { path: req.originalUrl, code });
    respond.fail(res, status, message, code, details);
  };
}

/** Access log (decorator around the request pipeline). */
export function requestLogger(logger) {
  return (req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
      const ms = Date.now() - start;
      if (req.originalUrl.startsWith('/api')) {
        logger.info(`${req.method} ${req.originalUrl} ${res.statusCode}`, { ms });
      }
    });
    next();
  };
}

/**
 * validate - schema-first request validation (Zod). Builds a pipe that checks
 * params, query and body separately.
 *
 * @param {{params?:import('zod').ZodTypeAny, query?:import('zod').ZodTypeAny, body?:import('zod').ZodTypeAny}} schemas
 */
export function validate(schemas = {}) {
  return (req, _res, next) => {
    try {
      for (const key of ['params', 'query', 'body']) {
        const schema = schemas[key];
        if (!schema) continue;
        const parsed = schema.parse(req[key]);
        // read-only replace keeps Express internals intact
        req[key] = parsed;
      }
      next();
    } catch (err) {
      next(err);
    }
  };
}

/**
 * requireAuth - Decorator around handlers that need a principal.
 * Attaches `req.user = { id, email, name }` after verifying the access token.
 */
export function requireAuth(tokenService) {
  return (req, _res, next) => {
    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) {
      return next(DomainError.unauthorized('Missing bearer token'));
    }
    try {
      const payload = tokenService.verify(token, 'access');
      req.user = { id: payload.sub, email: payload.email, name: payload.name };
      next();
    } catch (err) {
      next(DomainError.unauthorized(err.message ?? 'Invalid token'));
    }
  };
}

/** Attaches the principal when a token is present, otherwise continues anonymously. */
export function optionalAuth(tokenService) {
  return (req, _res, next) => {
    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme === 'Bearer' && token) {
      try {
        const payload = tokenService.verify(token, 'access');
        req.user = { id: payload.sub, email: payload.email, name: payload.name };
      } catch {
        /* anonymous */
      }
    }
    next();
  };
}

/**
 * compose - combines middlewares into one (Composite pattern).
 * @param {...Function} middlewares
 */
export const compose =
  (...middlewares) =>
  (req, res, next) => {
    let index = 0;
    const run = (i) => {
      if (i >= middlewares.length) return next();
      middlewares[i](req, res, (err) => (err ? next(err) : run(i + 1)));
    };
    run(index);
  };

export { asyncHandler };
