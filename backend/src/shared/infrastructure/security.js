import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

/**
 * PasswordHasher - Strategy interface. `bcrypt` is one implementation; swap in
 * argon2 without touching the identity module.
 */
export class PasswordHasher {
  async hash(_plain) {
    throw new Error('Not implemented');
  }

  async compare(_plain, _hash) {
    throw new Error('Not implemented');
  }
}

export class BcryptPasswordHasher extends PasswordHasher {
  /** @param {number} rounds */
  constructor(rounds = 10) {
    super();
    this.rounds = rounds;
  }

  async hash(plain) {
    return bcrypt.hash(plain, this.rounds);
  }

  async compare(plain, hash) {
    return bcrypt.compare(plain, hash);
  }
}

/**
 * TokenService - issues/verifies signed access + refresh tokens (Adapter
 * around jsonwebtoken so the domain never depends on the library).
 */
export class TokenService {
  /**
   * @param {object} opts
   * @param {string} opts.secret
   * @param {string} [opts.accessTtl]
   * @param {string} [opts.refreshTtl]
   */
  constructor({ secret, accessTtl = '15m', refreshTtl = '30d' }) {
    if (!secret) throw new Error('JWT_SECRET is required');
    this.secret = secret;
    this.accessTtl = accessTtl;
    this.refreshTtl = refreshTtl;
  }

  /**
   * Domain aggregates expose `email` as an `Email` value object; the token
   * payload is a plain claim bag, so unwrap it here (single place to keep the
   * wire format primitive-only).
   * @param {{id:string,email:any,name?:string}} user
   */
  static claims(user) {
    return {
      sub: String(user.id),
      email: typeof user.email === 'string' ? user.email : (user.email?.value ?? ''),
      name: user.name ?? '',
    };
  }

  signAccess(user) {
    return jwt.sign({ ...TokenService.claims(user), typ: 'access' }, this.secret, {
      expiresIn: this.accessTtl,
    });
  }

  signRefresh(user) {
    return jwt.sign({ ...TokenService.claims(user), typ: 'refresh' }, this.secret, {
      expiresIn: this.refreshTtl,
    });
  }

  /** @returns {{sub:string,email:string,typ:string}} */
  verify(token, expectedType = 'access') {
    const payload = jwt.verify(token, this.secret);
    if (payload.typ !== expectedType) {
      const err = new Error('Invalid token type');
      err.status = 401;
      throw err;
    }
    return payload;
  }
}
