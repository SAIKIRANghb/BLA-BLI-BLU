import { DomainError } from '../../../shared/domain/domain-error.js';
import { osrmError } from '../domain/index.js';

/**
 * OsrmGateway - infrastructure adapter that talks to an `osrm-routed` server
 * (see `infra/osrm/`). Every OSRM service maps onto one method; the adapter
 * owns URL construction, timeouts and transport failures.
 *
 * Transport problems become DomainErrors with 503/504 so the presentation
 * layer can answer without knowing anything about the engine.
 */
export class OsrmGateway {
  /**
   * @param {object} [options]
   * @param {string} [options.baseUrl] e.g. http://127.0.0.1:5000
   * @param {number} [options.timeoutMs]
   * @param {typeof fetch} [options.fetchImpl] injection point for tests
   */
  constructor({ baseUrl = 'http://127.0.0.1:5000', timeoutMs = 8000, fetchImpl } = {}) {
    this.baseUrl = String(baseUrl).replace(/\/+$/, '');
    this.timeoutMs = timeoutMs;
    this.fetch = fetchImpl ?? globalThis.fetch;
  }

  /** @returns {string} the engine origin, for diagnostics */
  get origin() {
    return this.baseUrl;
  }

  /**
   * GET that never throws raw network errors.
   * @param {string} path e.g. /route/v1/driving/77.2,28.6;77.2,28.7
   * @param {Record<string, unknown>} [query]
   * @returns {Promise<Response>}
   */
  async #get(path, query = {}) {
    // Query values are already validated by the domain layer (enums, ints,
    // bounded lists), so they are concatenated raw - matching the engine's
    // documented URL grammar (URLSearchParams would form-encode ";" to %3B).
    const qs = Object.entries(query)
      .filter(([, value]) => value !== undefined && value !== null && value !== '')
      .map(([key, value]) => `${key}=${value}`)
      .join('&');
    const url = new URL(`${this.baseUrl}${path}${qs ? `?${qs}` : ''}`);

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      return await this.fetch(url, { signal: controller.signal, headers: { accept: 'application/json' } });
    } catch (err) {
      if (err?.name === 'AbortError') {
        throw new DomainError('Routing engine timed out', { code: 'ROUTING_TIMEOUT', status: 504 });
      }
      throw new DomainError('Routing engine is unavailable', {
        code: 'ROUTING_UNAVAILABLE',
        status: 503,
        details: { reason: String(err?.message ?? err) },
      });
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * JSON service call. OSRM reports logical failures (NoRoute, TooBig, ...)
   * inside the body - those bodies are returned as-is and mapped to
   * DomainErrors by the application layer (`osrmError`).
   * @returns {Promise<object>} parsed OSRM body
   */
  async json(path, query = {}) {
    const res = await this.#get(path, query);
    try {
      const body = await res.json();
      if (body && typeof body === 'object') return body;
    } catch {
      /* fall through to the synthetic error below */
    }
    return { code: 'InvalidQuery', message: `Routing engine returned HTTP ${res.status} without a JSON body` };
  }

  /** Nearest - snap one coordinate to the street network. */
  nearest(profile, location, number) {
    return this.json(`/nearest/v1/${profile}/${location.toOsrm()}`, { number });
  }

  /** Route - fastest route between coordinates. */
  route(profile, locations, options = {}) {
    return this.json(`/route/v1/${profile}/${locations}`, options);
  }

  /** Table - duration/distance matrix of the fastest routes between all pairs. */
  table(profile, locations, options = {}) {
    return this.json(`/table/v1/${profile}/${locations}`, options);
  }

  /** Match - snap a noisy GPS trace onto the road network. */
  match(profile, locations, options = {}) {
    return this.json(`/match/v1/${profile}/${locations}`, options);
  }

  /** Trip - roundtrip/order optimization (greedy heuristic). */
  trip(profile, locations, options = {}) {
    return this.json(`/trip/v1/${profile}/${locations}`, options);
  }

  /**
   * Tile - Mapbox Vector Tiles carrying the routing graph metadata.
   * The engine's tile URL grammar is `tile({x},{y},{zoom}).mvt` - parens, x/y/z
   * order, no slashes (the URL parser rejects `/` inside the query part).
   * @returns {Promise<{status: number, buffer: Buffer}>}
   */
  async tile(profile, z, x, y) {
    const res = await this.#get(`/tile/v1/${profile}/tile(${x},${y},${z}).mvt`);
    const buffer = Buffer.from(await res.arrayBuffer());
    if (res.ok) return { status: res.status, buffer };

    let body = null;
    try {
      body = JSON.parse(buffer.toString('utf8'));
    } catch {
      /* binary/empty error body */
    }
    throw (
      osrmError(body?.code, { z, x, y }) ??
      new DomainError(`Tile ${z}/${x}/${y} could not be rendered (HTTP ${res.status})`, { code: 'TILE_ERROR', status: 502 })
    );
  }
}
