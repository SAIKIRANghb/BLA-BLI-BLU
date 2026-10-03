import { db } from '../../../config/database.js';
import { TrackingRepository, TRACKING_LIMITS } from '../domain/index.js';

/** Row -> position DTO (camelCase on the wire, snake_case in SQL). */
function toPosition(row) {
  if (!row) return null;
  return {
    id: row.id,
    orderId: row.order_id,
    lat: row.lat,
    lng: row.lng,
    accuracyM: row.accuracy_m,
    speedMps: row.speed_mps,
    headingDeg: row.heading_deg,
    recordedAt: new Date(row.recorded_at).toISOString(),
    receivedAt: new Date(row.received_at).toISOString(),
  };
}

/**
 * PgTrackingRepository - Infrastructure adapter for the rider fix trail.
 * Accepts either the pool (db) or a transaction facade (Unit of Work).
 */
export class PgTrackingRepository extends TrackingRepository {
  constructor(client = db) {
    super();
    this.db = client;
  }

  async save(position) {
    await this.db.query(
      `INSERT INTO rider_positions (id, order_id, lat, lng, accuracy_m, speed_mps, heading_deg, recorded_at, received_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        position.id,
        position.orderId,
        position.lat,
        position.lng,
        position.accuracyM,
        position.speedMps,
        position.headingDeg,
        position.recordedAt,
        position.receivedAt,
      ],
    );
    // Keep the trail bounded per order - no background job, the next insert
    // of the same order pays the (indexed) cleanup once the window passes.
    await this.db.query(
      `DELETE FROM rider_positions
        WHERE order_id = $1
          AND recorded_at < now() - $2::int * interval '1 day'
          AND received_at < now() - $2::int * interval '1 day'`,
      [position.orderId, TRACKING_LIMITS.pruneAfterDays],
    );
  }

  async listTrail(orderId, limit) {
    const rows = await this.db.rows(
      `SELECT * FROM (
         SELECT id, order_id, lat, lng, accuracy_m, speed_mps, heading_deg, recorded_at, received_at
           FROM rider_positions
          WHERE order_id = $1
          ORDER BY recorded_at DESC
          LIMIT $2
       ) newest
       ORDER BY recorded_at ASC`,
      [orderId, limit],
    );
    return rows.map(toPosition);
  }

  async listActiveDeliveries({ limit }) {
    const rows = await this.db.rows(
      `SELECT o.id, o.order_number, o.status, o.address, o.created_at, o.updated_at,
              p.lat AS last_lat, p.lng AS last_lng, p.accuracy_m AS last_accuracy_m,
              p.recorded_at AS last_recorded_at
         FROM orders o
         LEFT JOIN LATERAL (
           SELECT lat, lng, accuracy_m, recorded_at
             FROM rider_positions
            WHERE order_id = o.id
            ORDER BY recorded_at DESC
            LIMIT 1
         ) p ON TRUE
        WHERE o.status NOT IN ('delivered', 'cancelled')
          AND o.address->>'lat' IS NOT NULL
          AND o.address->>'lng' IS NOT NULL
        ORDER BY o.created_at ASC
        LIMIT $1`,
      [limit],
    );
    return rows.map((row) => ({
      id: row.id,
      orderNumber: row.order_number,
      status: row.status,
      address: {
        name: row.address?.name ?? '',
        line1: row.address?.line1 ?? '',
        line2: row.address?.line2 ?? '',
        city: row.address?.city ?? '',
        state: row.address?.state ?? '',
        pincode: row.address?.pincode ?? '',
        lat: Number(row.address?.lat),
        lng: Number(row.address?.lng),
      },
      placedAt: new Date(row.created_at).toISOString(),
      lastFix:
        row.last_lat == null
          ? null
          : {
              lat: row.last_lat,
              lng: row.last_lng,
              accuracyM: row.last_accuracy_m,
              recordedAt: new Date(row.last_recorded_at).toISOString(),
            },
    }));
  }
}
