import test from 'node:test';
import assert from 'node:assert/strict';
import { Result } from '../src/shared/domain/result.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

test('ok results expose their value and flip the railway switches', () => {
  const r = Result.ok(42);
  assert.ok(r.isOk());
  assert.ok(!r.isFail());
  assert.equal(r.value, 42);
  assert.equal(r.map((v) => v * 2).value, 84);
  assert.equal(r.chain((v) => Result.ok(v + 1)).value, 43);
  assert.equal(r.unwrapOr(0), 42);
  assert.throws(() => r.error, /no error/);
  assert.ok(Result.ok().isOk()); // no payload needed
});

test('failures wrap anything into a DomainError and short-circuit', () => {
  const r = Result.fail('boom');
  assert.ok(r.isFail());
  assert.ok(!r.isOk());
  assert.equal(r.error.message, 'boom');
  assert.equal(r.error.code, 'DOMAIN_ERROR');
  assert.equal(r.error.status, 400);
  assert.throws(() => r.value, /no value/);
  assert.equal(r.unwrapOr('fallback'), 'fallback');

  // map/chain pass the failure through untouched
  assert.equal(r.map((v) => v + 1), r);
  assert.equal(r.chain(() => Result.ok(1)), r);

  assert.equal(Result.fail(new Error('from an Error')).error.message, 'from an Error');
});

test('an existing DomainError keeps its HTTP mapping', () => {
  const r = Result.fail(DomainError.notFound('Cart item not found'));
  assert.equal(r.error.message, 'Cart item not found');
  assert.equal(r.error.code, 'NOT_FOUND');
  assert.equal(r.error.status, 404);
});

test('DomainError carries the codes the HTTP layer maps', () => {
  assert.equal(DomainError.validation('x').status, 422);
  assert.equal(DomainError.validation('x').code, 'VALIDATION_ERROR');
  assert.equal(DomainError.unauthorized().status, 401);
  assert.equal(DomainError.unauthorized().code, 'UNAUTHORIZED');
  assert.equal(DomainError.forbidden().status, 403);
  assert.equal(DomainError.conflict().status, 409);
  assert.deepEqual(DomainError.validation('x', { field: 'qty' }).details, { field: 'qty' });
});
