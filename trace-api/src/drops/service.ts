import { sql } from '../db/client.js';
import { AppError, notFound } from '../lib/errors.js';
import { geohash } from '../lib/geo.js';
import { checkFreshness, isImpossibleTravel, type LocationPayload } from '../integrity/location.js';
import { previousFix, recordFix } from '../integrity/fixes.js';
import { moderate } from '../moderation/moderate.js';
import { ownsMediaKey, signedReadUrl } from '../media/r2.js';
import { fuzzyCircle } from './fuzz.js';
import { evaluateUnlock } from './unlock.js';

export const MAX_CREATE_ACCURACY_M = 65;
export const MAX_DROPS_PER_DAY = 10;
export const MAX_DROPS_PER_CELL_PER_DAY = 3;
export const HOME_ZONE_RADIUS_M = 200;

export type DropType = 'photo' | 'text' | 'voice';

export interface CreateDropInput {
  type: DropType;
  body?: string;
  mediaKey?: string;
  teaser?: string;
  isAnonymous: boolean;
  location: LocationPayload;
}

/** Drops this user may see: approved (or their own), not blocked either way, not being carried. */
const visibleTo = (userId: string) => sql`
  (d.status = 'approved' OR (d.creator_id = ${userId} AND d.status = 'pending_moderation'))
  AND (d.visibility = 'public' OR d.creator_id = ${userId} OR ${userId} = ANY(d.recipient_ids))
  AND d.relay_carrier_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM blocks b
    WHERE (b.blocker_id = ${userId} AND b.blocked_id = d.creator_id)
       OR (b.blocker_id = d.creator_id AND b.blocked_id = ${userId})
  )`;

async function assertCanPlaceAt(userId: string, p: LocationPayload, cell: string) {
  const [counts] = await sql<{ today: number; inCell: number; inHome: boolean; inZone: boolean }[]>`
    SELECT
      (SELECT count(*)::int FROM drops WHERE creator_id = ${userId} AND created_at > now() - interval '1 day') AS today,
      (SELECT count(*)::int FROM drops WHERE creator_id = ${userId} AND geohash7 = ${cell}
         AND created_at > now() - interval '1 day') AS in_cell,
      EXISTS (SELECT 1 FROM users WHERE id = ${userId} AND home_zone IS NOT NULL
         AND ST_DWithin(home_zone, ST_MakePoint(${p.lng}, ${p.lat})::geography, ${HOME_ZONE_RADIUS_M})) AS in_home,
      EXISTS (SELECT 1 FROM exclusion_zones
         WHERE ST_Intersects(geo, ST_MakePoint(${p.lng}, ${p.lat})::geography)) AS in_zone`;
  if (!counts) throw new AppError('internal', 500);
  if (counts.today >= MAX_DROPS_PER_DAY) throw new AppError('daily_limit', 429);
  if (counts.inCell >= MAX_DROPS_PER_CELL_PER_DAY) throw new AppError('place_limit', 429);
  if (counts.inHome) throw new AppError('home_zone', 422);
  if (counts.inZone) throw new AppError('exclusion_zone', 422);
}

async function assertTrustworthyFix(userId: string, p: LocationPayload) {
  const stale = checkFreshness(p);
  if (stale) throw new AppError(stale, 422);
  if (isImpossibleTravel(await previousFix(userId), p)) throw new AppError('suspicious', 422);
}

export async function createDrop(userId: string, input: CreateDropInput) {
  const p = input.location;
  await assertTrustworthyFix(userId, p);
  if (p.accuracy > MAX_CREATE_ACCURACY_M) throw new AppError('low_accuracy', 422);

  if (input.type === 'text' && !input.body?.trim()) throw new AppError('body_required', 422);
  if (input.type !== 'text') {
    if (!input.mediaKey) throw new AppError('media_required', 422);
    if (!ownsMediaKey(userId, input.mediaKey)) throw forbiddenMedia();
  }

  const cell = geohash(p, 7);
  await assertCanPlaceAt(userId, p, cell);
  await recordFix(userId, p);

  const [drop] = await sql<{ id: string; status: string; createdAt: Date }[]>`
    INSERT INTO drops (creator_id, geo, geohash7, type, body, media_key, teaser, is_anonymous)
    VALUES (${userId}, ST_MakePoint(${p.lng}, ${p.lat})::geography, ${cell}, ${input.type},
            ${input.body?.trim() || null}, ${input.mediaKey ?? null}, ${input.teaser?.trim() || null},
            ${input.isAnonymous})
    RETURNING id, status, created_at`;
  if (!drop) throw new AppError('internal', 500);

  // Screening runs after the response; the drop stays invisible to others until approved.
  void screenDrop(drop.id, input).catch((err) => console.error('moderation error', drop.id, err));
  return drop;
}

function forbiddenMedia() {
  return new AppError('media_not_owned', 403);
}

async function screenDrop(dropId: string, input: CreateDropInput) {
  const imageUrl = input.type === 'photo' && input.mediaKey ? await signedReadUrl(input.mediaKey) : undefined;
  const verdict = await moderate({ text: [input.teaser, input.body].filter(Boolean).join('\n'), imageUrl });
  await sql`
    UPDATE drops
    SET status = ${verdict.approved ? 'approved' : 'rejected'},
        moderation_note = ${verdict.approved ? null : verdict.reason}
    WHERE id = ${dropId} AND status = 'pending_moderation'`;
}

