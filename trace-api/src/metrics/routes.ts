import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';

/** The events listed in spec §11. Anything else is dropped. */
export const EVENT_NAMES = [
  'app_open',
  'map_view',
  'compass_start',
  'unlock_attempt',
  'unlock_success',
  'drop_created',
  'echo_created',
  'trail_started',
  'trail_completed',
  'relay_picked',
  'relay_dropped',
  'capsule_opened',
] as const;

const Events = z.object({
  events: z
    .array(
      z.object({
        name: z.enum(EVENT_NAMES),
        at: z.iso.datetime({ offset: true }),
        // Small, flat, non-identifying props only (e.g. failure reason, drop type).
        props: z.record(z.string().max(40), z.union([z.string().max(80), z.number(), z.boolean()])).optional(),
      }),
    )
    .max(50),
});

const MAX_CLOCK_SKEW_MS = 24 * 3_600_000;

export async function eventRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  app.post('/v1/events', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { events } = Events.parse(req.body);
    const now = Date.now();
    // Keep device timestamps unless they're absurd.
    const rows = events.map((e) => {
      const at = Date.parse(e.at);
      return {
        user_id: req.userId,
        name: e.name,
        props: e.props ?? null,
        at: new Date(Math.abs(now - at) > MAX_CLOCK_SKEW_MS ? now : at),
      };
    });
    if (rows.length) await sql`INSERT INTO app_events ${sql(rows, 'user_id', 'name', 'props', 'at')}`;
    return reply.code(204).send();
  });
}

/** Pilot dashboard numbers (spec §11), computed straight from the tables. */
export async function pilotMetrics(days: number) {
  const since = sql`now() - make_interval(days => ${days})`;
  const [m] = await sql<Record<string, number | null>[]>`
    WITH cohort AS (SELECT id, created_at FROM users WHERE created_at > ${since})
    SELECT
      (SELECT count(*)::int FROM cohort) AS new_users,
      -- "First session": an unlock within 2 hours of signing up.
      (SELECT round(avg(CASE WHEN EXISTS (
          SELECT 1 FROM unlocks u WHERE u.user_id = c.id AND u.unlocked_at < c.created_at + interval '2 hours'
        ) THEN 1.0 ELSE 0 END), 3) FROM cohort c) AS first_session_unlock_rate,
      (SELECT round(avg(CASE WHEN EXISTS (
          SELECT 1 FROM app_events e WHERE e.user_id = c.id AND e.name = 'app_open'
            AND e.at >= c.created_at + interval '1 day' AND e.at < c.created_at + interval '2 days'
        ) THEN 1.0 ELSE 0 END), 3) FROM cohort c WHERE c.created_at < now() - interval '2 days') AS d1_retention,
      (SELECT round(avg(CASE WHEN EXISTS (
          SELECT 1 FROM app_events e WHERE e.user_id = c.id AND e.name = 'app_open'
            AND e.at >= c.created_at + interval '7 days' AND e.at < c.created_at + interval '8 days'
        ) THEN 1.0 ELSE 0 END), 3) FROM users c WHERE c.created_at < now() - interval '8 days'
          AND c.created_at > now() - interval '8 days' - make_interval(days => ${days})) AS d7_retention,
      (SELECT count(DISTINCT user_id)::int FROM app_events WHERE name = 'app_open' AND at > now() - interval '7 days') AS wau,
      (SELECT round(count(*)::numeric / nullif((SELECT count(DISTINCT user_id) FROM app_events
          WHERE name = 'app_open' AND at > now() - interval '7 days'), 0), 2)
        FROM drops WHERE created_at > now() - interval '7 days') AS drops_per_wau,
      (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY n) FROM (
          SELECT (SELECT count(*) FROM unlocks u WHERE u.drop_id = d.id) AS n
          FROM drops d WHERE d.status = 'approved' AND NOT d.is_relay) x) AS median_unlocks_per_drop,
      (SELECT round(avg(n), 2) FROM (
          SELECT (SELECT count(*) FROM relay_hops h WHERE h.drop_id = d.id AND h.dropped_at IS NOT NULL AND NOT h.returned) AS n
          FROM drops d WHERE d.is_relay AND d.status = 'approved') x) AS relay_hops_per_relay,
      (SELECT round((SELECT count(*) FROM trail_completions)::numeric
          / nullif((SELECT count(DISTINCT (user_id, props->>'trailId')) FROM app_events WHERE name = 'trail_started'), 0), 3))
        AS trail_completion_rate,
      -- Approved drops later removed after reports, as a share of approved drops.
      (SELECT round((SELECT count(DISTINCT target_id) FROM reports WHERE target_type = 'drop' AND resolution = 'remove')::numeric
          / nullif((SELECT count(*) FROM drops WHERE status IN ('approved', 'removed')), 0), 4)) AS moderation_false_negative_rate`;
  const unlockFailures = await sql`
    SELECT props->>'reason' AS reason, count(*)::int AS count
    FROM app_events WHERE name = 'unlock_attempt' AND props->>'reason' IS NOT NULL AND at > ${since}
    GROUP BY 1 ORDER BY 2 DESC`;
  const daily = await sql`
    SELECT date_trunc('day', at) AS day, name, count(*)::int AS count
    FROM app_events WHERE at > ${since} GROUP BY 1, 2 ORDER BY 1, 2`;

  return {
    days,
    // Keys match the camelCased SQL columns in `metrics` (postgres.camel).
    targets: {
      firstSessionUnlockRate: 0.6,
      d1Retention: 0.45,
      d7Retention: 0.25,
      dropsPerWau: 1.5,
      medianUnlocksPerDrop: 3,
      relayHopsPerRelay: 4,
      trailCompletionRate: 0.35,
      moderationFalseNegativeRate: 0.01,
    },
    // numeric/bigint columns arrive as strings; the dashboard wants numbers.
    metrics: Object.fromEntries(Object.entries(m ?? {}).map(([k, v]) => [k, v == null ? null : Number(v)])),
    unlockFailures,
    daily,
  };
}
