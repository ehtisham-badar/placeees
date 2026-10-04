import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { AppError, notFound } from '../lib/errors.js';
import { limitAction } from '../lib/rateLimit.js';

/** Hide a drop from everyone once this many distinct users have reported it, pending review. */
export const AUTO_HIDE_REPORTS = 3;

export async function safetyRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.post('/v1/reports', async (req, reply) => {
    const body = z
      .object({
        targetType: z.enum(['drop', 'echo', 'user']),
        targetId: z.uuid(),
        reason: z.string().max(500).optional(),
      })
      .parse(req.body);
    await limitAction(req.userId, 'report');

    await sql`
      INSERT INTO reports (reporter_id, target_type, target_id, reason)
      VALUES (${req.userId}, ${body.targetType}, ${body.targetId}, ${body.reason ?? null})`;

    if (body.targetType === 'drop') {
      await sql`
        UPDATE drops SET status = 'pending_moderation', moderation_note = 'auto_hidden_by_reports'
        WHERE id = ${body.targetId} AND status = 'approved'
          AND (SELECT count(DISTINCT reporter_id) FROM reports
               WHERE target_type = 'drop' AND target_id = ${body.targetId} AND resolved_at IS NULL) >= ${AUTO_HIDE_REPORTS}`;
    }
    return reply.code(201).send({ ok: true });
  });

  app.post('/v1/blocks/:userId', async (req, reply) => {
    const { userId } = z.object({ userId: z.uuid() }).parse(req.params);
    if (userId === req.userId) throw new AppError('cannot_block_self', 422);
    await sql`INSERT INTO blocks (blocker_id, blocked_id) VALUES (${req.userId}, ${userId}) ON CONFLICT DO NOTHING`;
    return reply.code(201).send({ ok: true });
  });

  // Lets users block the author of an anonymous drop without learning who they are.
  app.post('/v1/drops/:id/block-author', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const [drop] = await sql<{ creatorId: string }[]>`SELECT creator_id FROM drops WHERE id = ${id}`;
    if (!drop) throw notFound();
    if (drop.creatorId === req.userId) throw new AppError('cannot_block_self', 422);
    await sql`INSERT INTO blocks (blocker_id, blocked_id) VALUES (${req.userId}, ${drop.creatorId}) ON CONFLICT DO NOTHING`;
    return reply.code(201).send({ ok: true });
  });
}
