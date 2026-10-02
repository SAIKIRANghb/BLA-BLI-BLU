import { DomainError } from '../../../shared/domain/domain-error.js';

/**
 * Routing domain - coordinates, profiles and the OSRM error vocabulary.
 *
 * The app speaks latitude,longitude (web/GIS order); OSRM's URL format speaks
 * longitude,latitude. That translation lives here so no other layer ever has
 * to remember which order it is holding.
 */

/** Profiles the loaded dataset can answer for (extract built from the OSRM car profile). */
export const SUPPORTED_PROFILES = ['driving'];

/** Hard request limits - OSRM accepts far more, but the API refuses absurd payloads early. */
export const ROUTING_LIMITS = Object.freeze({
  points: 100,
  nearestNumber: 16,
  timestamps: 100,
  /** Engine hard-codes vector tiles to zoom 12..19 (keeps huge tiles from being served). */
  tileZoomMin: 12,
  tileZoomMax: 19,
});

/**
 * GeoPoint - immutable WGS84 coordinate (Value Object).
 */
export class GeoPoint {
  /**
   * @param {number} lat -90..90
   * @param {number} lng -180..180
   */
  constructor(lat, lng) {
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
      throw new DomainError('Latitude must be a number between -90 and 90', { code: 'INVALID_COORDINATE', status: 400, details: { field: 'lat' } });
    }
    if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
      throw new DomainError('Longitude must be a number between -180 and 180', { code: 'INVALID_COORDINATE', status: 400, details: { field: 'lng' } });
    }
    this.lat = lat;
    this.lng = lng;
    Object.freeze(this);
  }

  /**
   * Parses the wire format `lat,lng`.
   * @param {unknown} raw
   * @returns {GeoPoint}
   */
  static parse(raw) {
    const parts = String(raw ?? '').split(',');
    if (parts.length !== 2 || parts.some((s) => s.trim() === '')) {
      throw new DomainError('A coordinate must be formatted as "lat,lng"', { code: 'INVALID_COORDINATES', status: 400 });
    }
    const [lat, lng] = parts.map((s) => Number(s.trim()));
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      throw new DomainError('A coordinate must contain two decimal numbers ("lat,lng")', { code: 'INVALID_COORDINATES', status: 400 });
    }
    return new GeoPoint(lat, lng);
  }

  /** OSRM URL segment order: longitude,latitude. */
  toOsrm() {
    return `${this.lng},${this.lat}`;
  }
}

/**
 * Parses `lat,lng;lat,lng;...` into GeoPoints with count limits.
 * @param {unknown} raw
 * @param {{min?: number, max?: number}} [bounds]
 * @returns {GeoPoint[]}
 */
export function parseGeoPoints(raw, { min = 2, max = ROUTING_LIMITS.points } = {}) {
  const parts = String(raw ?? '').split(';').filter((s) => s.trim() !== '');
  if (parts.length < min) {
    throw new DomainError(`Expected at least ${min} points separated by ";"`, { code: 'INVALID_COORDINATES', status: 400, details: { min } });
  }
  if (parts.length > max) {
    throw new DomainError(`Too many points in one request (max ${max})`, { code: 'TOO_MANY_POINTS', status: 413, details: { max, got: parts.length } });
  }
  return parts.map((p) => GeoPoint.parse(p));
}

/**
 * Parses a comma separated index list ("0,2") used by the table service.
 * @param {unknown} raw
 * @param {number} count total points, used to bound the indices
 * @returns {number[] | undefined}
 */
export function parseIndexList(raw, count) {
  if (raw === undefined || raw === null || raw === '') return undefined;
  const parts = String(raw).split(',').filter((s) => s.trim() !== '');
  const indices = parts.map((s) => {
    const n = Number(s.trim());
    if (!Number.isInteger(n) || n < 0 || n >= count) {
      throw new DomainError(`Index "${s.trim()}" is out of range for ${count} points`, { code: 'INVALID_INDEX', status: 400 });
    }
    return n;
  });
  return indices.length > 0 ? indices : undefined;
}

/**
 * Parses a comma separated integer list ("1,31,91") - timestamps etc.
 * @param {unknown} raw
 * @param {string} field
 * @returns {number[]}
 */
