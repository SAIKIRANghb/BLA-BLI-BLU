/**
 * UseCase (abstract) - application layer contract.
 *
 * A use case orchestrates repositories/domain objects and returns a plain DTO.
 * It never leaks entities to the presentation layer (by convention: `execute`
 * returns whatever `toDto` mappers produced).
 */
export class UseCase {
  /**
   * @param {object} input validated DTO/command
   * @returns {Promise<any>}
   */
  async execute(_input) {
    throw new Error(`UseCase.execute not implemented by ${this.constructor.name}`);
  }
}

/**
 * Query use cases are read-only: they may bypass aggregates and hit read models
 * directly, but still return DTOs.
 */
export class Query extends UseCase {}
