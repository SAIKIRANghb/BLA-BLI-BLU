import { db } from '../../config/database.js';
import { UnitOfWork } from '../application/unit-of-work.js';

/**
 * PostgresUnitOfWork - Adapter around `db.transaction`.
 *
 * @example
 *   await uow.run(async ({ orders, carts }) => {
 *     await orders.save(order);
 *     await carts.delete(cart.id);
 *   });
 */
export class PostgresUnitOfWork extends UnitOfWork {
  /**
   * @param {{run:(fn:Function)=>Promise<any>}} [database]
   * @param {(client:object)=>object} [repoProvider] builds repository adapters bound to `client`
   */
  constructor(database = db, repoProvider = (client) => ({ client })) {
    super();
    this.database = database;
    this.repoProvider = repoProvider;
  }

  run(fn) {
    return this.database.transaction(async (client) => fn(this.repoProvider(client)));
  }
}
