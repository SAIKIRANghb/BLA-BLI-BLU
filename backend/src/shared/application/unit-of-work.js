/**
 * UnitOfWork - application port for transactional use cases (Port & Adapter).
 *
 * `run` gives a use case a bundle of repositories bound to ONE transaction, so
 * multi-aggregate writes stay atomic. The pg adapter wires it in
 * `shared/infrastructure/postgres-unit-of-work.js`.
 */
export class UnitOfWork {
  /**
   * @template T
   * @param {(repos:object)=>Promise<T>} _fn
   * @returns {Promise<T>}
   */
  async run(_fn) {
    throw new Error('UnitOfWork.run not implemented');
  }
}
