import test from 'node:test';
import assert from 'node:assert/strict';
import {
  GeoPoint,
  ROUTING_LIMITS,
  assertProfile,
  osrmError,
  parseGeoPoints,
  parseIndexList,
  parseIntegerList,
  parseRadiusList,
  toOsrmLocations,
} from '../src/modules/routing/domain/index.js';
import { RoutingService } from '../src/modules/routing/application/routing-service.js';
import { OsrmGateway } from '../src/modules/routing/infrastructure/osrm-gateway.js';
import { DomainError } from '../src/shared/domain/domain-error.js';

/** Gateway test double: records every call and answers from a responder. */
class FakeGateway {
  constructor(responder = () => ({ code: 'Ok' })) {
    this.responder = responder;
    this.calls = [];
  }

  record(service, args) {
    this.calls.push([service, args]);
    return Promise.resolve(this.responder(service, args));
  }

  nearest(...args) {
    return this.record('nearest', args);
  }

  route(...args) {
    return this.record('route', args);
  }

  table(...args) {
    return this.record('table', args);
  }

  match(...args) {
    return this.record('match', args);
  }

  trip(...args) {
    return this.record('trip', args);
  }

  tile(...args) {
    return this.record('tile', args);
  }
}

/** Accepts a thunk (sync throws) or a promise; resolves to the thrown error or null. */
async function caught(input) {
  try {
    await (typeof input === 'function' ? input() : input);
    return null;
  } catch (err) {
    return err;
  }
}

/** Always `await` this - asserts the failure is a DomainError with status/code.
 * Accepts an Error value, a thunk (sync throws) or a promise. */
async function assertDomainError(input, status, code) {
  const err = input instanceof Error ? input : await caught(input);
  assert.ok(err instanceof DomainError, `expected a DomainError, got: ${err?.message ?? err}`);
  assert.equal(err.status, status, `expected status ${status}, got ${err.status} (${err.code})`);
  if (code) assert.equal(err.code, code);
  return err;
}

// ───────────────────────────────── domain ────────────────────────────────────

test('GeoPoint parses the wire format and emits OSRM longitude-first order', () => {
  const p = GeoPoint.parse('28.6139,77.2090');
  assert.equal(p.lat, 28.6139);
  assert.equal(p.lng, 77.209);
  assert.equal(p.toOsrm(), '77.209,28.6139');
  assert.equal(
    toOsrmLocations([p, GeoPoint.parse('28.5494,77.2001')]),
    '77.209,28.6139;77.2001,28.5494',
  );
});

test('GeoPoint rejects malformed and out-of-range coordinates', async () => {
  await assertDomainError(() => GeoPoint.parse('28.6'), 400, 'INVALID_COORDINATES');
  await assertDomainError(() => GeoPoint.parse('28.6,77.2,1'), 400, 'INVALID_COORDINATES');
  await assertDomainError(() => GeoPoint.parse('abc,def'), 400, 'INVALID_COORDINATES');
  await assertDomainError(() => GeoPoint.parse(',77.2'), 400, 'INVALID_COORDINATES');
  await assertDomainError(() => GeoPoint.parse('91,10'), 400, 'INVALID_COORDINATE');
  await assertDomainError(() => GeoPoint.parse('10,181'), 400, 'INVALID_COORDINATE');
});

test('parseGeoPoints enforces the point-count limits', async () => {
  await assertDomainError(() => parseGeoPoints('28.6,77.2', { min: 2 }), 400, 'INVALID_COORDINATES');
  const tooMany = Array.from({ length: ROUTING_LIMITS.points + 1 }, (_, i) => `28.${i % 90},77.2`).join(';');
  await assertDomainError(() => parseGeoPoints(tooMany), 413, 'TOO_MANY_POINTS');
  assert.equal(parseGeoPoints('28.6,77.2;28.7,77.3').length, 2);
});

test('index and integer lists validate their contents', async () => {
  assert.deepEqual(parseIndexList('0,2', 3), [0, 2]);
  assert.equal(parseIndexList('', 3), undefined);
  await assertDomainError(() => parseIndexList('5', 3), 400, 'INVALID_INDEX');
  await assertDomainError(() => parseIndexList('1.5', 3), 400, 'INVALID_INDEX');
  assert.deepEqual(parseIntegerList('1,31,91', 'timestamps'), [1, 31, 91]);
  await assertDomainError(() => parseIntegerList('x', 'timestamps'), 400, 'INVALID_TIMESTAMPS');
  await assertDomainError(() => parseIntegerList('', 'timestamps'), 400, 'INVALID_TIMESTAMPS');
});

test('radiuses arrive comma separated and leave semicolon separated', async () => {
  assert.equal(parseRadiusList('20,30', 2), '20;30');
  assert.equal(parseRadiusList(undefined, 2), undefined);
  await assertDomainError(() => parseRadiusList('20', 2), 400, 'RADIUS_MISMATCH');
  await assertDomainError(() => parseRadiusList('20,-1', 2), 400, 'INVALID_RADIUS');
  await assertDomainError(() => parseRadiusList('wide', 2), 400, 'INVALID_RADIUS');
});

