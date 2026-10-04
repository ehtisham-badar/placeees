import { sql } from '../db/client.js';
import type { LocationPayload, PreviousFix } from './location.js';

export async function previousFix(userId: string): Promise<PreviousFix | null> {
  const [row] = await sql<{ lat: number | null; lng: number | null; lastFixAt: Date | null }[]>`
    SELECT ST_Y(last_fix_geo::geometry) AS lat, ST_X(last_fix_geo::geometry) AS lng, last_fix_at
    FROM users WHERE id = ${userId}`;
  if (!row || row.lat == null || row.lng == null || !row.lastFixAt) return null;
  return { lat: row.lat, lng: row.lng, at: row.lastFixAt };
}

/** Keeps only the single latest fix — never a history (spec F-05/F-17). */
export async function recordFix(userId: string, p: LocationPayload) {
  await sql`
    UPDATE users
    SET last_fix_geo = ST_MakePoint(${p.lng}, ${p.lat})::geography, last_fix_at = ${p.timestamp}
    WHERE id = ${userId}`;
}
