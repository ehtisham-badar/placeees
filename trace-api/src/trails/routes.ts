import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { fuzzyCircle } from '../drops/fuzz.js';
import { AppError, notFound } from '../lib/errors.js';

export const MIN_STOPS = 3;
export const MAX_STOPS = 15;

const CreateTrail = z.object({
  title: z.string().trim().min(1).max(60),
  stops: z
    .array(z.object({ dropId: z.uuid(), clue: z.string().trim().max(200).optional() }))
    .min(MIN_STOPS)
    .max(MAX_STOPS),
});

interface StopRow {
  seq: number;
  clue: string | null;
  dropId: string;
  type: string;
  teaser: string | null;
  lat: number;
  lng: number;
  unlocked: boolean;
}

export async function trailRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.post('/v1/trails', async (req, reply) => {
    const body = CreateTrail.parse(req.body);
    const ids = body.stops.map((s) => s.dropId);
    if (new Set(ids).size !== ids.length) throw new AppError('duplicate_stop', 422);

    // Stops must be your own public drops that are live (or awaiting review) and not in another trail.
    const owned = await sql<{ id: string }[]>`
      SELECT d.id FROM drops d
      WHERE d.id IN ${sql(ids)} AND d.creator_id = ${req.userId}
        AND d.status IN ('approved', 'pending_moderation') AND d.visibility = 'public'
        AND NOT EXISTS (SELECT 1 FROM trail_stops ts WHERE ts.drop_id = d.id)`;
    if (owned.length !== ids.length) throw new AppError('invalid_stops', 422);

    const trail = await sql.begin(async (tx) => {
      const [t] = await tx<{ id: string }[]>`
        INSERT INTO trails (creator_id, title) VALUES (${req.userId}, ${body.title}) RETURNING id`;
      await tx`
        INSERT INTO trail_stops ${tx(
          body.stops.map((s, i) => ({ trail_id: t!.id, drop_id: s.dropId, seq: i + 1, clue: s.clue || null })),
        )}`;
      return t!;
    });
    return reply.code(201).send({ id: trail.id });
  });

  app.get('/v1/trails/mine', async (req) => {
    const trails = await sql`
      SELECT t.id, t.title, t.created_at,
             (SELECT count(*)::int FROM trail_stops s WHERE s.trail_id = t.id) AS total,
             (SELECT count(*)::int FROM trail_completions c WHERE c.trail_id = t.id) AS completions
      FROM trails t WHERE t.creator_id = ${req.userId}
      ORDER BY t.created_at DESC`;
    return { trails };
  });

  /** A trail with your progress. Clues and stops reveal themselves one at a time. */
  app.get('/v1/trails/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const [trail] = await sql<{ id: string; title: string; creatorId: string; handle: string | null; completedAt: Date | null }[]>`
      SELECT t.id, t.title, t.creator_id, u.handle,
             (SELECT completed_at FROM trail_completions c WHERE c.trail_id = t.id AND c.user_id = ${req.userId})
               AS completed_at
      FROM trails t JOIN users u ON u.id = t.creator_id
      WHERE t.id = ${id}`;
    if (!trail) throw notFound();
    const mine = trail.creatorId === req.userId;

    const stops = await sql<StopRow[]>`
      SELECT s.seq, s.clue, d.id AS drop_id, d.type, d.teaser,
             ST_Y(d.geo::geometry) AS lat, ST_X(d.geo::geometry) AS lng,
             EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = d.id AND u.user_id = ${req.userId}) AS unlocked
      FROM trail_stops s JOIN drops d ON d.id = s.drop_id
      WHERE s.trail_id = ${id} AND d.status <> 'removed'
      ORDER BY s.seq`;

    return {
      id: trail.id,
      title: trail.title,
      creator: { handle: trail.handle },
      mine,
      total: stops.length,
      found: stops.filter((s) => s.unlocked).length,
      completedAt: trail.completedAt,
      stops: stops.map((s, i) => {
        const reached = mine || i === 0 || stops[i - 1]!.unlocked;
        return {
          seq: s.seq,
          unlocked: s.unlocked,
          reached,
          clue: reached ? s.clue : null,
          // Found stops show what they were; the current stop shows where to look (fuzzed).
          drop: mine || s.unlocked ? { id: s.dropId, type: s.type, teaser: s.teaser } : null,
          area: reached && !s.unlocked ? fuzzyCircle(s.dropId, { lat: s.lat, lng: s.lng }) : null,
          dropId: reached ? s.dropId : null,
        };
      }),
    };
  });
}
