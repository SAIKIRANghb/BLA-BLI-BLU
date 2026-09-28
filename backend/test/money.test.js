import test from 'node:test';
import assert from 'node:assert/strict';
import { Money } from '../src/shared/domain/money.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

test('Money holds integer paise so prices never drift', () => {
  assert.equal(Money.zero().paise, 0);
  assert.equal(Money.fromRupees(695).paise, 69500);
  assert.equal(Money.fromRupees(1000).rupees, 1000);
  assert.equal(new Money(1000.6).paise, 1001); // always rounds to a whole minor unit
});

test('arithmetic stays whole and never goes negative', () => {
  const a = new Money(69500);
  const b = new Money(4900);
  assert.equal(a.plus(b).paise, 74400);
  assert.equal(a.minus(b).paise, 64600);
  assert.equal(b.minus(a).paise, 0); // clamps instead of going negative
  assert.equal(new Money(999).times(0.5).paise, 500); // rounds, stays an int
});

test('percentOff reproduces the storefront discount badge', () => {
  const sale = Money.fromRupees(700);
  const list = Money.fromRupees(1000);
  assert.equal(sale.percentOff(list), 30);
  assert.equal(list.percentOff(list), 0);
  assert.equal(sale.percentOff(Money.zero()), 0); // no divide-by-zero
});

test('formats like the storefront', () => {
  assert.equal(Money.fromRupees(695).format(), '₹695');
  assert.equal(Money.fromRupees(1000).format(), '₹1,000');
});

test('rejects invalid amounts at construction', () => {
  const invalid = (e) => e instanceof DomainError && e.code === 'VALIDATION_ERROR' && e.status === 422;
  assert.throws(() => new Money(-1), invalid);
  assert.throws(() => new Money(NaN), invalid);
  assert.throws(() => new Money(Infinity), invalid);
});

test('value objects are immutable and compare by value', () => {
  const a = Money.fromRupees(500);
  assert.throws(() => {
    a.paise = 1; // frozen (test modules run in strict mode)
  }, TypeError);

  assert.ok(a.equals(Money.fromRupees(500)));
  assert.ok(!a.equals(Money.fromRupees(501)));
  assert.ok(!a.equals(50000)); // not a value object at all

  assert.ok(a.isGreaterThan(Money.fromRupees(499)));
  assert.ok(!a.isGreaterThan(Money.fromRupees(500)));
});
