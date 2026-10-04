import { sql } from '../db/client.js';

export type IntegrityKind =
  | 'mock_location'
  | 'impossible_travel'
  | 'attest_failed'
  | 'integrity_failed'
  | 'integrity_missing'
  | 'rate_limited';

/** Best-effort audit trail for suspicious behaviour. Never throws. */
export async function recordIntegrityEvent(userId: string | null, kind: IntegrityKind, detail?: Record<string, unknown>) {
  try {
    await sql`INSERT INTO integrity_events (user_id, kind, detail) VALUES (${userId}, ${kind}, ${detail ? sql.json(detail as never) : null})`;
  } catch {
    // An audit write must never take a request down.
  }
}
