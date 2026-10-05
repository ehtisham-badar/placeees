import { randomUUID } from 'node:crypto';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config.js';
import { AppError } from '../lib/errors.js';
import { localMediaEnabled, localUrl } from './local.js';

const enabled = Boolean(config.R2_ACCOUNT_ID && config.R2_ACCESS_KEY_ID && config.R2_SECRET_ACCESS_KEY);

const client = enabled
  ? new S3Client({
      region: 'auto',
      endpoint: `https://${config.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId: config.R2_ACCESS_KEY_ID, secretAccessKey: config.R2_SECRET_ACCESS_KEY },
    })
  : null;

export const MEDIA_READ_TTL_S = 600;

export const CONTENT_TYPES = { 'image/jpeg': 'jpg', 'audio/mp4': 'm4a', 'audio/aac': 'aac' } as const;
export type MediaContentType = keyof typeof CONTENT_TYPES;

function requireClient(): S3Client {
  if (!client) throw new AppError('media_unavailable', 503);
  return client;
}

export async function presignUpload(userId: string, contentType: MediaContentType) {
  const key = `drops/${userId}/${randomUUID()}.${CONTENT_TYPES[contentType]}`;
  if (!client && localMediaEnabled) return { key, url: localUrl('put', key, 300), headers: { 'content-type': contentType } };
  const url = await getSignedUrl(
    requireClient(),
    new PutObjectCommand({ Bucket: config.R2_BUCKET, Key: key, ContentType: contentType }),
    { expiresIn: 300 },
  );
  return { key, url, headers: { 'content-type': contentType } };
}

export async function signedReadUrl(key: string): Promise<string> {
  if (!client && localMediaEnabled) return localUrl('get', key, MEDIA_READ_TTL_S);
  return getSignedUrl(requireClient(), new GetObjectCommand({ Bucket: config.R2_BUCKET, Key: key }), {
    expiresIn: MEDIA_READ_TTL_S,
  });
}

/** Media keys are namespaced per user, so a client can only attach media it uploaded itself. */
export function ownsMediaKey(userId: string, key: string): boolean {
  return key.startsWith(`drops/${userId}/`) && !key.includes('..');
}
