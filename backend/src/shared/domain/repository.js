/**
 * Repository (abstract) - DDD persistence contract + base helpers.
 *
 * Each module extends this for its own aggregate. Implementations live in
 * `<module>/infrastructure/*-repository.js` (Dependency Inversion: the module
 * depends on this contract, never on pg).
 */
export class Repository {
  /**
   * @param {string} _id
   * @returns {Promise<import('../shared/domain/entity.js').Entity|null>}
   */
  async findById(_id) {
    throw new Error('Not implemented');
  }

  /** @returns {Promise<void>} */
  async save(_entity) {
    throw new Error('Not implemented');
  }

  /** @returns {Promise<void>} */
  async delete(_id) {
    throw new Error('Not implemented');
  }
}

/**
 * Spec (Specification pattern) - composable query predicates.
 * Repository implementations translate `and/or` trees into SQL WHERE clauses.
 */
export class Spec {
  static TRUE = new Spec('TRUE');
  static FALSE = new Spec('FALSE');

  constructor(where = 'TRUE', params = []) {
    this.where = where;
    this.params = params;
  }

  and(other) {
    return new Spec(`(${this.where}) AND (${other.where})`, [...this.params, ...other.params]);
  }

  or(other) {
    return new Spec(`(${this.where}) OR (${other.where})`, [...this.params, ...other.params]);
  }

  offset(n) {
    return new Spec(this.where, this.params, { offset: n });
  }
}
