import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';

export async function deviceRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.post('/v1/devices', async (req, reply) => {
    const { token, platform } = z
      .object({ token: z.string().min(10).max(4096), platform: z.enum(['ios', 'android']) })
      .parse(req.body);
    // A token belongs to whoever registered it last (e.g. after switching accounts).
    await sql`
      INSERT INTO devices (token, user_id, platform) VALUES (${token}, ${req.userId}, ${platform})
      ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = now()`;
    return reply.code(204).send();
  });

  app.delete('/v1/devices/:token', async (req, reply) => {
    const { token } = z.object({ token: z.string() }).parse(req.params);
    await sql`DELETE FROM devices WHERE token = ${token} AND user_id = ${req.userId}`;
    return reply.code(204).send();
  });
}