test('only the compiled dataset profile is served', async () => {
  assert.equal(assertProfile('driving'), 'driving');
  assert.equal(assertProfile(undefined), 'driving');
  await assertDomainError(() => assertProfile('cycling'), 422, 'UNSUPPORTED_PROFILE');
});

test('OSRM response codes map onto HTTP statuses', async () => {
  assert.equal(osrmError('Ok'), null);
  assert.equal(osrmError(undefined), null);
  await assertDomainError(osrmError('NoRoute'), 404, 'OSRM_NOROUTE');
  await assertDomainError(osrmError('NoMatch'), 404, 'OSRM_NOMATCH');
  await assertDomainError(osrmError('InvalidValue'), 400, 'OSRM_INVALIDVALUE');
  await assertDomainError(osrmError('InvalidQuery'), 400, 'OSRM_INVALIDQUERY');
  await assertDomainError(osrmError('InvalidOptions'), 422, 'OSRM_INVALIDOPTIONS');
  await assertDomainError(osrmError('TooBig'), 413, 'OSRM_TOOBIG');
  await assertDomainError(osrmError('NotImplemented'), 501, 'OSRM_NOTIMPLEMENTED');
  await assertDomainError(osrmError('SomethingNew'), 502, 'OSRM_SOMETHINGNEW');
});

// ──────────────────────────────── service ────────────────────────────────────

test('route builds longitude-first locations and map-friendly defaults', async () => {
  const body = { code: 'Ok', routes: [{ distance: 100 }] };
  const gateway = new FakeGateway(() => body);
  const service = new RoutingService({ gateway });

  const result = await service.route({ points: '28.6139,77.2090;28.5494,77.2001' });
  assert.deepEqual(result, body);

  const [profile, locations, options] = gateway.calls[0][1];
  assert.equal(profile, 'driving');
  assert.equal(locations, '77.209,28.6139;77.2001,28.5494');
  assert.equal(options.overview, 'full');
  assert.equal(options.geometries, 'geojson');
});

test('route surfaces engine failures and validates input before dialling out', async () => {
  const noRoute = new FakeGateway(() => ({ code: 'NoRoute', message: 'nope' }));
  await assertDomainError(
    new RoutingService({ gateway: noRoute }).route({ points: '1,2;3,4' }),
    404,
    'OSRM_NOROUTE',
  );

  const untouched = new FakeGateway();
  const service = new RoutingService({ gateway: untouched });
  await assertDomainError(service.route({ points: '28.6,77.2' }), 400, 'INVALID_COORDINATES');
  await assertDomainError(service.route({ points: '1,2;3,4', steps: 'maybe' }), 422, 'VALIDATION_ERROR');
  assert.equal(untouched.calls.length, 0, 'invalid input must not reach the gateway');
});

test('nearest snaps one point with a bounded result count', async () => {
  const gateway = new FakeGateway();
  const service = new RoutingService({ gateway });

  await service.nearest({ point: '28.6139,77.2090' });
  const [profile, location, number] = gateway.calls[0][1];
  assert.equal(profile, 'driving');
  assert.ok(location instanceof GeoPoint);
  assert.equal(number, 1);

  await assertDomainError(
    service.nearest({ point: '28.6,77.2', number: ROUTING_LIMITS.nearestNumber + 1 }),
    422,
    'VALIDATION_ERROR',
  );
  await assertDomainError(service.nearest({ point: '99,99' }), 400, 'INVALID_COORDINATE');
});

test('table forwards index lists semicolon separated with both annotations', async () => {
  const gateway = new FakeGateway();
  const service = new RoutingService({ gateway });
  const points = '28.6,77.2;28.7,77.3;28.8,77.4';

  await service.table({ points, sources: '0,1', destinations: '2', annotations: 'duration,distance' });
  const [, , options] = gateway.calls[0][1];
  assert.equal(options.sources, '0;1');
  assert.equal(options.destinations, '2');
  assert.equal(options.annotations, 'duration,distance');

  await service.table({ points, sources: 'all' });
  assert.equal(gateway.calls[1][1][2].sources, 'all');

  await assertDomainError(service.table({ points, annotations: 'speed' }), 422, 'VALIDATION_ERROR');
  await assertDomainError(service.table({ points, sources: '7' }), 400, 'INVALID_INDEX');
  // A 1x1 matrix is degenerate but valid (single address x warehouse).
  await service.table({ points: '28.6,77.2' });
  await assertDomainError(service.table({ points: '' }), 400, 'INVALID_COORDINATES');
});

