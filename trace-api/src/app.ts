import rateLimit from '@fastify/rate-limit';
import Fastify from 'fastify';
import { ZodError } from 'zod';
import { ADMIN_PAGE } from './admin/page.js';
import { adminRoutes } from './admin/routes.js';
import { config } from './config.js';
import { authRoutes } from './auth/routes.js';
import { circleRoutes } from './circles/routes.js';
import { dropRoutes } from './drops/routes.js';
import { echoRoutes } from './echoes/routes.js';
import { AppError } from './lib/errors.js';
import { attestRoutes } from './integrity/routes.js';
import { deviceRoutes } from './push/routes.js';
import { relayRoutes } from './relays/routes.js';
import { safetyRoutes } from './safety/routes.js';
import { thenNowRoutes } from './thennow/routes.js';
import { trailRoutes } from './trails/routes.js';
import { eventRoutes } from './metrics/routes.js';
import { localMediaRoutes } from './media/local.js';
import { userRoutes } from './users/routes.js';
import { venueRoutes } from './venues/routes.js';

export function buildApp() {
  const app = Fastify({ logger: { level: process.env.LOG_LEVEL ?? 'info' } });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof AppError) return reply.code(err.status).send({ error: err.code });
    if (err instanceof ZodError) return reply.code(400).send({ error: 'invalid_request', issues: err.issues });
    const status = (err as { statusCode?: number }).statusCode;
    if (status === 429) return reply.code(429).send({ error: 'rate_limited' });
    if (status && status >= 400 && status < 500) return reply.code(status).send({ error: 'bad_request' });
    req.log.error(err);
    return reply.code(500).send({ error: 'internal' });
  });

  // Per-IP ceiling for everything; per-user action limits live in lib/rateLimit.ts.
  app.register(rateLimit, {
    max: 300,
    timeWindow: '1 minute',
    errorResponseBuilder: (_req, ctx) => ({ statusCode: 429, error: 'rate_limited', retryAfter: ctx.after }),
  });

  app.get('/health', async () => ({ ok: true }));
  if (config.ADMIN_TOKEN) {
    app.get('/admin', async (_req, reply) =>
      reply
        .header('content-type', 'text/html; charset=utf-8')
        .header('x-frame-options', 'DENY')
        .header('cache-control', 'no-store')
        .send(ADMIN_PAGE),
    );
  }
  app.register(authRoutes);
  app.register(userRoutes);
  app.register(dropRoutes);
  app.register(safetyRoutes);
  app.register(deviceRoutes);
  app.register(trailRoutes);
  app.register(echoRoutes);
  app.register(circleRoutes);
  app.register(relayRoutes);
  app.register(thenNowRoutes);
  app.register(attestRoutes);
  app.register(adminRoutes);
  app.register(venueRoutes);
  app.register(eventRoutes);
  app.register(localMediaRoutes);
  return app;
}
