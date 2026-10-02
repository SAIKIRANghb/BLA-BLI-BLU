import { DomainError } from '../../../shared/domain/domain-error.js';
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
} from '../domain/index.js';

const GEOJSON = 'geojson';
const OVERVIEWS = ['full', 'simplified', 'false'];
const GEOMETRIES = ['polyline', 'polyline6', GEOJSON];
const TABLE_ANNOTATIONS = /^(duration|distance)(,(duration|distance))?$/;

/**
 * RoutingService - application layer for the six OSRM capabilities.
 *
 * One use case per engine service. Every method: validate (domain), delegate
 * to the gateway port, then translate the engine's `code` into the domain's
 * failure vocabulary. The OSRM body itself passes through untouched so
 * callers keep access to legs, waypoints, annotations, etc.
 */
export class RoutingService {
  /** @param {{gateway: {nearest:Function, route:Function, table:Function, match:Function, trip:Function, tile:Function}}} deps */
  constructor({ gateway }) {
    if (!gateway) throw new DomainError('RoutingService requires a gateway', { status: 500 });
    this.gateway = gateway;
  }

  /** @returns {Promise<object>} validated OSRM body */
  async #call(promise) {
    const body = await promise;
    const failure = osrmError(body?.code);
    if (failure) throw failure;
    return body;
  }

  /**
   * Nearest - snaps a coordinate to the street network and returns the
   * closest matches (with street names and distances).
   * @param {object} input {profile, point, number}
   */
  async nearest({ profile, point, number } = {}) {
    const p = assertProfile(profile);
    const location = GeoPoint.parse(point);
    const count = number === undefined ? 1 : Number(number);
    if (!Number.isInteger(count) || count < 1 || count > ROUTING_LIMITS.nearestNumber) {
      throw DomainError.validation(`number must be an integer between 1 and ${ROUTING_LIMITS.nearestNumber}`, { field: 'number' });
    }
    return this.#call(this.gateway.nearest(p, location, count));
  }

  /**
   * Route - the fastest route between two or more coordinates.
   * Defaults are chosen for map display: full geometry as GeoJSON.
   * @param {object} input {profile, points, overview, steps, alternatives, annotations, geometries}
   */
  async route({ profile, points, overview, steps, alternatives, annotations, geometries } = {}) {
    const p = assertProfile(profile);
    const locations = toOsrmLocations(parseGeoPoints(points, { min: 2 }));
    return this.#call(
      this.gateway.route(p, locations, {
        overview: this.#overview(overview),
        geometries: this.#geometries(geometries),
        steps: this.#bool(steps),
        alternatives: this.#bool(alternatives),
        annotations: this.#bool(annotations),
      }),
    );
  }

  /**
   * Table - duration/distance of the fastest route between all pairs of the
   * supplied coordinates (e.g. warehouses x delivery addresses).
   * @param {object} input {profile, points, sources, destinations, annotations}
   */
  async table({ profile, points, sources, destinations, annotations } = {}) {
    const p = assertProfile(profile);
    const coords = parseGeoPoints(points, { min: 1 });
    const ann = annotations === undefined ? 'duration' : String(annotations);
    if (!TABLE_ANNOTATIONS.test(ann)) {
      throw DomainError.validation('annotations must be "duration", "distance" or both comma separated', { field: 'annotations' });
    }
    return this.#call(
      this.gateway.table(p, toOsrmLocations(coords), {
        sources: this.#indexList(sources, coords.length),
        destinations: this.#indexList(destinations, coords.length),
        annotations: ann,
      }),
    );
  }

  /**
   * Match - snaps a noisy GPS trace (coordinates + timestamps) to the road
   * network in the most plausible way. `radiuses` carries per-point GPS
   * accuracy so jittered points still find their road.
   * @param {object} input {profile, points, timestamps, radiuses, overview, geometries}
   */
  async match({ profile, points, timestamps, radiuses, overview, geometries } = {}) {
    const p = assertProfile(profile);
    const coords = parseGeoPoints(points, { min: 2 });
    const stamps = parseIntegerList(timestamps, 'timestamps');
    if (stamps.length !== coords.length) {
      throw new DomainError(`timestamps (${stamps.length}) must match the number of points (${coords.length})`, {
        code: 'TIMESTAMP_MISMATCH',
        status: 400,
      });
    }
    for (let i = 1; i < stamps.length; i += 1) {
      if (stamps[i] < stamps[i - 1]) {
        throw new DomainError('timestamps must be monotonically increasing (seconds, separated by ";")', {
          code: 'INVALID_TIMESTAMPS',
          status: 400,
        });
      }
    }
    return this.#call(
      this.gateway.match(p, toOsrmLocations(coords), {
        timestamps: stamps.join(';'),
        radiuses: parseRadiusList(radiuses, coords.length),
        overview: this.#overview(overview),
        geometries: this.#geometries(geometries),
      }),
    );
  }

  /**
   * Trip - orders the points into a roundtrip (greedy heuristic / TSP).
   * The engine only accepts `source=any|first` and `destination=any|last`,
   * and rejects an open trip between two arbitrary ends.
   * @param {object} input {profile, points, source, destination, roundtrip, overview, geometries}
   */
  async trip({ profile, points, source, destination, roundtrip, overview, geometries } = {}) {
    const p = assertProfile(profile);
    const locations = toOsrmLocations(parseGeoPoints(points, { min: 2 }));
    const src = this.#enum(source, ['any', 'first'], 'any');
    const dst = this.#enum(destination, ['any', 'last'], 'any');
    const rt = this.#bool(roundtrip, 'true');
    if (rt === 'false' && src === 'any' && dst === 'any') {
      throw DomainError.validation('an open trip needs source=first or destination=last', { field: 'roundtrip' });
    }
    return this.#call(
      this.gateway.trip(p, locations, {
        source: src,
        destination: dst,
        roundtrip: rt,
        overview: this.#overview(overview),
        geometries: this.#geometries(geometries),
      }),
    );
  }

  /**
   * Tile - Mapbox Vector Tile of the routing graph at z/x/y.
   * The engine only serves zoom 12..19 and requires x/y inside the slippy grid.
   * @param {object} input {profile, z, x, y}
   * @returns {Promise<{status: number, buffer: Buffer}>}
   */
  async tile({ profile, z, x, y } = {}) {
    const p = assertProfile(profile);
    if (!Number.isInteger(z) || z < ROUTING_LIMITS.tileZoomMin || z > ROUTING_LIMITS.tileZoomMax) {
      throw DomainError.validation(`z must be between ${ROUTING_LIMITS.tileZoomMin} and ${ROUTING_LIMITS.tileZoomMax}`, { field: 'z' });
    }
    const max = 2 ** z - 1;
    for (const [field, value] of [['x', x], ['y', y]]) {
      if (!Number.isInteger(value) || value < 0 || value > max) {
        throw DomainError.validation(`${field} must be between 0 and ${max} at zoom ${z}`, { field });
      }
    }
    return this.gateway.tile(p, z, x, y);
  }

  // ── option helpers ───────────────────────────────────────────────────────

  #bool(value, fallback = undefined) {
    if (value === undefined) return fallback;
    const raw = String(value).toLowerCase();
    if (['true', '1'].includes(raw)) return 'true';
    if (['false', '0'].includes(raw)) return 'false';
    throw DomainError.validation(`expected a boolean flag, got "${value}"`, { field: 'flag' });
  }

  #overview(value) {
    const v = value === undefined ? 'full' : String(value);
    if (!OVERVIEWS.includes(v)) throw DomainError.validation(`overview must be one of ${OVERVIEWS.join(', ')}`, { field: 'overview' });
    return v;
  }

  #geometries(value) {
    const v = value === undefined ? GEOJSON : String(value);
    if (!GEOMETRIES.includes(v)) throw DomainError.validation(`geometries must be one of ${GEOMETRIES.join(', ')}`, { field: 'geometries' });
    return v;
  }

  #enum(value, allowed, fallback) {
    if (value === undefined) return fallback;
    const v = String(value);
    if (!allowed.includes(v)) throw DomainError.validation(`${v} is not one of ${allowed.join(', ')}`, { field: 'value' });
    return v;
  }

  #indexList(raw, count) {
    if (raw !== undefined && raw !== null && String(raw).trim() === 'all') return 'all';
    const indices = parseIndexList(raw, count);
    // The engine separates per-location options and index lists with ";".
    return indices === undefined ? undefined : indices.join(';');
  }
}
