import { sql } from '../db/client.js';
import { pushToUsers } from '../push/send.js';

/** Relays not dropped within 7 days go back to where they were picked up (spec F-13). */
export async function returnOverdueRelays(): Promise<number> {
  const returned = await sql<{ carrierId: string; dropId: string; teaser: string | null }[]>`
    WITH due AS (
      UPDATE relay_hops
      SET dropped_at = now(), dropped_geo = pickup_geo, returned = true
      WHERE dropped_at IS NULL AND deadline_at <= now()
      RETURNING drop_id, carrier_id
    )
    UPDATE drops d SET relay_carrier_id = NULL
    FROM due WHERE d.id = due.drop_id AND d.relay_carrier_id = due.carrier_id
    RETURNING due.carrier_id, d.id AS drop_id, d.teaser`;

  for (const r of returned) {
    await pushToUsers([r.carrierId], {
      title: 'A relay went home',
      body: 'Its 7 days with you ran out, so it returned to where you found it.',
      data: { dropId: r.dropId, kind: 'relay_returned' },
    });
  }
  return returned.length;
}

/** Warn carriers a day before their relay goes home. */
export async function warnRelayDeadlines(): Promise<number> {
  const due = await sql<{ carrierId: string; dropId: string }[]>`
    UPDATE relay_hops SET warned_at = now()
    WHERE dropped_at IS NULL AND warned_at IS NULL AND deadline_at <= now() + interval '24 hours'
    RETURNING carrier_id, drop_id`;
  for (const d of due) {
    await pushToUsers([d.carrierId], {
      title: 'One day left',
      body: 'The relay you’re carrying needs a new home by tomorrow, at least 1 km from where you found it.',
      data: { dropId: d.dropId, kind: 'relay_deadline' },
    });
  }
  return due.length;
}
