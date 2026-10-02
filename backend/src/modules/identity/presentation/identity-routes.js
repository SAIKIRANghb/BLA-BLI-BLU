import { z } from 'zod';
import { Router, respond, asyncHandler } from '../../../shared/presentation/http/http.js';
import { bindRoutes } from '../../../shared/presentation/http/route-binder.js';
import { requireAuth } from '../../../shared/presentation/http/middlewares.js';
import { BcryptPasswordHasher, TokenService } from '../../../shared/infrastructure/security.js';
import { RegisterUser, LoginUser, RefreshToken, GetProfile, UpdateProfile } from '../application/auth-use-cases.js';
import { ListAddresses, SaveAddress, DeleteAddress } from '../application/address-use-cases.js';
import { PgUserRepository, PgAddressRepository } from '../infrastructure/pg-repositories.js';
import { env } from '../../../config/env.js';

/** Identity contract schemas (Zod = single source of truth for validation). */
export const identitySchemas = {
  register: z.object({
    name: z.string().min(2).max(60),
    email: z.string().email(),
    password: z.string().min(8).max(72),
    phone: z
      .string()
      .regex(/^\d{10}$/)
      .optional()
      .nullable(),
  }),
  login: z.object({ email: z.string().email(), password: z.string().min(1) }),
  refresh: z.object({ refreshToken: z.string().min(20) }),
  updateProfile: z.object({
    name: z.string().min(2).max(60).optional(),
    phone: z
      .string()
      .regex(/^\d{10}$/)
      .optional()
      .nullable(),
  }),
  addressId: z.object({ id: z.string().uuid() }),
  address: z.object({
    id: z.string().uuid().optional(),
    label: z.string().max(30).optional(),
    line1: z.string().min(3).max(120),
    line2: z.string().max(120).optional(),
    city: z.string().min(2).max(60),
    state: z.string().min(2).max(60),
    pincode: z.string().regex(/^\d{6}$/),
    phone: z.string().regex(/^\d{10}$/),
    isDefault: z.boolean().optional(),
    // Optional map pin picked on the address map screen.
    lat: z.number().min(-90).max(90).nullable().optional(),
    lng: z.number().min(-180).max(180).nullable().optional(),
  }),
};

/**
 * IdentityController - thin presentation facade over auth/address use cases.
 */
export class IdentityController {
  constructor(useCases) {
    this.register = useCases.register;
    this.login = useCases.login;
    this.refresh = useCases.refresh;
    this.getProfile = useCases.getProfile;
    this.updateProfile = useCases.updateProfile;
    this.listAddresses = useCases.listAddresses;
    this.saveAddress = useCases.saveAddress;
    this.deleteAddress = useCases.deleteAddress;
  }

  handleRegister = asyncHandler(async (req, res) => respond.created(res, await this.register.execute(req.body)));

  handleLogin = asyncHandler(async (req, res) => {
    const result = await this.login.execute(req.body);
    if (result.isFail()) throw result.error; // DomainError -> errorHandler mapping
    respond.ok(res, result.value);
  });

  handleRefresh = asyncHandler(async (req, res) => respond.ok(res, await this.refresh.execute(req.body)));

  handleMe = asyncHandler(async (req, res) => respond.ok(res, await this.getProfile.execute({ actor: req.user })));

  handleUpdateMe = asyncHandler(async (req, res) =>
    respond.ok(res, await this.updateProfile.execute({ actor: req.user, ...req.body })),
  );

  handleListAddresses = asyncHandler(async (req, res) => respond.ok(res, await this.listAddresses.execute({ actor: req.user })));

  handleSaveAddress = asyncHandler(async (req, res) =>
    respond.ok(res, await this.saveAddress.execute({ actor: req.user, ...req.body })),
  );

  handleDeleteAddress = asyncHandler(async (req, res) =>
    respond.ok(res, await this.deleteAddress.execute({ actor: req.user, id: req.params.id })),
  );
}

/**
 * createIdentityRouter - composition root for the identity context.
 * Dependencies are injected (DIP); defaults wire the pg adapters.
 *
 * @param {object} [overrides]
 */
export function createIdentityRouter(overrides = {}) {
  const userRepo = overrides.userRepo ?? new PgUserRepository();
  const addressRepo = overrides.addressRepo ?? new PgAddressRepository();
  const hasher = overrides.hasher ?? new BcryptPasswordHasher(env.security.bcryptRounds);
  const tokens =
    overrides.tokens ??
    new TokenService({
      secret: env.security.jwtSecret,
      accessTtl: env.security.accessTtl,
      refreshTtl: env.security.refreshTtl,
    });

  const controller = new IdentityController({
    register: new RegisterUser({ userRepo, hasher, tokens }),
    login: new LoginUser({ userRepo, hasher, tokens }),
    refresh: new RefreshToken({ userRepo, tokens }),
    getProfile: new GetProfile({ userRepo }),
    updateProfile: new UpdateProfile({ userRepo }),
    listAddresses: new ListAddresses({ addressRepo }),
    saveAddress: new SaveAddress({ addressRepo }),
    deleteAddress: new DeleteAddress({ addressRepo }),
  });

  const auth = requireAuth(tokens);

  const table = new Router()
    .post('/auth/register', { schemas: { body: identitySchemas.register }, handler: controller.handleRegister })
    .post('/auth/login', { schemas: { body: identitySchemas.login }, handler: controller.handleLogin })
    .post('/auth/refresh', { schemas: { body: identitySchemas.refresh }, handler: controller.handleRefresh })
    .get('/auth/me', { middleware: [auth], handler: controller.handleMe })
    .put('/auth/me', { middleware: [auth], schemas: { body: identitySchemas.updateProfile }, handler: controller.handleUpdateMe })
    .get('/addresses', { middleware: [auth], handler: controller.handleListAddresses })
    .post('/addresses', { middleware: [auth], schemas: { body: identitySchemas.address }, handler: controller.handleSaveAddress })
    .delete('/addresses/:id', {
      middleware: [auth],
      schemas: { params: identitySchemas.addressId },
      handler: controller.handleDeleteAddress,
    });

  return { router: bindRoutes(table), tokens };
}
