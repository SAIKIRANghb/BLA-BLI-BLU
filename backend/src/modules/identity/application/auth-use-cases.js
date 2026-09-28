import { UseCase } from '../../../shared/application/use-case.js';
import { Result } from '../../../shared/domain/result.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Email } from '../../../shared/domain/identifiers.js';
import { User } from '../domain/index.js';

/**
 * RegisterUser - creates an account (identity invariant: unique email).
 */
export class RegisterUser extends UseCase {
  /** @param {{userRepo:import('../domain/index.js').UserRepository, hasher:object, tokens:object}} deps */
  constructor({ userRepo, hasher, tokens }) {
    super();
    this.userRepo = userRepo;
    this.hasher = hasher;
    this.tokens = tokens;
  }

  async execute({ name, email, password, phone = null }) {
    if (String(password ?? '').length < 8) {
      throw DomainError.validation('Password must be at least 8 characters');
    }
    const normalized = new Email(email);
    const existing = await this.userRepo.findByEmail(normalized.value);
    if (existing) throw DomainError.conflict('An account with this email already exists');

    const user = new User({ name, email: normalized, passwordHash: await this.hasher.hash(password), phone });
    user.validate();
    await this.userRepo.save(user);
    user.record('user.registered', { userId: user.id });

    return {
      user: user.toDto(),
      accessToken: this.tokens.signAccess(user),
      refreshToken: this.tokens.signRefresh(user),
    };
  }
}

/** LoginUser - credential check (Result pattern shown for the "wrong password" branch). */
export class LoginUser extends UseCase {
  constructor({ userRepo, hasher, tokens }) {
    super();
    this.userRepo = userRepo;
    this.hasher = hasher;
    this.tokens = tokens;
  }

  async execute({ email, password }) {
    const user = await this.userRepo.findByEmail(new Email(email).value);
    const ok = user && (await this.hasher.compare(String(password), user.passwordHash));
    if (!ok) {
      // constant-ish message: never reveal whether the email exists
      return Result.fail(DomainError.unauthorized('Invalid email or password'));
    }
    return Result.ok({
      user: user.toDto(),
      accessToken: this.tokens.signAccess(user),
      refreshToken: this.tokens.signRefresh(user),
    });
  }
}

/** RefreshToken - rotates an access token using a refresh token. */
export class RefreshToken extends UseCase {
  constructor({ userRepo, tokens }) {
    super();
    this.userRepo = userRepo;
    this.tokens = tokens;
  }

  async execute({ refreshToken }) {
    let payload;
    try {
      payload = this.tokens.verify(refreshToken, 'refresh');
    } catch {
      throw DomainError.unauthorized('Invalid or expired refresh token');
    }
    const user = await this.userRepo.findById(payload.sub);
    if (!user) throw DomainError.unauthorized('Account no longer exists');
    return { user: user.toDto(), accessToken: this.tokens.signAccess(user) };
  }
}

/** GetProfile - current principal (Actor pattern: uses `input.actor`). */
export class GetProfile extends UseCase {
  constructor({ userRepo }) {
    super();
    this.userRepo = userRepo;
  }

  async execute({ actor }) {
    if (!actor) throw DomainError.unauthorized();
    const user = await this.userRepo.findById(actor.id);
    if (!user) throw DomainError.notFound('Account not found');
    return user.toDto();
  }
}

/** UpdateProfile */
export class UpdateProfile extends UseCase {
  constructor({ userRepo }) {
    super();
    this.userRepo = userRepo;
  }

  async execute({ actor, name, phone }) {
    const user = await this.userRepo.findById(actor.id);
    if (!user) throw DomainError.notFound('Account not found');
    if (name !== undefined) user.name = String(name);
    if (phone !== undefined) user.phone = phone;
    user.validate();
    await this.userRepo.save(user);
    return user.toDto();
  }
}
