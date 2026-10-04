import Fastify from 'fastify';
import { ZodError } from 'zod';
import { authRoutes } from './auth/routes.js';
import { circleRoutes } from './circles/routes.js';
import { dropRoutes } from './drops/routes.js';
import { echoRoutes } from './echoes/routes.js';
import { AppError } from './lib/errors.js';
import { deviceRoutes } from './push/routes.js';
import { relayRoutes } from './relays/routes.js';
import { safetyRoutes } from './safety/routes.js';
import { thenNowRoutes } from './thennow/routes.js';
import { trailRoutes } from './trails/routes.js';
import { userRoutes } from './users/routes.js';

export function buildApp() {
  const app = Fastify({ logger: { level: process.env.LOG_LEVEL ?? 'info' } });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof AppError) return reply.code(err.status).send({ error: err.code });
    if (err instanceof ZodError) return reply.code(400).send({ error: 'invalid_request', issues: err.issues });
    req.log.error(err);
    return reply.code(500).send({ error: 'internal' });
  });

  app.get('/health', async () => ({ ok: true }));
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
  return app;
}
