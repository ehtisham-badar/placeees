import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { assertPresentAt } from '../drops/service.js';
import { LocationPayload } from '../integrity/location.js';
import { AppError, notFound } from '../lib/errors.js';
import { ownsMediaKey, signedReadUrl } from '../media/r2.js';
import { limitAction } from '../lib/rateLimit.js';
import { moderate } from '../moderation/moderate.js';

export const MAX_NOW_PHOTOS_PER_DAY = 10;

const IdParam = z.object({ id: z.uuid() });

async function assertThenNowAccess(userId: string, dropId: string) {
  const [d] = await sql<{ type: string; creatorId: string; unlocked: boolean }[]>`
    SELECT d.type, d.creator_id,
           EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = d.id AND u.user_id = ${userId}) AS unlocked
    FROM drops d WHERE d.id = ${dropId} AND d.status = 'approved'`;
  if (!d || d.type !== 'then_now') throw notFound();
  if (d.creatorId !== userId && !d.unlocked) throw new AppError('locked', 403);
}

/** "Now" photos of a Then/Now spot: the place's timeline (spec F-14). */
export async function thenNowRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.get('/v1/drops/:id/now-photos', async (req) => {
    const { id } = IdParam.parse(req.params);
    await assertThenNowAccess(req.userId, id);
    const rows = await sql<{ id: string; mediaKey: string; createdAt: Date; handle: string | null; mine: boolean; pending: boolean }[]>`
      SELECT n.id, n.media_key, n.created_at, u.handle,
             n.user_id = ${req.userId} AS mine, n.status = 'pending_moderation' AS pending
      FROM now_photos n JOIN users u ON u.id = n.user_id
      WHERE n.drop_id = ${id}
        AND (n.status = 'approved' OR (n.user_id = ${req.userId} AND n.status = 'pending_moderation'))
        AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = ${req.userId} AND b.blocked_id = n.user_id)
             OR (b.blocker_id = n.user_id AND b.blocked_id = ${req.userId}))
      ORDER BY n.created_at DESC
      LIMIT 100`;
    return {
      photos: await Promise.all(
        rows.map(async (r) => ({
          id: r.id,
          url: await signedReadUrl(r.mediaKey),
          createdAt: r.createdAt,
          authorHandle: r.handle,
          mine: r.mine,
          pending: r.pending,
        })),
      ),
    };
  });

  app.post('/v1/drops/:id/now-photos', async (req, reply) => {
    const { id } = IdParam.parse(req.params);
    const body = z
      .object({
        mediaKey: z.string().max(200),
        location: LocationPayload,
        heading: z.number().min(0).max(360).optional(),
        pitch: z.number().min(-90).max(90).optional(),
      })
      .parse(req.body);

    await limitAction(req.userId, 'nowPhoto');
    await assertThenNowAccess(req.userId, id);
    if (!ownsMediaKey(req.userId, body.mediaKey)) throw new AppError('media_not_owned', 403);
    const [{ today } = { today: 0 }] = await sql<{ today: number }[]>`
      SELECT count(*)::int AS today FROM now_photos WHERE user_id = ${req.userId} AND created_at > now() - interval '1 day'`;
    if (today >= MAX_NOW_PHOTOS_PER_DAY) throw new AppError('daily_limit', 429);
    // A "now" photo has to be taken now, here.
    await assertPresentAt(req.userId, id, body.location);

    const [photo] = await sql<{ id: string; createdAt: Date }[]>`
      INSERT INTO now_photos (drop_id, user_id, media_key, heading, pitch)
      VALUES (${id}, ${req.userId}, ${body.mediaKey}, ${body.heading ?? null}, ${body.pitch ?? null})
      RETURNING id, created_at`;

    void (async () => {
      const verdict = await moderate({ imageUrl: await signedReadUrl(body.mediaKey) });
      await sql`UPDATE now_photos SET status = ${verdict.approved ? 'approved' : 'rejected'} WHERE id = ${photo!.id}`;
    })().catch((err) => req.log.error(err, 'now photo moderation failed'));

    return reply.code(201).send({ id: photo!.id, createdAt: photo!.createdAt, pending: true });
  });
}
