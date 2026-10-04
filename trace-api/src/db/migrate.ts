import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { sql } from './client.js';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations');

async function migrate() {
  await sql`CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ DEFAULT now())`;
  const applied = new Set((await sql<{ name: string }[]>`SELECT name FROM schema_migrations`).map((r) => r.name));
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();

  for (const file of files) {
    if (applied.has(file)) continue;
    const body = await readFile(path.join(dir, file), 'utf8');
    await sql.begin(async (tx) => {
      await tx.unsafe(body);
      await tx`INSERT INTO schema_migrations (name) VALUES (${file})`;
    });
    console.log(`applied ${file}`);
  }
  await sql.end();
}

migrate().catch((err) => {
  console.error(err);
  process.exit(1);
});
