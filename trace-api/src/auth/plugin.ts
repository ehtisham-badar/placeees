import type { FastifyReply, FastifyRequest } from 'fastify';
import { sql } from '../db/client.js';
import { AppError } from '../lib/errors.js';
import { verifyToken } from './jwt.js';

declare module 'fastify' {
  interface FastifyRequest {
    userId: string;
  }
}

// Bans must bite on existing 30-day tokens too; a short cache keeps that to one query per user per minute.
const BAN_TTL_MS = 60_000;
const banCache = new Map<string, { banned: boolean; at: number }>();

export function forgetBanState(userId: string) {
  banCache.delete(userId);
}

async function isBanned(userId: string): Promise<boolean> {
  const hit = banCache.get(userId);
  if (hit && Date.now() - hit.at < BAN_TTL_MS) return hit.banned;
  const [row] = await sql<{ banned: boolean }[]>`SELECT banned_at IS NOT NULL AS banned FROM users WHERE id = ${userId}`;
  const banned = !row || row.banned;
  banCache.set(userId, { banned, at: Date.now() });
  return banned;
}

export async function requireAuth(req: FastifyRequest, _reply: FastifyReply) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw new AppError('unauthorized', 401);
  req.userId = await verifyToken(header.slice(7));
  if (await isBanned(req.userId)) throw new AppError('banned', 403);
}
