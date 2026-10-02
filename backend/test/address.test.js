import test from 'node:test';
import assert from 'node:assert/strict';
import { Address } from '../src/modules/identity/domain/index.js';
import { SaveAddress } from '../src/modules/identity/application/address-use-cases.js';
import { ShippingAddress } from '../src/modules/ordering/domain/index.js';
import { assertGeoPair } from '../src/shared/domain/geo.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

const base = {
  label: 'Home',
  line1: '221B Baker Street',
  city: 'Gurugram',
  state: 'Haryana',
  pincode: '122002',
  phone: '9876543210',
};

async function caught(input) {
  try {
    await (typeof input === 'function' ? input() : input);
    return null;
  } catch (err) {
    return err;
  }
}

async function assertValidation(input) {
  const err = await caught(input);
  assert.ok(err instanceof DomainError, `expected a DomainError, got: ${err?.message ?? err}`);
  assert.equal(err.status, 422);
  assert.equal(err.code, 'VALIDATION_ERROR');
  return err;
}

/** Minimal in-memory stand-in for PgAddressRepository. */
class FakeAddressRepo {
  constructor() {
    this.items = [];
  }

  async listByUser() {
    return this.items;
  }

  async findById(id) {
    return this.items.find((a) => a.id === id) ?? null;
  }

  async save(address) {
    address.validate();
    const i = this.items.findIndex((a) => a.id === address.id);
    if (i >= 0) this.items[i] = address;
    else this.items.push(address);
    return address;
  }
}

test('assertGeoPair allows none-or-both only', async () => {
  assertGeoPair(null, null);
  assertGeoPair(undefined, undefined);
  assertGeoPair(28.6139, 77.209);
  await assertValidation(() => assertGeoPair(28.6, null));
  await assertValidation(() => assertGeoPair(null, 77.2));
  await assertValidation(() => assertGeoPair(91, 77.2));
  await assertValidation(() => assertGeoPair(28.6, 181));
  await assertValidation(() => assertGeoPair('north', 77.2));
});

test('address keeps working without any pin', () => {
  const a = new Address({ userId: 'u1', ...base });
  a.validate();
  assert.equal(a.lat, null);
  assert.equal(a.lng, null);
  const dto = a.toDto();
  assert.equal(dto.lat, null);
  assert.equal(dto.lng, null);
});

test('address stores and echoes a picked pin', () => {
  const a = new Address({ userId: 'u1', ...base, lat: 28.6139, lng: 77.209 });
  a.validate();
  assert.equal(a.toDto().lat, 28.6139);
  assert.equal(a.toDto().lng, 77.209);
});

test('SaveAddress creates with a pin and keeps it across null updates', async () => {
  const repo = new FakeAddressRepo();
  const save = new SaveAddress({ addressRepo: repo });
  const actor = { id: 'user-1' };

  const created = await save.execute({ actor, ...base, lat: 28.6139, lng: 77.209 });
  assert.equal(created.lat, 28.6139);
  assert.equal(created.lng, 77.209);

  // A form submission without a pin must not wipe the stored coordinates.
  const updated = await save.execute({ actor, id: created.id, ...base, lat: null, lng: null });
  assert.equal(updated.lat, 28.6139);
  assert.equal(updated.lng, 77.209);

  // Re-pinning moves the coordinates.
  const moved = await save.execute({ actor, id: created.id, ...base, lat: 28.5494, lng: 77.2001 });
  assert.equal(moved.lat, 28.5494);
  assert.equal(moved.lng, 77.2001);
});

test('SaveAddress rejects a half-set pin', async () => {
  const repo = new FakeAddressRepo();
  const save = new SaveAddress({ addressRepo: repo });
  await assertValidation(save.execute({ actor: { id: 'user-1' }, ...base, lat: 28.6 }));
  assert.equal(repo.items.length, 0);
});

test('shipping snapshot carries the pin through toDto and rejects bad pairs', () => {
  const withPin = new ShippingAddress({ name: 'Asha', ...base, lat: 28.6139, lng: 77.209 });
  assert.equal(withPin.toDto().lat, 28.6139);
  assert.equal(withPin.toDto().lng, 77.209);

  const noPin = new ShippingAddress({ name: 'Asha', ...base });
  assert.equal(noPin.toDto().lat, null);
  assert.equal(noPin.toDto().lng, null);

  // JSON round-trip as persisted in the orders.address JSONB column.
  const revived = new ShippingAddress(JSON.parse(JSON.stringify(withPin.toDto())));
  assert.equal(revived.lat, 28.6139);

  assert.throws(() => new ShippingAddress({ name: 'Asha', ...base, lat: 28.6 }), DomainError);
  assert.throws(() => new ShippingAddress({ name: 'Asha', ...base, lat: 1234, lng: 77 }), DomainError);
});
