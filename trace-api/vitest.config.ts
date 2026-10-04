import { configDefaults, defineConfig } from 'vitest/config';

// Unit tests only. The PostGIS suite in test-db/ runs via `npm run test:db`.
export default defineConfig({
  test: {
    exclude: [...configDefaults.exclude, 'test-db/**'],
  },
});
