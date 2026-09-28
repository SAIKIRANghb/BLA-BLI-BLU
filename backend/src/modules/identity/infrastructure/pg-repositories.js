import { db } from '../../../config/database.js';
import { User, Address, UserRepository, AddressRepository } from '../domain/index.js';
import { DomainError } from '../../../shared/domain/domain-error.js';

/**
 * PgUserRepository - Infrastructure adapter.
 */
export class PgUserRepository extends UserRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  map(row) {
    if (!row) return null;
    return new User({
      id: row.id,
      name: row.name,
      email: row.email,
      passwordHash: row.password_hash,
      phone: row.phone,
      role: row.role,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    });
  }

  async findById(id) {
    return this.map(await this.db.one('SELECT * FROM users WHERE id = $1', [id]));
  }

  async findByEmail(email) {
    return this.map(await this.db.one('SELECT * FROM users WHERE email = $1', [String(email).toLowerCase()]));
  }

  async save(user) {
    user.validate();
    await this.db.query(
      `INSERT INTO users (id, name, email, password_hash, phone, role, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (email) DO UPDATE
         SET name = EXCLUDED.name, phone = EXCLUDED.phone,
             password_hash = EXCLUDED.password_hash, updated_at = EXCLUDED.updated_at`,
      [user.id, user.name, user.email.value, user.passwordHash, user.phone, user.role, user.createdAt, user.updatedAt],
    );
    return user;
  }

  async delete(id) {
    await this.db.query('DELETE FROM users WHERE id = $1', [id]);
  }
}

/** PgAddressRepository */
export class PgAddressRepository extends AddressRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  map(row) {
    return row
      ? new Address({
          id: row.id,
          userId: row.user_id,
          label: row.label,
          line1: row.line1,
          line2: row.line2,
          city: row.city,
          state: row.state,
          pincode: row.pincode,
          phone: row.phone,
          isDefault: row.is_default,
          createdAt: row.created_at,
        })
      : null;
  }

  async listByUser(userId) {
    const rows = await this.db.rows(
      'SELECT * FROM addresses WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
      [userId],
    );
    return rows.map((r) => this.map(r));
  }

  async findById(id) {
    return this.map(await this.db.one('SELECT * FROM addresses WHERE id = $1', [id]));
  }

  async save(address) {
    address.validate();
    await this.db.transaction(async (client) => {
      if (address.isDefault) {
        await client.query('UPDATE addresses SET is_default = FALSE WHERE user_id = $1', [address.userId]);
      }
      await client.query(
        `INSERT INTO addresses (id, user_id, label, line1, line2, city, state, pincode, phone, is_default, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
         ON CONFLICT (id) DO UPDATE SET
           label = EXCLUDED.label, line1 = EXCLUDED.line1, line2 = EXCLUDED.line2,
           city = EXCLUDED.city, state = EXCLUDED.state, pincode = EXCLUDED.pincode,
           phone = EXCLUDED.phone, is_default = EXCLUDED.is_default`,
        [
          address.id,
          address.userId,
          address.label,
          address.line1,
          address.line2,
          address.city,
          address.state,
          address.pincode,
          address.phone,
          address.isDefault,
          address.createdAt,
        ],
      );
    });
    return address;
  }

  async delete(id, userId) {
    const res = await this.db.query('DELETE FROM addresses WHERE id = $1 AND user_id = $2', [id, userId]);
    if (!res.rowCount) throw DomainError.notFound('Address not found');
  }
}
