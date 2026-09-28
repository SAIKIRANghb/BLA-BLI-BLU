/**
 * DomainError - the single failure type the domain layer is allowed to throw.
 * The HTTP layer maps it to a status code (see presentation/http/error-handler.js).
 */
export class DomainError extends Error {
  /**
   * @param {string} message  human readable message safe to return to clients
   * @param {object} [options]
   * @param {string} [options.code]   machine readable code, e.g. "OUT_OF_STOCK"
   * @param {number} [options.status] suggested HTTP status
   * @param {object} [options.details] extra structured context
   */
  constructor(message, { code = 'DOMAIN_ERROR', status = 400, details = undefined } = {}) {
    super(message);
    this.name = 'DomainError';
    this.code = code;
    this.status = status;
    this.details = details;
  }

  static notFound(message = 'Resource not found', details) {
    return new DomainError(message, { code: 'NOT_FOUND', status: 404, details });
  }

  static unauthorized(message = 'Unauthorized', details) {
    return new DomainError(message, { code: 'UNAUTHORIZED', status: 401, details });
  }

  static forbidden(message = 'Forbidden', details) {
    return new DomainError(message, { code: 'FORBIDDEN', status: 403, details });
  }

  static conflict(message = 'Conflict', details) {
    return new DomainError(message, { code: 'CONFLICT', status: 409, details });
  }

  static validation(message = 'Validation failed', details) {
    return new DomainError(message, { code: 'VALIDATION_ERROR', status: 422, details });
  }
}
