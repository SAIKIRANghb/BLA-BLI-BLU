import test from 'node:test';
import assert from 'node:assert/strict';
import { RiderPosition, TRACKING_LIMITS, TrackingRepository } from '../src/modules/tracking/domain/index.js';
import { ReportPosition, GetTrack, ListActiveDeliveries } from '../src/modules/tracking/application/tracking-service.js';
import { trackingSchemas, requireRider } from '../src/modules/tracking/presentation/tracking-routes.js';
import { Order, OrderStatus } from '../src/modules/ordering/domain/index.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

const ORDER_ID = '2c9f1b70-1e6a-4a1e-9e1b-000000000001';
const OTHER_ID = '2c9f1b70-1e6a-4a1e-9e1b-000000000002';

/** Accepts a thunk (sync throws) or a promise; resolves to the thrown error or null. */
async function caught(input) {
  try {
    await (typeof input === 'function' ? input() : input);
    return null;
  } catch (err) {
    return err;
  }
}

/** Always `await` this - asserts the failure is a DomainError with status/code. */
async function assertDomainError(input, status, code) {
  const err = input instanceof Error ? input : await caught(input);
  assert.ok(err instanceof DomainError, `expected a DomainError, got: ${err?.message ?? err}`);
  assert.equal(err.status, status, `expected status ${status}, got ${err.status} (${err.code})`);
  if (code) assert.equal(err.code, code);
  return err;
}

/** In-memory TrackingRepository double; records every call. */
class FakeTrackingRepo {
  constructor() {
    this.saved = [];
    this.trail = [];
    this.queue = [];
    this.calls = [];
  }

  async save(position) {
    this.calls.push(['save', position]);
    this.saved.push(position);
    return undefined;
  }

  async listTrail(orderId, limit) {
    this.calls.push(['listTrail', orderId, limit]);
    return this.trail.slice(0, limit);
  }

  async listActiveDeliveries(query) {
    this.calls.push(['listActiveDeliveries', query]);
    return this.queue.slice(0, query.limit);
  }
}

/** In-memory OrderRepository double. */
class FakeOrderRepo {
  constructor(orders = []) {
    this.orders = orders;
    this.calls = [];
  }

  async findById(id) {
    this.calls.push(id);
    return this.orders.find((o) => o.id === id) ?? null;
  }
}

/** Minimal Order aggregate for the use cases (items only matter to validate()). */
function makeOrder({ id = ORDER_ID, userId = 'user-1', email = 'owner@example.com', status = 'shipped' } = {}) {
  return new Order({
    id,
    orderNumber: 'BBL-20251001-1234',
    userId,
    email,
    phone: '9876543210',
    status,
    paymentMethod: 'cod',
    subtotal: 49900,
    discount: 0,
    shipping: 4900,
    total: 54800,
    address: {
      name: 'Test Owner',
      phone: '9876543210',
      line1: '221B Baker Street',
      city: 'Gurugram',
      state: 'Haryana',
      pincode: '122002',
      lat: 28.6139,
      lng: 77.209,
    },
    items: [
      {
        id: 'item-1',
        handle: 'love-drunk-best-unisex-perfume',
        title: 'Love Drunk',
        unitPrice: 49900,
        quantity: 1,
      },
    ],
    events: [],
  });
}

// ───────────────────────────────── domain ────────────────────────────────────

test('RiderPosition builds a valid fix and defaults recordedAt to now', () => {
  const before = Date.now();
  const fix = new RiderPosition({ orderId: ORDER_ID, lat: 28.6139, lng: 77.209, accuracyM: 8, speedMps: 6.5, headingDeg: 270 });
  const after = Date.now();
  assert.equal(fix.orderId, ORDER_ID);
  assert.equal(fix.lat, 28.6139);
  assert.equal(fix.lng, 77.209);
  assert.equal(fix.accuracyM, 8);
  assert.equal(fix.speedMps, 6.5);
  assert.equal(fix.headingDeg, 270);
  assert.ok(fix.id.length === 36, 'mints a uuid');
  assert.ok(fix.recordedAt.getTime() >= before && fix.recordedAt.getTime() <= after);
  assert.equal(fix.receivedAt.getTime(), fix.createdAt.getTime());
});

