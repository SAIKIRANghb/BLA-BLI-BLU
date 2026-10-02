import { AggregateRoot } from '../../../shared/domain/entity.js';
import { Email } from '../../../shared/domain/identifiers.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Repository } from '../../../shared/domain/repository.js';
import { assertGeoPair } from '../../../shared/domain/geo.js';

/**
 * User - aggregate root of the Identity bounded context.
 * Password material never leaves this context (only the hash is persisted).
 */
export class User extends AggregateRoot {
  constructor({ id, name, email, passwordHash, phone = null, role = 'customer', createdAt, updatedAt }) {
    super(id, { createdAt });
    this.name = name;
    this.email = email instanceof Email ? email : new Email(email);
    this.passwordHash = passwordHash;
    this.phone = phone;
    this.role = role;
    this.updatedAt = updatedAt ? new Date(updatedAt) : this.createdAt;
  }

  validate() {
    if (!this.name || this.name.trim().length < 2) throw DomainError.validation('Name must be at least 2 characters');
  }

  /** @param {(plain:string, hash:string)=>Promise<boolean>} compare */
  async matchesPassword(plain, compare) {
    return compare(plain, this.passwordHash);
  }

  changePassword(newHash) {
    this.passwordHash = newHash;
    this.updatedAt = new Date();
    this.record('user.password_changed', { userId: this.id });
  }

  /** Safe projection - never includes passwordHash. */
  toDto() {
    return {
      id: this.id,
      name: this.name,
      email: this.email.value,
      phone: this.phone,
      role: this.role,
      createdAt: this.createdAt.toISOString(),
    };
  }
}

/**
 * Address - value-backed entity belonging to a user (ship-to target).
 */
export class Address extends AggregateRoot {
  constructor({ id, userId, label = 'Home', line1, line2 = '', city, state, pincode, phone, isDefault = false, lat = null, lng = null, createdAt }) {
    super(id, { createdAt });
    this.userId = userId;
    this.label = label;
    this.line1 = line1;
    this.line2 = line2;
    this.city = city;
    this.state = state;
    this.pincode = pincode;
    this.phone = phone;
    this.isDefault = Boolean(isDefault);
    this.lat = lat ?? null;
    this.lng = lng ?? null;
  }

  validate() {
    if (!this.line1 || !this.city || !this.state) throw DomainError.validation('Address line, city and state are required');
    if (!/^\d{6}$/.test(String(this.pincode))) throw DomainError.validation('Pincode must be 6 digits');
    if (!/^\d{10}$/.test(String(this.phone ?? ''))) throw DomainError.validation('Phone must be 10 digits');
    assertGeoPair(this.lat, this.lng);
  }

  toDto() {
    return {
      id: this.id,
      label: this.label,
      line1: this.line1,
      line2: this.line2,
      city: this.city,
      state: this.state,
      pincode: this.pincode,
      phone: this.phone,
      isDefault: this.isDefault,
      lat: this.lat,
      lng: this.lng,
    };
  }
}

export class UserRepository extends Repository {
  /** @param {string} _email @returns {Promise<User|null>} */
  async findByEmail(_email) {
    throw new Error('Not implemented');
  }
}

export class AddressRepository extends Repository {
  /** @param {string} _userId @returns {Promise<Address[]>} */
  async listByUser(_userId) {
    throw new Error('Not implemented');
  }
}
