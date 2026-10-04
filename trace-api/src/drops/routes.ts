import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { requireAuth } from '../auth/plugin.js';
import { Conditions } from '../conditions/schema.js';
import { LocationPayload } from '../integrity/location.js';
import { CONTENT_TYPES, presignUpload, type MediaContentType } from '../media/r2.js';
import { createDrop, getDropContent, nearHint, nearbyDrops, unlockDrop } from './service.js';

const CreateDrop = z.object({
  type: z.enum(['text', 'photo', 'voice']),
  body: z.string().max(500).optional(),
  mediaKey: z.string().max(200).optional(),
  teaser: z.string().max(60).optional(),
  isAnonymous: z.boolean().default(false),
  location: LocationPayload,
  conditions: Conditions.optional(),
  revealConditions: z.boolean().default(false),
  unlockAt: z.iso.datetime({ offset: true }).transform((s) => new Date(s)).optional(),
  recipientHandles: z.array(z.string().max(21)).max(20).optional(),
  circleId: z.uuid().optional(),
});

const Nearby = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().positive().max(5000).optional(),
});

const IdParam = z.object({ id: z.uuid() });

export async function dropRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.post('/v1/media/presign', async (req) => {
    const contentTypes = Object.keys(CONTENT_TYPES) as [MediaContentType, ...MediaContentType[]];
    const { contentType } = z.object({ contentType: z.enum(contentTypes) }).parse(req.body);
    return presignUpload(req.userId, contentType);
  });

  app.post('/v1/drops', async (req, reply) => {
    const drop = await createDrop(req.userId, CreateDrop.parse(req.body));
    return reply.code(201).send(drop);
  });

  app.get('/v1/drops/nearby', async (req) => {
    const q = Nearby.parse(req.query);
    return { drops: await nearbyDrops(req.userId, q.lat, q.lng, q.radius ?? config.NEARBY_RADIUS_M) };
  });

  app.get('/v1/drops/:id', async (req) => getDropContent(req.userId, IdParam.parse(req.params).id));

  app.post('/v1/drops/:id/unlock', async (req) => {
    const { location } = z.object({ location: LocationPayload }).parse(req.body);
    return unlockDrop(req.userId, IdParam.parse(req.params).id, location);
  });

  app.post('/v1/drops/:id/near-hint', async (req) => {
    const { location } = z.object({ location: LocationPayload }).parse(req.body);
    return nearHint(req.userId, IdParam.parse(req.params).id, location);
  });
}
