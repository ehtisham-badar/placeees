import { sql } from '../db/client.js';
import { pushToUsers } from '../push/send.js';

/**
 * Time capsules (F-09): notify the creator and recipients once `unlock_at` passes.
 * The UPDATE … RETURNING claims each capsule atomically, so concurrent runners never double-send.
 */
export async function notifyOpenedCapsules(): Promise<number> {
  const due = await sql<{ id: string; creatorId: string; recipientIds: string[] | null; teaser: string | null }[]>`
    UPDATE drops SET capsule_notified_at = now()
    WHERE id IN (
      SELECT id FROM drops
      WHERE unlock_at <= now() AND capsule_notified_at IS NULL AND status = 'approved'
      ORDER BY unlock_at
      LIMIT 100
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id, creator_id, recipient_ids, teaser`;

  for (const capsule of due) {
    await pushToUsers([capsule.creatorId, ...(capsule.recipientIds ?? [])], {
      title: 'A time capsule just opened',
      body: capsule.teaser ?? 'Something sealed at a place you know is ready. Go and open it.',
      data: { dropId: capsule.id, kind: 'capsule_opened' },
    });
  }
  return due.length;
}

export function startCapsuleJob(log: { error: (o: unknown, m: string) => void }, everyMs = 60_000) {
  const tick = () => notifyOpenedCapsules().catch((err) => log.error(err, 'capsule job failed'));
  const timer = setInterval(tick, everyMs);
  timer.unref();
  return () => clearInterval(timer);
}
