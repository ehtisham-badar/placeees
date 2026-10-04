import postgres from 'postgres';
import { config } from '../config.js';

export const sql = postgres(config.DATABASE_URL, {
  max: 10,
  transform: postgres.camel,
  // "already exists, skipping" from idempotent migrations is noise, not news.
  onnotice: () => {},
});

export type Sql = typeof sql;
