import { defineConfig } from 'vitest/config';

/**
 * End-to-end tests against a real PostGIS database. Destroys and recreates the `public` schema of
 * TEST_DATABASE_URL, so never point it at a database you care about.
 *   TEST_DATABASE_URL=postgres://localhost:5432/trace_test npm run test:db
 */
const url = process.env.TEST_DATABASE_URL;
if (!url) throw new Error('Set TEST_DATABASE_URL to a throwaway PostGIS database.');

export default defineConfig({
  test: {
    include: ['test-db/**/*.test.ts'],
    globalSetup: ['test-db/setup.ts'],
    fileParallelism: false,
    testTimeout: 20_000,
    env: {
      DATABASE_URL: url,
      ALLOW_DEV_LOGIN: 'true',
      ADMIN_TOKEN: 'test-admin-token-test-admin-token',
      RUN_JOBS: 'false',
      LOG_LEVEL: 'silent',
      INTEGRITY_MODE: 'off',
      LOCAL_MEDIA_DIR: '/tmp/trace-test-media',
      PUBLIC_API_URL: 'http://localhost',
    },
  },
});
