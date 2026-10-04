import type { FastifyReply, FastifyRequest } from 'fastify';
import { AppError } from '../lib/errors.js';
import { verifyToken } from './jwt.js';

declare module 'fastify' {
  interface FastifyRequest {
    userId: string;
  }
}

export async function requireAuth(req: FastifyRequest, _reply: FastifyReply) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw new AppError('unauthorized', 401);
  req.userId = await verifyToken(header.slice(7));
}
