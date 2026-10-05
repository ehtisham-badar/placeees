import { z } from 'zod';

const bool = z
  .enum(['true', 'false', '1', '0'])
  .default('false')
  .transform((v) => v === 'true' || v === '1');

const Env = z.object({
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().default('postgres://trace:trace@localhost:5432/trace'),
  JWT_SECRET: z.string().min(32).default('dev-only-secret-dev-only-secret-dev-only'),
  APPLE_BUNDLE_ID: z.string().default('app.trace.mobile'),
  GOOGLE_CLIENT_IDS: z
    .string()
    .default('')
    .transform((s) => s.split(',').map((x) => x.trim()).filter(Boolean)),
  ALLOW_DEV_LOGIN: bool,
  NEARBY_RADIUS_M: z.coerce.number().default(2000),
  R2_ACCOUNT_ID: z.string().default(''),
  R2_ACCESS_KEY_ID: z.string().default(''),
  R2_SECRET_ACCESS_KEY: z.string().default(''),
  R2_BUCKET: z.string().default('trace-media'),
  OPENAI_API_KEY: z.string().default(''),
  // APNs token auth (.p8 key contents; literal \n sequences are accepted)
  APNS_KEY_ID: z.string().default(''),
  APNS_TEAM_ID: z.string().default(''),
  APNS_PRIVATE_KEY: z.string().default(''),
  APNS_PRODUCTION: bool,
  // Firebase Cloud Messaging HTTP v1 (service account)
  FCM_PROJECT_ID: z.string().default(''),
  FCM_CLIENT_EMAIL: z.string().default(''),
  FCM_PRIVATE_KEY: z.string().default(''),
  // F-17 integrity: off (dev), report (log only) or enforce (reject untrusted requests).
  INTEGRITY_MODE: z.enum(['off', 'report', 'enforce']).default('off'),
  APPLE_TEAM_ID: z.string().default(''),
  ANDROID_PACKAGE: z.string().default('app.trace.mobile'),
  // Comma-separated SHA-256 fingerprints of the Android signing certs (for assetlinks.json).
  ANDROID_CERT_SHA256: z
    .string()
    .default('')
    .transform((s) => s.split(',').map((x) => x.trim()).filter(Boolean)),
  // Google service account for Play Integrity decoding (falls back to the FCM one).
  GOOGLE_SA_CLIENT_EMAIL: z.string().default(''),
  GOOGLE_SA_PRIVATE_KEY: z.string().default(''),
  // Development media store (used when R2 isn't configured): a folder on the API's disk, and the
  // URL phones use to reach this API (e.g. http://192.168.1.20:3000).
  LOCAL_MEDIA_DIR: z.string().default(''),
  PUBLIC_API_URL: z.string().default(''),
  // F-05 admin API and page. Unset = admin disabled.
  ADMIN_TOKEN: z.string().default(''),
  // F-16 venue links.
  PUBLIC_WEB_URL: z.string().default('https://trace.app'),
  APP_STORE_URL: z.string().default(''),
  PLAY_STORE_URL: z.string().default(''),
  RUN_JOBS: z
    .enum(['true', 'false', '1', '0'])
    .default('true')
    .transform((v) => v === 'true' || v === '1'),
});

export const config = Env.parse(process.env);
export type Config = typeof config;
