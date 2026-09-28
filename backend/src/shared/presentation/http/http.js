import { DomainError } from '../../domain/domain-error.js';

/** Wraps an async route handler so rejected promises reach the error middleware. */
export const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/**
 * Respond - tiny presentational helper so controllers never hand-roll JSON.
 */
export const respond = {
  ok(res, data, meta = undefined) {
    const body = meta === undefined ? { success: true, data } : { success: true, data, meta };
    return res.json(body);
  },
  created(res, data, meta = undefined) {
    const body = meta === undefined ? { success: true, data } : { success: true, data, meta };
    return res.status(201).json(body);
  },
  noContent(res) {
    return res.status(204).end();
  },
  fail(res, status, message, code = 'ERROR', details = undefined) {
    return res.status(status).json({ success: false, error: { code, message, details } });
  },
};

/**
 * Controller (abstract) - presentation base class.
 *
 * Controllers only: validate input (Zod schema on the route), call a use case,
 * and shape the response. No SQL, no domain rules.
 */
export class Controller {
  constructor(useCase) {
    this.useCase = useCase;
  }

  async handle(req, res) {
    const output = await this.useCase.execute(this.input(req));
    return this.result(res, output, req);
  }

  /** @returns {object} validated input for the use case */
  input(req) {
    return { ...req.params, ...req.query, ...req.body, actor: req.user };
  }

  /** @returns {any} HTTP payload */
  result(res, output, _req) {
    return respond.ok(res, output);
  }
}

/**
 * Router (abstract) - declarative route table (Template Method).
 *
 * Each route entry = { method, path, [schema], handler } and gets wired with
 * validation + async handling automatically.
 */
export class Router {
  constructor() {
    this.routes = [];
  }

  /**
   * @param {'get'|'post'|'put'|'patch'|'delete'} method
   * @param {string} path
   * @param {object} options { schema?, middleware?, handler }
   */
  route(method, path, options) {
    this.routes.push({ method, path, ...options });
    return this;
  }

  get(path, options) {
    return this.route('get', path, options);
  }

  post(path, options) {
    return this.route('post', path, options);
  }

  put(path, options) {
    return this.route('put', path, options);
  }

  patch(path, options) {
    return this.route('patch', path, options);
  }

  delete(path, options) {
    return this.route('delete', path, options);
  }

  /** @returns {Array<{method:string,path:string}>} */
  list() {
    return this.routes.map(({ method, path }) => ({ method, path }));
  }
}

/**
 * Converts a DomainError (or anything else) into a JSON error envelope.
 */
export function toHttpError(err) {
  if (err instanceof DomainError) {
    return { status: err.status, code: err.code, message: err.message, details: err.details };
  }
  if (err?.name === 'ZodError') {
    return {
      status: 422,
      code: 'VALIDATION_ERROR',
      message: 'Validation failed',
      details: err.issues?.map((i) => ({ path: i.path.join('.'), message: i.message })),
    };
  }
  if (err?.status) {
    return { status: err.status, code: err.code ?? 'ERROR', message: err.message, details: err.details };
  }
  return { status: 500, code: 'INTERNAL_ERROR', message: 'Something went wrong' };
}