test('RiderPosition requires orderId, lat and lng', async () => {
  await assertDomainError(() => new RiderPosition({ lat: 28.6, lng: 77.2 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ orderId: ORDER_ID, lng: 77.2 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ orderId: ORDER_ID, lat: 28.6 }), 422, 'VALIDATION_ERROR');
});

test('RiderPosition reuses the shared WGS84 geo ranges', async () => {
  await assertDomainError(() => new RiderPosition({ orderId: ORDER_ID, lat: 91, lng: 77.2 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ orderId: ORDER_ID, lat: 28.6, lng: -181 }), 422, 'VALIDATION_ERROR');
});

test('RiderPosition enforces accuracy/speed/heading ranges', async () => {
  const base = { orderId: ORDER_ID, lat: 28.6, lng: 77.2 };
  // bounds are inclusive
  new RiderPosition({ ...base, accuracyM: 0 });
  new RiderPosition({ ...base, accuracyM: TRACKING_LIMITS.maxAccuracyM });
  new RiderPosition({ ...base, speedMps: 0 });
  new RiderPosition({ ...base, speedMps: TRACKING_LIMITS.maxSpeedMps });
  new RiderPosition({ ...base, headingDeg: 0 });
  new RiderPosition({ ...base, headingDeg: 360 });
  // and everything outside is rejected
  await assertDomainError(() => new RiderPosition({ ...base, accuracyM: -1 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ ...base, accuracyM: TRACKING_LIMITS.maxAccuracyM + 1 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ ...base, speedMps: -0.5 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ ...base, speedMps: TRACKING_LIMITS.maxSpeedMps + 1 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ ...base, headingDeg: 361 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(() => new RiderPosition({ ...base, headingDeg: -1 }), 422, 'VALIDATION_ERROR');
});

test('RiderPosition accepts optional fix extras as null when absent', () => {
  const fix = new RiderPosition({ orderId: ORDER_ID, lat: 28.6, lng: 77.2 });
  assert.equal(fix.accuracyM, null);
  assert.equal(fix.speedMps, null);
  assert.equal(fix.headingDeg, null);
  const dto = fix.toDto();
  assert.equal(dto.accuracyM, null);
  assert.equal(dto.speedMps, null);
  assert.equal(dto.headingDeg, null);
});

test('RiderPosition rejects an unparseable recordedAt', async () => {
  await assertDomainError(
    () => new RiderPosition({ orderId: ORDER_ID, lat: 28.6, lng: 77.2, recordedAt: 'not-a-date' }),
    422,
    'VALIDATION_ERROR',
  );
});

test('RiderPosition rejects a device clock running too far ahead', async () => {
  const future = new Date(Date.now() + (TRACKING_LIMITS.maxFutureSkewSec + 60) * 1000);
  await assertDomainError(
    () => new RiderPosition({ orderId: ORDER_ID, lat: 28.6, lng: 77.2, recordedAt: future }),
    422,
    'VALIDATION_ERROR',
  );
  // small skew is tolerated (NTP drift)
  const ok = new RiderPosition({
    orderId: ORDER_ID,
    lat: 28.6,
    lng: 77.2,
    recordedAt: new Date(Date.now() + 30 * 1000),
  });
  assert.ok(ok.recordedAt);
});

test('RiderPosition.toDto emits ISO timestamps and every wire field', () => {
  const recordedAt = new Date('2025-10-01T10:00:00.000Z');
  const fix = new RiderPosition({
    id: '9f4a2d2e-0b1c-4d5e-8f70-000000000009',
    orderId: ORDER_ID,
    lat: 28.6139,
    lng: 77.209,
    accuracyM: 5,
    speedMps: 3.2,
    headingDeg: 90,
    recordedAt,
    receivedAt: new Date('2025-10-01T10:00:01.000Z'),
  });
  const dto = fix.toDto();
  assert.deepEqual(Object.keys(dto).sort(), [
    'accuracyM',
    'headingDeg',
    'id',
    'lat',
    'lng',
    'orderId',
    'receivedAt',
    'recordedAt',
    'speedMps',
  ]);
  assert.equal(dto.id, '9f4a2d2e-0b1c-4d5e-8f70-000000000009');
  assert.equal(dto.recordedAt, '2025-10-01T10:00:00.000Z');
  assert.equal(dto.receivedAt, '2025-10-01T10:00:01.000Z');
});

test('TrackingRepository base contract throws until implemented', async () => {
  const repo = new TrackingRepository();
  await assert.rejects(() => repo.save({}));
  await assert.rejects(() => repo.listTrail('o', 10));
  await assert.rejects(() => repo.listActiveDeliveries({ limit: 10 }));
});

test('TRACKING_LIMITS keeps sane trail/queue bounds', () => {
  assert.ok(TRACKING_LIMITS.trailDefault <= TRACKING_LIMITS.trailMax);
  assert.ok(TRACKING_LIMITS.deliveriesDefault <= TRACKING_LIMITS.deliveriesMax);
  assert.ok(TRACKING_LIMITS.pruneAfterDays >= 1);
  assert.ok(TRACKING_LIMITS.maxSpeedMps > 10, 'delivery speeds must fit');
});

// ─────────────────────────────── application ─────────────────────────────────

test('ReportPosition 404s for an unknown order', async () => {
  const trackingRepo = new FakeTrackingRepo();
  const useCase = new ReportPosition({ trackingRepo, orderRepo: new FakeOrderRepo([]) });
  await assertDomainError(() => useCase.execute({ id: OTHER_ID, lat: 28.6, lng: 77.2 }), 404, 'NOT_FOUND');
  assert.equal(trackingRepo.saved.length, 0);
});

test('ReportPosition 409s once the order is terminal', async () => {
  const trackingRepo = new FakeTrackingRepo();
  const useCase = new ReportPosition({ trackingRepo, orderRepo: new FakeOrderRepo([makeOrder({ status: 'delivered' })]) });
  await assertDomainError(() => useCase.execute({ id: ORDER_ID, lat: 28.6, lng: 77.2 }), 409, 'CONFLICT');
  assert.equal(trackingRepo.saved.length, 0);
});

test('ReportPosition accepts a live order, appends the fix and returns its DTO', async () => {
  const trackingRepo = new FakeTrackingRepo();
  const orderRepo = new FakeOrderRepo([makeOrder({ status: 'shipped' })]);
  const useCase = new ReportPosition({ trackingRepo, orderRepo });
  const dto = await useCase.execute({
    id: ORDER_ID,
    lat: 28.6139,
    lng: 77.209,
    accuracyM: 7,
    speedMps: 4.5,
    headingDeg: 180,
    recordedAt: new Date('2025-10-01T10:00:00.000Z'),
  });
  assert.equal(dto.orderId, ORDER_ID);
  assert.equal(dto.lat, 28.6139);
  assert.equal(dto.accuracyM, 7);
  assert.equal(dto.recordedAt, '2025-10-01T10:00:00.000Z');
  assert.equal(trackingRepo.saved.length, 1);
  assert.ok(trackingRepo.saved[0] instanceof RiderPosition);
  assert.equal(trackingRepo.saved[0].orderId, ORDER_ID);
});

test('ReportPosition surfaces domain validation for a bad fix', async () => {
  const trackingRepo = new FakeTrackingRepo();
  const useCase = new ReportPosition({ trackingRepo, orderRepo: new FakeOrderRepo([makeOrder()]) });
  await assertDomainError(() => useCase.execute({ id: ORDER_ID, lat: 91, lng: 77.2 }), 422, 'VALIDATION_ERROR');
  assert.equal(trackingRepo.saved.length, 0);
});

test('GetTrack 404s for an unknown order', async () => {
  const useCase = new GetTrack({ trackingRepo: new FakeTrackingRepo(), orderRepo: new FakeOrderRepo([]) });
  await assertDomainError(() => useCase.execute({ id: OTHER_ID, actor: { id: 'user-1' } }), 404, 'NOT_FOUND');
});

test('GetTrack 403s without an actor', async () => {
  const useCase = new GetTrack({ trackingRepo: new FakeTrackingRepo(), orderRepo: new FakeOrderRepo([makeOrder()]) });
  await assertDomainError(() => useCase.execute({ id: ORDER_ID, actor: null }), 403, 'FORBIDDEN');
});

test('GetTrack 403s for a different signed-in user', async () => {
  const useCase = new GetTrack({ trackingRepo: new FakeTrackingRepo(), orderRepo: new FakeOrderRepo([makeOrder()]) });
  await assertDomainError(() => useCase.execute({ id: ORDER_ID, actor: { id: 'someone-else', email: 'x@y.z' } }), 403, 'FORBIDDEN');
});

test('GetTrack 403s for a guest order watched by the wrong email', async () => {
  const order = makeOrder({ userId: null, email: 'guest@example.com' });
  const useCase = new GetTrack({ trackingRepo: new FakeTrackingRepo(), orderRepo: new FakeOrderRepo([order]) });
  await assertDomainError(
    () => useCase.execute({ id: ORDER_ID, actor: { id: 'user-2', email: 'other@example.com' } }),
    403,
    'FORBIDDEN',
  );
});

test('GetTrack lets the account owner read the trail', async () => {
  const trackingRepo = new FakeTrackingRepo();
  trackingRepo.trail = [
    { lat: 28.55, lng: 77.25, recordedAt: '2025-10-01T10:00:00.000Z' },
    { lat: 28.56, lng: 77.26, recordedAt: '2025-10-01T10:00:30.000Z' },
  ];
  const useCase = new GetTrack({ trackingRepo, orderRepo: new FakeOrderRepo([makeOrder({ status: 'shipped' })]) });
  const out = await useCase.execute({ id: ORDER_ID, actor: { id: 'user-1', email: 'owner@example.com' } });
  assert.equal(out.orderId, ORDER_ID);
  assert.equal(out.orderNumber, 'BBL-20251001-1234');
  assert.equal(out.status, 'shipped');
  assert.equal(out.trail.length, 2);
  assert.equal(out.latest.lat, 28.56, 'latest is the newest fix');
  assert.equal(out.updatedAt, '2025-10-01T10:00:30.000Z');
  const [, orderId, limit] = trackingRepo.calls.find(([name]) => name === 'listTrail');
  assert.equal(orderId, ORDER_ID);
  assert.equal(limit, TRACKING_LIMITS.trailDefault, 'default trail size is requested');
});

test('GetTrack lets a guest checkout watch by matching email', async () => {
  const order = makeOrder({ userId: null, email: 'guest@example.com' });
  const useCase = new GetTrack({ trackingRepo: new FakeTrackingRepo(), orderRepo: new FakeOrderRepo([order]) });
  const out = await useCase.execute({ id: ORDER_ID, actor: { id: 'user-9', email: 'guest@example.com' } });
  assert.equal(out.trail.length, 0);
});

test('GetTrack returns a coherent empty payload before any fix arrives', async () => {
  const useCase = new GetTrack({ trackingRepo: new FakeTrackingRepo(), orderRepo: new FakeOrderRepo([makeOrder()]) });
  const out = await useCase.execute({ id: ORDER_ID, actor: { id: 'user-1' } });
  assert.equal(out.latest, null);
  assert.deepEqual(out.trail, []);
  assert.equal(out.updatedAt, null);
});

test('GetTrack clamps the requested limit into the trail bounds', async () => {
  const trackingRepo = new FakeTrackingRepo();
  const useCase = new GetTrack({ trackingRepo, orderRepo: new FakeOrderRepo([makeOrder()]) });
  await useCase.execute({ id: ORDER_ID, actor: { id: 'user-1' }, limit: 99999 });
  await useCase.execute({ id: ORDER_ID, actor: { id: 'user-1' }, limit: 'not-a-number' });
  await useCase.execute({ id: ORDER_ID, actor: { id: 'user-1' }, limit: 0 });
  const limits = trackingRepo.calls.filter(([n]) => n === 'listTrail').map(([, , l]) => l);
  assert.deepEqual(limits, [TRACKING_LIMITS.trailMax, TRACKING_LIMITS.trailDefault, TRACKING_LIMITS.trailDefault]);
});

test('ListActiveDeliveries returns the queue read model', async () => {
  const trackingRepo = new FakeTrackingRepo();
  trackingRepo.queue = [
    { id: ORDER_ID, orderNumber: 'BBL-1', status: 'shipped', address: { lat: 28.6, lng: 77.2 } },
    { id: OTHER_ID, orderNumber: 'BBL-2', status: 'confirmed', address: { lat: 28.7, lng: 77.3 } },
  ];
  const useCase = new ListActiveDeliveries({ trackingRepo });
  const out = await useCase.execute({});
  assert.equal(out.total, 2);
  assert.equal(out.items[0].orderNumber, 'BBL-1');
  assert.deepEqual(out.limit, TRACKING_LIMITS.deliveriesDefault);
});

test('ListActiveDeliveries clamps the queue size', async () => {
  const trackingRepo = new FakeTrackingRepo();
  const useCase = new ListActiveDeliveries({ trackingRepo });
  await useCase.execute({ limit: 5000 });
  await useCase.execute({ limit: 'zzz' });
  const limits = trackingRepo.calls.map(([, q]) => q.limit);
  assert.deepEqual(limits, [TRACKING_LIMITS.deliveriesMax, TRACKING_LIMITS.deliveriesDefault]);
});

// ────────────────────────────── presentation ─────────────────────────────────

test('fix schema accepts a bare coordinate pair and coerces recordedAt', () => {
  const parsed = trackingSchemas.fix.parse({ lat: 28.6139, lng: 77.209, recordedAt: '2025-10-01T10:00:00.000Z' });
  assert.ok(parsed.recordedAt instanceof Date, 'ISO string becomes a Date');
  assert.equal(parsed.accuracyM, undefined, 'optional extras stay absent');
});

test('fix schema rejects out-of-range coordinates and extras', () => {
  assert.throws(() => trackingSchemas.fix.parse({ lat: 91, lng: 0 }));
  assert.throws(() => trackingSchemas.fix.parse({ lat: 0, lng: -181 }));
  assert.throws(() => trackingSchemas.fix.parse({ lat: 0, lng: 0, accuracyM: TRACKING_LIMITS.maxAccuracyM + 1 }));
  assert.throws(() => trackingSchemas.fix.parse({ lat: 0, lng: 0, speedMps: TRACKING_LIMITS.maxSpeedMps + 1 }));
  assert.throws(() => trackingSchemas.fix.parse({ lat: 0, lng: 0, headingDeg: 361 }));
  assert.throws(() => trackingSchemas.fix.parse({ lat: 0 }));
});

test('idParam only accepts uuids', () => {
  trackingSchemas.idParam.parse({ id: ORDER_ID });
  assert.throws(() => trackingSchemas.idParam.parse({ id: 'not-a-uuid' }));
});

test('track and deliveries query schemas bound the limit', () => {
  assert.equal(trackingSchemas.trackQuery.parse({ limit: '10' }).limit, 10);
  assert.throws(() => trackingSchemas.trackQuery.parse({ limit: '99999' }));
  assert.equal(trackingSchemas.deliveriesQuery.parse({}).limit, undefined);
  assert.throws(() => trackingSchemas.deliveriesQuery.parse({ limit: '0' }));
});

test('requireRider admits the rider key and rejects everything else', () => {
  const mw = requireRider();
  let admitted = false;
  let error = null;
  mw({ headers: { 'x-rider-key': 'blabliblu-rider' } }, null, (err) => {
    error = err;
    admitted = err === undefined;
  });
  assert.ok(admitted, 'the default rider key is admitted');
  assert.equal(error, undefined);

  mw({ headers: {} }, null, (err) => {
    error = err;
  });
  assert.ok(error instanceof DomainError);
  assert.equal(error.status, 403);
  assert.equal(error.code, 'FORBIDDEN');

  error = null;
  mw({ headers: { 'x-rider-key': 'wrong' } }, null, (err) => {
    error = err;
  });
  assert.ok(error instanceof DomainError, 'a wrong key is rejected');
  assert.equal(error.status, 403);
});
