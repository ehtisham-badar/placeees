import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { assertPresentAt } from '../drops/service.js';
import { LocationPayload } from '../integrity/location.js';
import { AppError, notFound } from '../lib/errors.js';
import { moderate } from '../moderation/moderate.js';
import { pushToUsers } from '../push/send.js';

export const MAX_ECHOES_PER_DAY = 20;

const IdParam = z.object({ id: z.uuid() });

/** Echoes are for people who have opened the drop (or its creator). */
async function assertCanRead(userId: string, dropId: string) {
  const [row] = await sql<{ creatorId: string; unlocked: boolean }[]>`
    SELECT d.creator_id,
           EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = d.id AND u.user_id = ${userId}) AS unlocked
    FROM drops d WHERE d.id = ${dropId} AND d.status = 'approved'`;
  if (!row) throw notFound();
  if (row.creatorId !== userId && !row.unlocked) throw new AppError('locked', 403);
  return row;
}

export async function echoRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.get('/v1/drops/:id/echoes', async (req) => {
    const { id } = IdParam.parse(req.params);
    await assertCanRead(req.userId, id);
    const echoes = await sql`
      SELECT e.id, e.body, e.created_at, u.handle AS author_handle,
             e.user_id = ${req.userId} AS mine, e.status = 'pending_moderation' AS pending
      FROM echoes e JOIN users u ON u.id = e.user_id
      WHERE e.drop_id = ${id}
        AND (e.status = 'approved' OR (e.user_id = ${req.userId} AND e.status = 'pending_moderation'))
        AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = ${req.userId} AND b.blocked_id = e.user_id)
             OR (b.blocker_id = e.user_id AND b.blocked_id = ${req.userId}))
      ORDER BY e.created_at ASC
      LIMIT 500`;
    return { echoes };
  });

  // Same presence check as an unlock (spec F-11): you have to be standing there.
  app.post('/v1/drops/:id/echoes', async (req, reply) => {
    const { id } = IdParam.parse(req.params);
    const body = z
      .object({ body: z.string().trim().min(1).max(280), location: LocationPayload })
      .parse(req.body);

    const drop = await assertCanRead(req.userId, id);
    const [{ today } = { today: 0 }] = await sql<{ today: number }[]>`
      SELECT count(*)::int AS today FROM echoes WHERE user_id = ${req.userId} AND created_at > now() - interval '1 day'`;
    if (today >= MAX_ECHOES_PER_DAY) throw new AppError('daily_limit', 429);
    await assertPresentAt(req.userId, id, body.location);

    const [echo] = await sql<{ id: string; createdAt: Date }[]>`
      INSERT INTO echoes (drop_id, user_id, body) VALUES (${id}, ${req.userId}, ${body.body})
      RETURNING id, created_at`;

    void (async () => {
      const verdict = await moderate({ text: body.body });
      await sql`
        UPDATE echoes SET status = ${verdict.approved ? 'approved' : 'rejected'},
                          moderation_note = ${verdict.approved ? null : verdict.reason}
        WHERE id = ${echo!.id} AND status = 'pending_moderation'`;
      if (verdict.approved && drop.creatorId !== req.userId) {
        await pushToUsers([drop.creatorId], {
          title: 'Someone was here',
          body: 'A visitor left an echo on your drop.',
          data: { dropId: id, kind: 'echo' },
        });
      }
    })().catch((err) => req.log.error(err, 'echo moderation failed'));

    return reply.code(201).send({ id: echo!.id, createdAt: echo!.createdAt, pending: true });
  });
}
