import { createHmac, timingSafeEqual } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

/**
 * Development media store: files on the API's disk behind HMAC-signed, expiring URLs, with the same
 * contract as R2's presigned URLs. Lets photo, Then/Now and voice drops work on a phone against a
 * local API. Production uses R2.
 */
export const localMediaEnabled = Boolean(config.LOCAL_MEDIA_DIR && config.PUBLIC_API_URL);

/** Upload caps per type. 30 s of AAC is ~250 KB; photos are compressed to ≤ 1.5 MB on the device. */
export const MAX_BYTES: Record<string, number> = {
  'image/jpeg': 2_000_000,
  'audio/mp4': 1_000_000,
  'audio/aac': 1_000_000,
};
const EXT_TYPES: Record<string, string> = { jpg: 'image/jpeg', m4a: 'audio/mp4', aac: 'audio/aac' };
const KEY = /^drops\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|m4a|aac)$/;

type Op = 'put' | 'get';

function sign(op: Op, key: string, exp: number): string {
  return createHmac('sha256', config.JWT_SECRET).update(`trace-media|${op}|${key}|${exp}`).digest('base64url');
}

export function localUrl(op: Op, key: string, ttlS: number, now = Date.now()): string {
  const exp = Math.floor(now / 1000) + ttlS;
  const q = new URLSearchParams({ key, exp: String(exp), sig: sign(op, key, exp) });
  return `${config.PUBLIC_API_URL}/v1/media/local/${op === 'put' ? 'upload' : 'file'}?${q}`;
}

export function verifyLocal(op: Op, key: string, exp: number, sig: string, now = Date.now()): boolean {
  if (!KEY.test(key) || exp * 1000 < now) return false;
  const a = Buffer.from(sig);
  const b = Buffer.from(sign(op, key, exp));
  return a.length === b.length && timingSafeEqual(a, b);
}

const Query = z.object({ key: z.string().max(200), exp: z.coerce.number().int(), sig: z.string().max(100) });
const filePath = (key: string) => path.join(config.LOCAL_MEDIA_DIR, key);

export async function localMediaRoutes(app: FastifyInstance) {
  if (!localMediaEnabled) return;

  app.addContentTypeParser(Object.keys(MAX_BYTES), { parseAs: 'buffer', bodyLimit: 2_000_000 }, (_req, body, done) =>
    done(null, body),
  );

  app.put('/v1/media/local/upload', async (req, reply) => {
    const q = Query.parse(req.query);
    if (!verifyLocal('put', q.key, q.exp, q.sig)) throw new AppError('forbidden', 403);
    const expected = EXT_TYPES[q.key.split('.').pop()!];
    const type = req.headers['content-type']?.split(';')[0];
    if (!expected || type !== expected) throw new AppError('wrong_content_type', 415);
    const body = req.body as Buffer;
    if (!Buffer.isBuffer(body) || body.length === 0 || body.length > MAX_BYTES[type]!) throw new AppError('too_large', 413);
    await mkdir(path.dirname(filePath(q.key)), { recursive: true });
    await writeFile(filePath(q.key), body);
    return reply.code(200).send();
  });

  app.get('/v1/media/local/file', async (req, reply) => {
    const q = Query.parse(req.query);
    if (!verifyLocal('get', q.key, q.exp, q.sig)) throw new AppError('forbidden', 403);
    const info = await stat(filePath(q.key)).catch(() => null);
    if (!info) throw new AppError('not_found', 404);
    return reply
      .header('content-type', EXT_TYPES[q.key.split('.').pop()!]!)
      .header('content-length', info.size)
      .header('cache-control', 'private, max-age=600')
      .send(createReadStream(filePath(q.key)));
  });
}
