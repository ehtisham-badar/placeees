import { randomInt } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { AppError, notFound } from '../lib/errors.js';

export const MAX_MEMBERS = 50;
export const MAX_OWNED_CIRCLES = 10;

// No 0/O, 1/I/L: invite codes get read aloud and typed on phones.
const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

export function inviteCode(length = 8): string {
  let out = '';
  for (let i = 0; i < length; i++) out += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return out;
}

export function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

const IdParam = z.object({ id: z.uuid() });

async function circleFor(userId: string, circleId: string) {
  const [c] = await sql<{ id: string; name: string; inviteCode: string; ownerId: string; memberCount: number }[]>`
    SELECT c.id, c.name, c.invite_code, c.owner_id,
           (SELECT count(*)::int FROM circle_members m WHERE m.circle_id = c.id) AS member_count
    FROM circles c
    JOIN circle_members me ON me.circle_id = c.id AND me.user_id = ${userId}
    WHERE c.id = ${circleId}`;
  if (!c) throw notFound();
  return {
    id: c.id,
    name: c.name,
    inviteCode: c.inviteCode,
    memberCount: c.memberCount,
    isOwner: c.ownerId === userId,
  };
}

export async function circleRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.get('/v1/circles', async (req) => {
    const circles = await sql`
      SELECT c.id, c.name, c.invite_code, c.owner_id = ${req.userId} AS is_owner,
             (SELECT count(*)::int FROM circle_members m WHERE m.circle_id = c.id) AS member_count
      FROM circles c JOIN circle_members me ON me.circle_id = c.id AND me.user_id = ${req.userId}
      ORDER BY me.joined_at DESC`;
    return { circles };
  });

  app.post('/v1/circles', async (req, reply) => {
    const { name } = z.object({ name: z.string().trim().min(1).max(40) }).parse(req.body);
    const [{ owned } = { owned: 0 }] = await sql<{ owned: number }[]>`
      SELECT count(*)::int AS owned FROM circles WHERE owner_id = ${req.userId}`;
    if (owned >= MAX_OWNED_CIRCLES) throw new AppError('circle_limit', 429);

    const id = await sql.begin(async (tx) => {
      // Codes are random; retry the rare collision.
      for (let attempt = 0; attempt < 5; attempt++) {
        const [c] = await tx<{ id: string }[]>`
          INSERT INTO circles (owner_id, name, invite_code) VALUES (${req.userId}, ${name}, ${inviteCode()})
          ON CONFLICT (invite_code) DO NOTHING RETURNING id`;
        if (c) {
          await tx`INSERT INTO circle_members (circle_id, user_id) VALUES (${c.id}, ${req.userId})`;
          return c.id;
        }
      }
      throw new AppError('internal', 500);
    });
    return reply.code(201).send(await circleFor(req.userId, id));
  });

  app.post('/v1/circles/join', async (req) => {
    const { code } = z.object({ code: z.string().min(4).max(20) }).parse(req.body);
    const [c] = await sql<{ id: string; members: number }[]>`
      SELECT c.id, (SELECT count(*)::int FROM circle_members m WHERE m.circle_id = c.id) AS members
      FROM circles c WHERE c.invite_code = ${normalizeCode(code)}`;
    if (!c) throw new AppError('invalid_code', 404);
    const [already] = await sql`SELECT 1 FROM circle_members WHERE circle_id = ${c.id} AND user_id = ${req.userId}`;
    if (!already) {
      if (c.members >= MAX_MEMBERS) throw new AppError('circle_full', 409);
      await sql`INSERT INTO circle_members (circle_id, user_id) VALUES (${c.id}, ${req.userId}) ON CONFLICT DO NOTHING`;
    }
    return circleFor(req.userId, c.id);
  });

  app.get('/v1/circles/:id', async (req) => {
    const { id } = IdParam.parse(req.params);
    const circle = await circleFor(req.userId, id);
    const members = await sql`
      SELECT u.handle, (c.owner_id = u.id) AS is_owner, m.joined_at
      FROM circle_members m JOIN users u ON u.id = m.user_id JOIN circles c ON c.id = m.circle_id
      WHERE m.circle_id = ${id}
      ORDER BY (c.owner_id = u.id) DESC, m.joined_at`;
    return { ...circle, members };
  });

  app.post('/v1/circles/:id/leave', async (req, reply) => {
    const { id } = IdParam.parse(req.params);
    const circle = await circleFor(req.userId, id);
    if (circle.isOwner) throw new AppError('owner_cannot_leave', 422);
    await sql`DELETE FROM circle_members WHERE circle_id = ${id} AND user_id = ${req.userId}`;
    return reply.code(204).send();
  });
}
