import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { sql } from '../db/client.js';
import { AppError } from '../lib/errors.js';
import { serializeUser, type UserRow } from '../users/serialize.js';
import { issueToken } from './jwt.js';
import { verifyAppleIdentity, verifyGoogleIdentity } from './providers.js';

type Provider = 'apple_sub' | 'google_sub' | 'dev_sub';

async function signIn(provider: Provider, sub: string) {
  const [user] = await sql<UserRow[]>`
    INSERT INTO users ${sql({ [provider]: sub })}
    ON CONFLICT (${sql(provider)}) DO UPDATE SET ${sql(provider)} = EXCLUDED.${sql(provider)}
    RETURNING *`;
  if (!user) throw new AppError('sign_in_failed', 500);
  if (user.bannedAt) throw new AppError('banned', 403);
  return { token: await issueToken(user.id), user: serializeUser(user) };
}

// Sign-in is cheap to spam and expensive to verify: 10 a minute per IP.
const strict = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };

export async function authRoutes(app: FastifyInstance) {
  app.post('/v1/auth/apple', strict, async (req) => {
    const { identityToken } = z.object({ identityToken: z.string().min(1) }).parse(req.body);
    return signIn('apple_sub', await verifyAppleIdentity(identityToken));
  });

  app.post('/v1/auth/google', strict, async (req) => {
    const { idToken } = z.object({ idToken: z.string().min(1) }).parse(req.body);
    return signIn('google_sub', await verifyGoogleIdentity(idToken));
  });

  if (config.ALLOW_DEV_LOGIN) {
    app.post('/v1/auth/dev', strict, async (req) => {
      const { name, code } = z.object({ name: z.string().min(1).max(40), code: z.string().max(200).optional() }).parse(req.body);
      if (config.DEV_LOGIN_CODE) {
        const a = Buffer.from(code ?? '');
        const b = Buffer.from(config.DEV_LOGIN_CODE);
        if (a.length !== b.length || !timingSafeEqual(a, b)) throw new AppError('unauthorized', 401);
      }
      return signIn('dev_sub', name);
    });
  }
}
