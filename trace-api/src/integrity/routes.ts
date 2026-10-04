import { randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { config } from '../config.js';
import { sql } from '../db/client.js';
import { AppError } from '../lib/errors.js';
import { AttestError, verifyAttestation } from './appAttest.js';
import { recordIntegrityEvent } from './events.js';
import { appleAppId } from './verify.js';

/** iOS App Attest key registration (spec F-17). */
export async function attestRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.post('/v1/attest/challenge', async (req) => {
    const challenge = randomBytes(32).toString('base64');
    await sql`
      INSERT INTO attest_challenges (challenge, user_id, expires_at)
      VALUES (${challenge}, ${req.userId}, now() + interval '5 minutes')`;
    return { challenge };
  });

  app.post('/v1/attest/register', async (req, reply) => {
    const body = z
      .object({ keyId: z.string().min(10).max(100), attestation: z.string().max(20_000), challenge: z.string() })
      .parse(req.body);
    if (!config.APPLE_TEAM_ID) throw new AppError('attest_not_configured', 503);

    // Challenges are single-use.
    const [used] = await sql`
      DELETE FROM attest_challenges
      WHERE challenge = ${body.challenge} AND user_id = ${req.userId} AND expires_at > now()
      RETURNING challenge`;
    if (!used) throw new AppError('bad_challenge', 422);

    try {
      const { publicKeyPem, env } = verifyAttestation({
        attestation: Buffer.from(body.attestation, 'base64'),
        challenge: Buffer.from(body.challenge),
        keyId: body.keyId,
        appId: appleAppId(),
      });
      await sql`
        INSERT INTO attest_keys (key_id, user_id, public_key, env) VALUES (${body.keyId}, ${req.userId}, ${publicKeyPem}, ${env})
        ON CONFLICT (key_id) DO UPDATE SET user_id = EXCLUDED.user_id, public_key = EXCLUDED.public_key, counter = 0`;
      return reply.code(201).send({ ok: true, env });
    } catch (err) {
      const reason = err instanceof AttestError ? err.message : 'error';
      await recordIntegrityEvent(req.userId, 'attest_failed', { reason, stage: 'register' });
      throw new AppError('attestation_rejected', 422);
    }
  });
}
