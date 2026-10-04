import postgres from 'postgres';

/** Fresh schema, then every migration, exactly as production would apply them. */
export default async function setup() {
  const url = process.env.TEST_DATABASE_URL!;
  const sql = postgres(url, { onnotice: () => {} });
  await sql.unsafe('DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;');
  await sql.end();

  process.env.DATABASE_URL = url;
  const { runMigrations } = await import('../src/db/migrate.js');
  const { sql: appSql } = await import('../src/db/client.js');
  await runMigrations(appSql, () => {});
  await appSql.end();
}
