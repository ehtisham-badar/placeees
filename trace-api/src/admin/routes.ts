import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { forgetBanState } from '../auth/plugin.js';
import { inviteCode } from '../circles/routes.js';
import { config } from '../config.js';
import { sql } from '../db/client.js';
import { AppError, notFound } from '../lib/errors.js';
import { signedReadUrl } from '../media/r2.js';
import { pilotMetrics } from '../metrics/routes.js';

function tokenMatches(given: string | undefined): boolean {
  if (!config.ADMIN_TOKEN || !given) return false;
  const a = Buffer.from(given);
  const b = Buffer.from(config.ADMIN_TOKEN);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function requireAdmin(req: FastifyRequest) {
  // With no token configured the admin API doesn't exist.
  if (!config.ADMIN_TOKEN) throw notFound();
  const header = req.headers['x-admin-token'];
  if (!tokenMatches(Array.isArray(header) ? header[0] : header)) throw new AppError('unauthorized', 401);
}

const media = async (key: string | null) => (key ? signedReadUrl(key).catch(() => null) : null);

const Action = z.object({ action: z.enum(['approve', 'reject', 'remove']) });
const status = { approve: 'approved', reject: 'rejected', remove: 'removed' } as const;
const IdParam = z.object({ id: z.uuid() });

/** Minimal moderation and safety API behind ADMIN_TOKEN (spec F-05). */
export async function adminRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAdmin);

  app.get('/v1/admin/queue', async () => {
    const drops = await sql<{ mediaKey: string | null }[]>`
      SELECT d.id, d.type, d.teaser, d.body, d.media_key, d.created_at, d.moderation_note, d.creator_id, u.handle,
             (SELECT count(*)::int FROM reports r WHERE r.target_type = 'drop' AND r.target_id = d.id AND r.resolved_at IS NULL)
               AS open_reports
      FROM drops d JOIN users u ON u.id = d.creator_id
      WHERE d.status = 'pending_moderation'
      ORDER BY open_reports DESC, d.created_at
      LIMIT 100`;
    const echoes = await sql`
      SELECT e.id, e.body, e.drop_id, e.created_at, e.user_id, u.handle
      FROM echoes e JOIN users u ON u.id = e.user_id
      WHERE e.status = 'pending_moderation' ORDER BY e.created_at LIMIT 100`;
    const nowPhotos = await sql<{ mediaKey: string }[]>`
      SELECT n.id, n.media_key, n.drop_id, n.created_at, n.user_id, u.handle
      FROM now_photos n JOIN users u ON u.id = n.user_id
      WHERE n.status = 'pending_moderation' ORDER BY n.created_at LIMIT 100`;
    return {
      drops: await Promise.all(drops.map(async ({ mediaKey, ...d }) => ({ ...d, mediaUrl: await media(mediaKey) }))),
      echoes,
      nowPhotos: await Promise.all(nowPhotos.map(async ({ mediaKey, ...n }) => ({ ...n, mediaUrl: await media(mediaKey) }))),
    };
  });

  app.get('/v1/admin/reports', async () => {
    const reports = await sql`
      SELECT r.target_type, r.target_id, count(*)::int AS count, count(DISTINCT r.reporter_id)::int AS reporters,
             array_agg(DISTINCT r.reason) FILTER (WHERE r.reason IS NOT NULL) AS reasons, max(r.created_at) AS last_at,
             CASE r.target_type
               WHEN 'drop' THEN (SELECT coalesce(d.teaser, left(d.body, 140)) FROM drops d WHERE d.id = r.target_id)
               WHEN 'echo' THEN (SELECT left(e.body, 140) FROM echoes e WHERE e.id = r.target_id)
               WHEN 'user' THEN (SELECT '@' || u.handle FROM users u WHERE u.id = r.target_id)
             END AS preview
      FROM reports r
      WHERE r.resolved_at IS NULL
      GROUP BY r.target_type, r.target_id
      ORDER BY reporters DESC, last_at DESC
      LIMIT 200`;
    return { reports };
  });

  app.post('/v1/admin/drops/:id', async (req) => {
    const { id } = IdParam.parse(req.params);
    const { action } = Action.parse(req.body);
    const [row] = await sql`
      UPDATE drops SET status = ${status[action]}, moderated_at = now(), moderation_note = ${`admin:${action}`}
      WHERE id = ${id} RETURNING id`;
    if (!row) throw notFound();
    await sql`
      UPDATE reports SET resolved_at = now(), resolution = ${action}
      WHERE target_type = 'drop' AND target_id = ${id} AND resolved_at IS NULL`;
    return { ok: true };
  });

  app.post('/v1/admin/echoes/:id', async (req) => {
    const { id } = IdParam.parse(req.params);
    const { action } = Action.parse(req.body);
    const [row] = await sql`UPDATE echoes SET status = ${status[action]} WHERE id = ${id} RETURNING id`;
    if (!row) throw notFound();
    await sql`
      UPDATE reports SET resolved_at = now(), resolution = ${action}
      WHERE target_type = 'echo' AND target_id = ${id} AND resolved_at IS NULL`;
    return { ok: true };
  });

  app.post('/v1/admin/now-photos/:id', async (req) => {
    const { id } = IdParam.parse(req.params);
    const { action } = Action.parse(req.body);
    const [row] = await sql`UPDATE now_photos SET status = ${status[action]} WHERE id = ${id} RETURNING id`;
    if (!row) throw notFound();
    return { ok: true };
  });

  app.post('/v1/admin/reports/dismiss', async (req) => {
    const body = z.object({ targetType: z.enum(['drop', 'echo', 'user']), targetId: z.uuid() }).parse(req.body);
    await sql`
      UPDATE reports SET resolved_at = now(), resolution = 'dismissed'
      WHERE target_type = ${body.targetType} AND target_id = ${body.targetId} AND resolved_at IS NULL`;
    // A drop auto-hidden by reports goes back up when the reports are dismissed.
    if (body.targetType === 'drop') {
      await sql`
        UPDATE drops SET status = 'approved', moderation_note = 'admin:restored'
        WHERE id = ${body.targetId} AND moderation_note = 'auto_hidden_by_reports'`;
    }
    return { ok: true };
  });

  /** Everyone, newest first. Provider only (never the Apple/Google account ids), and no locations. */
  app.get('/v1/admin/users', async (req) => {
    const { q } = z.object({ q: z.string().trim().max(40).optional() }).parse(req.query);
    const users = await sql`
      SELECT u.id, u.handle, u.created_at, u.banned_at,
             CASE WHEN u.apple_sub IS NOT NULL THEN 'apple'
                  WHEN u.google_sub IS NOT NULL THEN 'google'
                  WHEN u.dev_sub LIKE 'seed:%' THEN 'seed'
                  ELSE 'dev' END AS provider,
             u.home_zone IS NOT NULL AS has_home_zone,
             u.last_fix_at AS last_active_at,
             (SELECT count(*)::int FROM drops d WHERE d.creator_id = u.id) AS drops,
             (SELECT count(*)::int FROM unlocks x WHERE x.user_id = u.id) AS unlocks,
             (SELECT count(*)::int FROM integrity_events e WHERE e.user_id = u.id) AS integrity_events,
             (SELECT count(*)::int FROM devices v WHERE v.user_id = u.id) AS devices
      FROM users u
      WHERE ${q ? sql`u.handle ILIKE ${'%' + q.replace(/[%_\\]/g, '') + '%'}` : sql`true`}
      ORDER BY u.created_at DESC
      LIMIT 200`;
    return { users };
  });

  app.get('/v1/admin/users/:id', async (req) => {
    const { id } = IdParam.parse(req.params);
    const [user] = await sql`
      SELECT id, handle, created_at, banned_at,
             (SELECT count(*)::int FROM drops WHERE creator_id = users.id) AS drops,
             (SELECT count(*)::int FROM unlocks WHERE user_id = users.id) AS unlocks,
             (SELECT count(*)::int FROM reports WHERE target_type = 'user' AND target_id = users.id) AS reports_against
      FROM users WHERE id = ${id}`;
    if (!user) throw notFound();
    const events = await sql`
      SELECT kind, detail, created_at FROM integrity_events WHERE user_id = ${id} ORDER BY created_at DESC LIMIT 50`;
    return { user, events };
  });

  app.post('/v1/admin/users/:id/ban', async (req) => {
    const { id } = IdParam.parse(req.params);
    const { banned } = z.object({ banned: z.boolean() }).parse(req.body);
    const [row] = await sql`
      UPDATE users SET banned_at = ${banned ? sql`now()` : null} WHERE id = ${id} RETURNING id`;
    if (!row) throw notFound();
    forgetBanState(id);
    return { ok: true };
  });

  app.get('/v1/admin/metrics', async (req) => {
    const { days } = z.object({ days: z.coerce.number().int().min(1).max(90).default(7) }).parse(req.query);
    return pilotMetrics(days);
  });

  app.get('/v1/admin/integrity', async () => {
    const events = await sql`
      SELECT e.kind, e.detail, e.created_at, e.user_id, u.handle
      FROM integrity_events e LEFT JOIN users u ON u.id = e.user_id
      ORDER BY e.created_at DESC LIMIT 200`;
    const summary = await sql`
      SELECT kind, count(*)::int AS count FROM integrity_events
      WHERE created_at > now() - interval '1 day' GROUP BY kind ORDER BY count DESC`;
    return { events, summary };
  });

  // F-16: venue codes for QR posters / NFC tags.
  app.get('/v1/admin/venues', async () => ({
    venues: (await sql<{ code: string }[]>`
      SELECT v.code, v.name, v.drop_id, v.created_at, d.teaser
      FROM venues v JOIN drops d ON d.id = v.drop_id ORDER BY v.created_at DESC`).map((v) => ({
      ...v,
      url: `${config.PUBLIC_WEB_URL}/v/${v.code}`,
    })),
  }));

  app.post('/v1/admin/venues', async (req, reply) => {
    const body = z.object({ dropId: z.uuid(), name: z.string().trim().min(1).max(60) }).parse(req.body);
    const [drop] = await sql`SELECT 1 FROM drops WHERE id = ${body.dropId} AND status = 'approved' AND visibility = 'public'`;
    if (!drop) throw new AppError('invalid_drop', 422);
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = inviteCode();
      const [v] = await sql`
        INSERT INTO venues (code, drop_id, name) VALUES (${code}, ${body.dropId}, ${body.name})
        ON CONFLICT DO NOTHING RETURNING code`;
      if (v) return reply.code(201).send({ code, url: `${config.PUBLIC_WEB_URL}/v/${code}` });
    }
    throw new AppError('internal', 500);
  });
}