interface NearbyRow {
  id: string;
  type: DropType;
  teaser: string | null;
  createdAt: Date;
  lat: number;
  lng: number;
  hasConditions: boolean;
  unlockAt: Date | null;
  isRelay: boolean;
  status: string;
  mine: boolean;
  unlocked: boolean;
}

export async function nearbyDrops(userId: string, lat: number, lng: number, radius: number) {
  const rows = await sql<NearbyRow[]>`
    SELECT d.id, d.type, d.teaser, d.created_at, d.status,
           ST_Y(d.geo::geometry) AS lat, ST_X(d.geo::geometry) AS lng,
           d.conditions IS NOT NULL AS has_conditions, d.unlock_at, d.is_relay,
           d.creator_id = ${userId} AS mine,
           EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = d.id AND u.user_id = ${userId}) AS unlocked
    FROM drops d
    WHERE ${visibleTo(userId)}
      AND ST_DWithin(d.geo, ST_MakePoint(${lng}, ${lat})::geography, ${radius})
      AND (d.expires_after IS NULL
           OR (SELECT count(*) FROM unlocks u WHERE u.drop_id = d.id) < d.expires_after)
    ORDER BY d.created_at DESC
    LIMIT 200`;

  // The true point is fuzzed here and never leaves the server for locked drops.
  return rows.map((r) => ({
    id: r.id,
    type: r.type,
    teaser: r.teaser,
    createdAt: r.createdAt,
    ...fuzzyCircle(r.id, { lat: r.lat, lng: r.lng }),
    badges: { condition: r.hasConditions, capsuleUnlockAt: r.unlockAt, relay: r.isRelay },
    mine: r.mine,
    unlocked: r.unlocked,
    pending: r.status === 'pending_moderation',
  }));
}

interface DropRow {
  id: string;
  creatorId: string;
  type: DropType;
  body: string | null;
  mediaKey: string | null;
  teaser: string | null;
  isAnonymous: boolean;
  createdAt: Date;
  status: string;
  handle: string | null;
  unlockCount: number;
  unlockedAt: Date | null;
}

async function loadDrop(userId: string, dropId: string): Promise<DropRow | undefined> {
  const [row] = await sql<DropRow[]>`
    SELECT d.id, d.creator_id, d.type, d.body, d.media_key, d.teaser, d.is_anonymous, d.created_at,
           d.status, u.handle,
           (SELECT count(*)::int FROM unlocks x WHERE x.drop_id = d.id) AS unlock_count,
           (SELECT unlocked_at FROM unlocks x WHERE x.drop_id = d.id AND x.user_id = ${userId}) AS unlocked_at
    FROM drops d JOIN users u ON u.id = d.creator_id
    WHERE d.id = ${dropId}`;
  return row;
}

export async function serializeContent(row: DropRow, userId: string) {
  const mine = row.creatorId === userId;
  return {
    id: row.id,
    type: row.type,
    body: row.body,
    teaser: row.teaser,
    mediaUrl: row.mediaKey ? await signedReadUrl(row.mediaKey) : null,
    author: row.isAnonymous && !mine ? null : { handle: row.handle },
    isAnonymous: row.isAnonymous,
    createdAt: row.createdAt,
    unlockedAt: row.unlockedAt,
    unlockCount: row.unlockCount,
    mine,
    status: row.status,
  };
}

/** Content is only readable once unlocked (or by its creator). Reopenable anywhere afterwards. */
export async function getDropContent(userId: string, dropId: string) {
  const row = await loadDrop(userId, dropId);
  if (!row || row.status === 'removed') throw notFound();
  if (row.creatorId !== userId && !row.unlockedAt) throw new AppError('locked', 403);
  return serializeContent(row, userId);
}

export async function unlockDrop(userId: string, dropId: string, p: LocationPayload) {
  const [drop] = await sql<{ visible: boolean; distanceM: number; hasConditions: boolean; unlockAt: Date | null }[]>`
    SELECT (${visibleTo(userId)} AND d.status = 'approved') AS visible,
           ST_Distance(d.geo, ST_MakePoint(${p.lng}, ${p.lat})::geography) AS distance_m,
           d.conditions IS NOT NULL AS has_conditions, d.unlock_at
    FROM drops d WHERE d.id = ${dropId} AND d.status <> 'removed'`;
  if (!drop) throw notFound();

  const failure = evaluateUnlock({
    payload: p,
    previousFix: await previousFix(userId),
    distanceM: drop.distanceM,
    visible: drop.visible,
    hasConditions: drop.hasConditions,
    unlockAt: drop.unlockAt,
  });
  if (failure) throw new AppError(failure, failure === 'not_visible' ? 404 : 422);

  await recordFix(userId, p);
  await sql`
    INSERT INTO unlocks (user_id, drop_id, accuracy) VALUES (${userId}, ${dropId}, ${p.accuracy})
    ON CONFLICT DO NOTHING`;
  return getDropContent(userId, dropId);
}
