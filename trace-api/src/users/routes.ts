import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { AppError, notFound } from '../lib/errors.js';
import { destination } from '../lib/geo.js';
import { serializeUser, type UserRow } from './serialize.js';

const HOME_ZONE_FUZZ_M = 50;

async function me(userId: string) {
  const [user] = await sql<UserRow[]>`SELECT * FROM users WHERE id = ${userId}`;
  if (!user) throw notFound();
  return serializeUser(user);
}

export async function userRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.get('/v1/me', async (req) => me(req.userId));

  app.patch('/v1/me', async (req) => {
    const { handle } = z
      .object({ handle: z.string().trim().toLowerCase().regex(/^[a-z0-9_.]{3,20}$/) })
      .parse(req.body);
    const taken = await sql`SELECT 1 FROM users WHERE handle = ${handle} AND id <> ${req.userId}`;
    if (taken.length) throw new AppError('handle_taken', 409);
    await sql`UPDATE users SET handle = ${handle} WHERE id = ${req.userId}`;
    return me(req.userId);
  });

  app.get('/v1/handles/:handle/available', async (req) => {
    const { handle } = z.object({ handle: z.string().toLowerCase() }).parse(req.params);
    const rows = await sql`SELECT 1 FROM users WHERE handle = ${handle} AND id <> ${req.userId}`;
    return { available: /^[a-z0-9_.]{3,20}$/.test(handle) && rows.length === 0 };
  });

  // The home point is stored with a random offset so the exact address is never kept.
  app.put('/v1/me/home-zone', async (req) => {
    const { lat, lng } = z.object({ lat: z.number(), lng: z.number() }).parse(req.body);
    const fuzzed = destination({ lat, lng }, Math.random() * 360, Math.random() * HOME_ZONE_FUZZ_M);
    await sql`UPDATE users SET home_zone = ST_MakePoint(${fuzzed.lng}, ${fuzzed.lat})::geography
              WHERE id = ${req.userId}`;
    return me(req.userId);
  });

  app.delete('/v1/me/home-zone', async (req) => {
    await sql`UPDATE users SET home_zone = NULL WHERE id = ${req.userId}`;
    return me(req.userId);
  });

  app.get('/v1/me/passport', async (req) => {
    const unlocked = await sql`
      SELECT d.id, d.type, d.teaser, d.body, d.created_at, x.unlocked_at,
             CASE WHEN d.is_anonymous THEN NULL ELSE u.handle END AS author_handle
      FROM unlocks x
      JOIN drops d ON d.id = x.drop_id
      JOIN users u ON u.id = d.creator_id
      WHERE x.user_id = ${req.userId} AND d.status = 'approved'
      ORDER BY x.unlocked_at DESC`;
    const created = await sql`
      SELECT d.id, d.type, d.teaser, d.body, d.created_at, d.status,
             (SELECT count(*)::int FROM unlocks x WHERE x.drop_id = d.id) AS unlock_count
      FROM drops d
      WHERE d.creator_id = ${req.userId} AND d.status <> 'removed'
      ORDER BY d.created_at DESC`;
    const stamps = await sql`
      SELECT t.id AS trail_id, t.title, c.completed_at,
             (SELECT count(*)::int FROM trail_stops s WHERE s.trail_id = t.id) AS stops
      FROM trail_completions c JOIN trails t ON t.id = c.trail_id
      WHERE c.user_id = ${req.userId}
      ORDER BY c.completed_at DESC`;
    return { unlocked, created, stamps };
  });
}
