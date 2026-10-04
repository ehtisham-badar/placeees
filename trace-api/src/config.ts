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
  RUN_JOBS: z
    .enum(['true', 'false', '1', '0'])
    .default('true')
    .transform((v) => v === 'true' || v === '1'),
});

export const config = Env.parse(process.env);
export type Config = typeof config;