export function parseIntegerList(raw, field) {
  const parts = String(raw ?? '').split(',').filter((s) => s.trim() !== '');
  if (parts.length === 0) {
    throw new DomainError(`${field} must be a comma separated list of integers`, { code: `INVALID_${field.toUpperCase()}`, status: 400 });
  }
  return parts.map((s) => {
    const n = Number(s.trim());
    if (!Number.isInteger(n) || n < 0) {
      throw new DomainError(`${field} must contain non-negative integers`, { code: `INVALID_${field.toUpperCase()}`, status: 400 });
    }
    return n;
  });
}

/**
 * Parses the optional per-point GPS accuracy list for the match service
 * ("20,20,30" on our wire format, `;` separated towards the engine).
 * @param {unknown} raw
 * @param {number} count number of trace points the radii must cover
 * @returns {string | undefined} engine-ready `;` separated list
 */
export function parseRadiusList(raw, count) {
  if (raw === undefined || raw === null || raw === '') return undefined;
  const parts = String(raw).split(',').filter((s) => s.trim() !== '');
  const values = parts.map((s) => {
    const n = Number(s.trim());
    if (!Number.isFinite(n) || n < 0) {
      throw new DomainError(`radius "${s.trim()}" must be a number >= 0`, { code: 'INVALID_RADIUS', status: 400 });
    }
    return n;
  });
  if (values.length !== count) {
    throw new DomainError(`radiuses (${values.length}) must match the number of points (${count})`, {
      code: 'RADIUS_MISMATCH',
      status: 400,
    });
  }
  return values.join(';');
}

/** @param {GeoPoint[]} points @returns {string} `lng,lat;lng,lat` for the OSRM URL */
export function toOsrmLocations(points) {
  return points.map((p) => p.toOsrm()).join(';');
}

/**
 * The dataset is compiled from a single profile - reject the rest early with
 * a helpful message instead of letting OSRM answer "InvalidService".
 * @param {unknown} profile
 * @returns {string} the validated profile
 */
export function assertProfile(profile) {
  const value = String(profile ?? 'driving');
  if (!SUPPORTED_PROFILES.includes(value)) {
    throw new DomainError(`Unsupported profile "${value}" - this dataset serves: ${SUPPORTED_PROFILES.join(', ')}`, {
      code: 'UNSUPPORTED_PROFILE',
      status: 422,
      details: { supported: SUPPORTED_PROFILES },
    });
  }
  return value;
}

const OSRM_MESSAGES = Object.freeze({
  InvalidQuery: 'The routing query was malformed',
  InvalidUrl: 'The routing URL was malformed',
  InvalidService: 'Unknown routing service',
  InvalidVersion: 'Unknown routing protocol version',
  InvalidOptions: 'The routing engine rejected those options',
  InvalidValue: 'One of the supplied values is invalid',
  NoSegment: 'One of the coordinates is not on the road network',
  NoRoute: 'No route exists between those points',
  NoMatch: 'The GPS trace could not be matched to the road network',
  NoTrips: 'No trip could be computed for those points',
  NoTable: 'No duration table could be computed for those points',
  TooBig: 'Too many coordinates for one request',
  TooBigRequest: 'Too many coordinates for one request',
  UnsupportedOption: 'The routing engine does not support that option',
  DataError: 'Routing data error',
  NotImplemented: 'That routing capability is not supported by this engine build',
  DisabledDataset: 'The requested routing dataset is not available',
});

const OSRM_STATUS = Object.freeze({
  InvalidQuery: 400,
  InvalidUrl: 400,
  InvalidService: 404,
  InvalidVersion: 404,
  InvalidOptions: 422,
  InvalidValue: 400,
  NoSegment: 404,
  NoRoute: 404,
  NoMatch: 404,
  NoTrips: 404,
  NoTable: 404,
  TooBig: 413,
  TooBigRequest: 413,
  UnsupportedOption: 422,
  DataError: 422,
  NotImplemented: 501,
  DisabledDataset: 404,
});

/**
 * Maps an OSRM response `code` onto a DomainError (Observer: one place that
 * understands the engine's vocabulary).
 * @param {unknown} code
 * @param {object} [details]
 * @returns {DomainError | null} null when the code means success
 */
export function osrmError(code, details = undefined) {
  if (code === undefined || code === null || code === 'Ok') return null;
  const name = String(code);
  return new DomainError(OSRM_MESSAGES[name] ?? `Routing engine error (${name})`, {
    code: `OSRM_${name.toUpperCase()}`,
    status: OSRM_STATUS[name] ?? 502,
    details: details ?? { upstream: name },
  });
}