test('match aligns timestamps and radiuses with the trace, semicolon separated', async () => {
  const gateway = new FakeGateway();
  const service = new RoutingService({ gateway });
  const points = '28.6139,77.2090;28.6129,77.2120;28.6119,77.2150';

  await service.match({ points, timestamps: '1,41,81', radiuses: '20,30,20' });
  const [, , options] = gateway.calls[0][1];
  assert.equal(options.timestamps, '1;41;81');
  assert.equal(options.radiuses, '20;30;20');
  assert.equal(options.geometries, 'geojson');

  await assertDomainError(service.match({ points, timestamps: '1,41' }), 400, 'TIMESTAMP_MISMATCH');
  await assertDomainError(service.match({ points, timestamps: '81,41,1' }), 400, 'INVALID_TIMESTAMPS');
  // Equal timestamps are monotonic - the engine accepts them.
  await service.match({ points, timestamps: '41,41,81' });
  await assertDomainError(
    service.match({ points, timestamps: '1,41,81', radiuses: '20' }),
    400,
    'RADIUS_MISMATCH',
  );
});

test("trip validates the engine's supported source/destination combinations", async () => {
  const gateway = new FakeGateway();
  const service = new RoutingService({ gateway });
  const points = '28.6,77.2;28.7,77.3;28.8,77.4';

  await service.trip({ points, source: 'first', destination: 'last', roundtrip: 'false' });
  const [, , options] = gateway.calls[0][1];
  assert.equal(options.source, 'first');
  assert.equal(options.destination, 'last');
  assert.equal(options.roundtrip, 'false');

  await assertDomainError(service.trip({ points, source: 'last' }), 422, 'VALIDATION_ERROR');
  await assertDomainError(service.trip({ points, destination: 'first' }), 422, 'VALIDATION_ERROR');
  await assertDomainError(
    service.trip({ points, roundtrip: 'false' }),
    422,
    'VALIDATION_ERROR',
    'open trip without fixed ends is unsupported',
  );
});

test('tile validates the slippy grid the engine will accept', async () => {
  const gateway = new FakeGateway(() => ({ status: 200, buffer: Buffer.from([0x1a]) }));
  const service = new RoutingService({ gateway });

  const out = await service.tile({ z: 14, x: 11705, y: 6831 });
  assert.equal(out.status, 200);
  assert.deepEqual(gateway.calls[0], ['tile', ['driving', 14, 11705, 6831]]);

  await assertDomainError(service.tile({ z: 11, x: 1463, y: 854 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(service.tile({ z: 20, x: 0, y: 0 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(service.tile({ z: 14, x: 99999, y: 0 }), 422, 'VALIDATION_ERROR');
  await assertDomainError(service.tile({ z: 14, x: 0, y: -1 }), 422, 'VALIDATION_ERROR');
});

// ──────────────────────────────── gateway ────────────────────────────────────

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

test('gateway builds OSRM URLs in the engine grammar', async () => {
  const seen = [];
  const gateway = new OsrmGateway({
    baseUrl: 'http://osrm.test:5000/',
    fetchImpl: async (url) => {
      seen.push(String(url));
      return jsonResponse({ code: 'Ok' });
    },
  });

  await gateway.route('driving', '77.21,28.61;77.2,28.55', {
    overview: 'full',
    geometries: 'geojson',
    steps: undefined,
  });
  assert.equal(
    seen[0],
    'http://osrm.test:5000/route/v1/driving/77.21,28.61;77.2,28.55?overview=full&geometries=geojson',
  );

  await gateway.match('driving', '77.2,28.6;77.3,28.7', { timestamps: '1;41', radiuses: '20;20' });
  assert.ok(seen[1].endsWith('/match/v1/driving/77.2,28.6;77.3,28.7?timestamps=1;41&radiuses=20;20'));

  await gateway.tile('driving', 14, 11705, 6831);
  assert.equal(seen[2], 'http://osrm.test:5000/tile/v1/driving/tile(11705,6831,14).mvt');
  assert.equal(gateway.origin, 'http://osrm.test:5000');
});

test('gateway passes engine error bodies through for the domain to map', async () => {
  const gateway = new OsrmGateway({
    fetchImpl: async () => jsonResponse({ code: 'InvalidValue', message: 'Invalid coordinate value.' }, 400),
  });
  const body = await gateway.route('driving', '999,999;1,2', {});
  assert.equal(body.code, 'InvalidValue');
});

test('gateway turns transport failures into 503 and timeouts into 504', async () => {
  const down = new OsrmGateway({
    fetchImpl: async () => {
      throw new TypeError('fetch failed');
    },
  });
  await assertDomainError(down.route('driving', '1,2;3,4', {}), 503, 'ROUTING_UNAVAILABLE');

  const stall = new OsrmGateway({
    timeoutMs: 5,
    fetchImpl: (url, { signal }) =>
      new Promise((resolve, reject) => {
        signal.addEventListener('abort', () => {
          const aborted = new Error('aborted');
          aborted.name = 'AbortError';
          reject(aborted);
        });
      }),
  });
  await assertDomainError(stall.table('driving', '1,2', {}), 504, 'ROUTING_TIMEOUT');
});

test('gateway maps tile failures onto the OSRM vocabulary', async () => {
  const gateway = new OsrmGateway({
    fetchImpl: async () =>
      jsonResponse({ code: 'InvalidOptions', message: 'Only zoomlevel 12+ is supported' }, 400),
  });
  await assertDomainError(gateway.tile('driving', 11, 1463, 854), 422, 'OSRM_INVALIDOPTIONS');
});
