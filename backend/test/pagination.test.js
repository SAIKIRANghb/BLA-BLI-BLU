import test from 'node:test';
import assert from 'node:assert/strict';
import { PageRequest, PageResult } from '../src/shared/domain/pagination.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

test('PageRequest applies storefront defaults and computes the offset', () => {
  const first = new PageRequest();
  assert.equal(first.page, 1);
  assert.equal(first.limit, 24);
  assert.equal(first.sort, 'featured');
  assert.equal(first.offset, 0);

  assert.equal(new PageRequest({ page: 3, limit: 24 }).offset, 48);
  assert.equal(new PageRequest({ page: 2, limit: 10 }).offset, 10);
});

test('PageRequest validates the bounds every list endpoint relies on', () => {
  const invalid = (re) => (e) => e instanceof DomainError && e.code === 'VALIDATION_ERROR' && re.test(e.message);
  assert.throws(() => new PageRequest({ page: 0 }), invalid(/page must be >= 1/));
  assert.throws(() => new PageRequest({ page: 1.5 }), invalid(/page must be >= 1/));
  assert.throws(() => new PageRequest({ limit: 0 }), invalid(/between 1 and 100/));
  assert.throws(() => new PageRequest({ limit: 101 }), invalid(/between 1 and 100/));
  assert.doesNotThrow(() => new PageRequest({ limit: 100 }));

  assert.throws(
    () => new PageRequest({ sort: 'cheapest', allowedSorts: ['featured', 'newest'] }),
    invalid(/sort must be one of: featured, newest/),
  );
  assert.doesNotThrow(() => new PageRequest({ sort: 'newest', allowedSorts: ['featured', 'newest'] }));
});

test('PageRequest trims the free-text query', () => {
  assert.equal(new PageRequest({ q: '  oud  ' }).q, 'oud');
  assert.equal(new PageRequest({ q: null }).q, '');
});

test('PageResult describes the window and the navigation edges', () => {
  const pageOne = new PageResult(['a', 'b'], 50, new PageRequest({ page: 1, limit: 24 }));
  assert.equal(pageOne.totalPages, 3);
  assert.equal(pageOne.hasNext, true);
  assert.equal(pageOne.hasPrev, false);

  const last = new PageResult(['j'], 50, new PageRequest({ page: 3, limit: 24 }));
  assert.equal(last.hasNext, false);
  assert.equal(last.hasPrev, true);
  assert.equal(last.limit, 24);
  assert.equal(last.total, 50);

  // an empty result set still renders as one (empty) page
  const empty = new PageResult([], 0, new PageRequest({ page: 1, limit: 24 }));
  assert.equal(empty.totalPages, 1);
  assert.equal(empty.hasNext, false);
  assert.equal(empty.hasPrev, false);
});
