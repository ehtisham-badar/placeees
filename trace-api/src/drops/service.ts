import { sql } from '../db/client.js';
import { AppError, notFound } from '../lib/errors.js';
import { distanceM, geohash } from '../lib/geo.js';
import { checkFreshness, isImpossibleTravel, type LocationPayload } from '../integrity/location.js';
import { previousFix, recordFix } from '../integrity/fixes.js';
import { recordIntegrityEvent } from '../integrity/events.js';
import { assertTrustedPayload } from '../integrity/verify.js';
import { limitAction } from '../lib/rateLimit.js';
import { moderate } from '../moderation/moderate.js';
import { ownsMediaKey, signedReadUrl } from '../media/r2.js';
import { conditionsMet } from '../conditions/evaluate.js';
import { conditionKinds, type Conditions } from '../conditions/schema.js';
import { currentWeather } from '../conditions/weather.js';
import { fuzzyCircle } from './fuzz.js';
import { evaluateUnlock, presenceFailure } from './unlock.js';

export const MAX_CREATE_ACCURACY_M = 65;
export const MAX_DROPS_PER_DAY = 10;
export const MAX_DROPS_PER_CELL_PER_DAY = 3;
export const HOME_ZONE_RADIUS_M = 200;
export const NEAR_HINT_RADIUS_M = 100;
export const NEAR_HINT_TTL_MS = 5 * 60_000;
export const CAPSULE_MIN_MS = 24 * 3600_000;
export const CAPSULE_MAX_MS = 25 * 365.25 * 24 * 3600_000;
export const MAX_RECIPIENTS = 20;

export type DropType = 'photo' | 'text' | 'voice' | 'then_now';

export interface CreateDropInput {
  type: DropType;
  body?: string;
  mediaKey?: string;
  teaser?: string;
  isAnonymous: boolean;
  location: LocationPayload;
  conditions?: Conditions;
  revealConditions: boolean;
  unlockAt?: Date;
  recipientHandles?: string[];
  circleId?: string;
  isRelay: boolean;
  captureHeading?: number;
  capturePitch?: number;
}

/** Drops this user may see: approved (or their own), not blocked either way, not being carried. */
const visibleTo = (userId: string) => sql`
  (d.status = 'approved' OR (d.creator_id = ${userId} AND d.status = 'pending_moderation'))
  AND (d.visibility = 'public' OR d.creator_id = ${userId} OR ${userId} = ANY(d.recipient_ids)
       OR (d.visibility = 'circle' AND EXISTS (
             SELECT 1 FROM circle_members cm WHERE cm.circle_id = d.circle_id AND cm.user_id = ${userId})))
  AND d.relay_carrier_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM blocks b
    WHERE (b.blocker_id = ${userId} AND b.blocked_id = d.creator_id)
       OR (b.blocker_id = d.creator_id AND b.blocked_id = ${userId})
  )`;

/**
 * Trail stops after the first stay hidden (and locked) until the previous stop is unlocked (F-10).
 * True for drops outside trails and for the trail's creator.
 */
export const trailOrderOk = (userId: string) => sql`
  NOT EXISTS (
    SELECT 1 FROM trail_stops ts
    WHERE ts.drop_id = d.id AND ts.seq > 1 AND d.creator_id <> ${userId}
      AND NOT EXISTS (
        SELECT 1 FROM trail_stops prev
        JOIN unlocks u ON u.drop_id = prev.drop_id AND u.user_id = ${userId}
        WHERE prev.trail_id = ts.trail_id AND prev.seq = ts.seq - 1))`;

export { visibleTo };

async function assertCanPlaceAt(userId: string, p: LocationPayload, cell: string, isPublic: boolean) {
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
  if (counts.inZone && isPublic) throw new AppError('exclusion_zone', 422);
}

async function assertTrustworthyFix(userId: string, p: LocationPayload) {
  const stale = checkFreshness(p);
  if (stale) throw new AppError(stale, 422);
  await assertTrustedPayload(userId, p);
  if (isImpossibleTravel(await previousFix(userId), p)) {
    await recordIntegrityEvent(userId, 'impossible_travel', { lat: p.lat, lng: p.lng });
    throw new AppError('suspicious', 422);
  }
}

export async function createDrop(userId: string, input: CreateDropInput) {
  await limitAction(userId, 'createDrop');
  const p = input.location;
  await assertTrustworthyFix(userId, p);
  if (p.accuracy > MAX_CREATE_ACCURACY_M) throw new AppError('low_accuracy', 422);

  if (input.type === 'text' && !input.body?.trim()) throw new AppError('body_required', 422);
  if (input.type !== 'text') {
    if (!input.mediaKey) throw new AppError('media_required', 422);
    if (!ownsMediaKey(userId, input.mediaKey)) throw forbiddenMedia();
  }

  if (input.type === 'then_now' && (input.captureHeading == null || input.capturePitch == null)) {
    throw new AppError('angle_required', 422);
  }
  // A relay travels in public; it can't also be sealed, private or addressed.
  if (input.isRelay && (input.unlockAt || input.circleId || input.recipientHandles?.length)) {
    throw new AppError('relay_must_be_public', 422);
  }
  if (input.unlockAt) {
    const ahead = input.unlockAt.getTime() - Date.now();
    if (ahead < CAPSULE_MIN_MS) throw new AppError('capsule_too_soon', 422);
    if (ahead > CAPSULE_MAX_MS) throw new AppError('capsule_too_far', 422);
  }
  const recipientIds = await resolveRecipients(userId, input.recipientHandles ?? []);
  if (input.circleId) {
    if (recipientIds.length) throw new AppError('visibility_conflict', 422);
    const [member] = await sql`
      SELECT 1 FROM circle_members WHERE circle_id = ${input.circleId} AND user_id = ${userId}`;
    if (!member) throw new AppError('not_a_member', 403);
  }
  const visibility = input.circleId ? 'circle' : recipientIds.length ? 'users' : 'public';

  const cell = geohash(p, 7);
  await assertCanPlaceAt(userId, p, cell, visibility === 'public');
  await recordFix(userId, p);

  const [drop] = await sql<{ id: string; status: string; createdAt: Date }[]>`
    INSERT INTO drops (creator_id, geo, geohash7, type, body, media_key, teaser, is_anonymous,
                       conditions, conditions_revealed, unlock_at, visibility, recipient_ids, circle_id,
                       is_relay, capture_heading, capture_pitch)
    VALUES (${userId}, ST_MakePoint(${p.lng}, ${p.lat})::geography, ${cell}, ${input.type},
            ${input.body?.trim() || null}, ${input.mediaKey ?? null}, ${input.teaser?.trim() || null},
            ${input.isAnonymous}, ${input.conditions ? sql.json(input.conditions) : null},
            ${input.conditions ? input.revealConditions : false}, ${input.unlockAt ?? null},
            ${visibility}, ${recipientIds.length ? recipientIds : null}, ${input.circleId ?? null},
            ${input.isRelay}, ${input.type === 'then_now' ? input.captureHeading! : null},
            ${input.type === 'then_now' ? input.capturePitch! : null})
    RETURNING id, status, created_at`;
  if (!drop) throw new AppError('internal', 500);

  // Screening runs after the response; the drop stays invisible to others until approved.
  void screenDrop(drop.id, input).catch((err) => console.error('moderation error', drop.id, err));
  return drop;
}

/** Capsule recipients are chosen by handle; every handle must exist. */
async function resolveRecipients(userId: string, handles: string[]): Promise<string[]> {
  const wanted = [...new Set(handles.map((h) => h.trim().toLowerCase().replace(/^@/, '')).filter(Boolean))];
  if (wanted.length === 0) return [];
  if (wanted.length > MAX_RECIPIENTS) throw new AppError('too_many_recipients', 422);
  const rows = await sql<{ id: string; handle: string }[]>`SELECT id, handle FROM users WHERE handle IN ${sql(wanted)}`;
  if (rows.length !== wanted.length) throw new AppError('unknown_recipient', 422);
  return rows.map((r) => r.id).filter((id) => id !== userId);
}

function forbiddenMedia() {
  return new AppError('media_not_owned', 403);
}

async function screenDrop(dropId: string, input: CreateDropInput) {
  const imageUrl =
    (input.type === 'photo' || input.type === 'then_now') && input.mediaKey ? await signedReadUrl(input.mediaKey) : undefined;
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
  conditions: Conditions | null;
  conditionsRevealed: boolean;
  unlockAt: Date | null;
  isRelay: boolean;
  status: string;
  mine: boolean;
  unlocked: boolean;
  forMe: boolean;
  trailId: string | null;
  trailTitle: string | null;
  trailSeq: number | null;
  trailTotal: number | null;
  circleId: string | null;
  circleName: string | null;
  relayHops: number;
}

export async function nearbyDrops(userId: string, lat: number, lng: number, radius: number) {
  const rows = await sql<NearbyRow[]>`
    SELECT d.id, d.type, d.teaser, d.created_at, d.status,
           ST_Y(d.geo::geometry) AS lat, ST_X(d.geo::geometry) AS lng,
           d.conditions, d.conditions_revealed, d.unlock_at, d.is_relay,
           d.creator_id = ${userId} AS mine,
           ${userId} = ANY(COALESCE(d.recipient_ids, '{}')) AS for_me,
           EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = d.id AND u.user_id = ${userId}) AS unlocked,
           t.id AS trail_id, t.title AS trail_title, ts.seq AS trail_seq,
           (SELECT count(*)::int FROM trail_stops x WHERE x.trail_id = t.id) AS trail_total,
           c.id AS circle_id, c.name AS circle_name,
           (SELECT count(*)::int FROM relay_hops h WHERE h.drop_id = d.id AND h.dropped_at IS NOT NULL
              AND NOT h.returned) AS relay_hops
    FROM drops d
    LEFT JOIN trail_stops ts ON ts.drop_id = d.id
    LEFT JOIN trails t ON t.id = ts.trail_id
    LEFT JOIN circles c ON c.id = d.circle_id
    WHERE ${visibleTo(userId)}
      AND ${trailOrderOk(userId)}
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
    badges: {
      condition: r.conditions != null,
      conditionKinds: r.conditions ? conditionKinds(r.conditions) : [],
      // The exact rule is only shown when the creator chose to reveal it (or to the creator).
      conditions: r.conditions && (r.conditionsRevealed || r.mine) ? r.conditions : null,
      capsuleUnlockAt: r.unlockAt,
      forYou: r.forMe,
      relay: r.isRelay,
      relayHops: r.isRelay ? r.relayHops : null,
      trail: r.trailId ? { id: r.trailId, title: r.trailTitle, seq: r.trailSeq, total: r.trailTotal } : null,
      circle: r.circleId ? { id: r.circleId, name: r.circleName } : null,
    },
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
  trailId: string | null;
  trailTitle: string | null;
  trailSeq: number | null;
  trailTotal: number | null;
  nextClue: string | null;
  trailCompletedAt: Date | null;
  circleId: string | null;
  circleName: string | null;
  isRelay: boolean;
  relayCarrierId: string | null;
  relayHops: number;
  carriedBefore: boolean;
  carryDeadline: Date | null;
  captureHeading: number | null;
  capturePitch: number | null;
}

async function loadDrop(userId: string, dropId: string): Promise<DropRow | undefined> {
  const [row] = await sql<DropRow[]>`
    SELECT d.id, d.creator_id, d.type, d.body, d.media_key, d.teaser, d.is_anonymous, d.created_at,
           d.status, u.handle,
           (SELECT count(*)::int FROM unlocks x WHERE x.drop_id = d.id) AS unlock_count,
           (SELECT unlocked_at FROM unlocks x WHERE x.drop_id = d.id AND x.user_id = ${userId}) AS unlocked_at,
           t.id AS trail_id, t.title AS trail_title, ts.seq AS trail_seq,
           (SELECT count(*)::int FROM trail_stops x WHERE x.trail_id = t.id) AS trail_total,
           (SELECT clue FROM trail_stops x WHERE x.trail_id = t.id AND x.seq = ts.seq + 1) AS next_clue,
           (SELECT completed_at FROM trail_completions x WHERE x.trail_id = t.id AND x.user_id = ${userId})
             AS trail_completed_at,
           c.id AS circle_id, c.name AS circle_name,
           d.is_relay, d.relay_carrier_id, d.capture_heading, d.capture_pitch,
           (SELECT count(*)::int FROM relay_hops h WHERE h.drop_id = d.id AND h.dropped_at IS NOT NULL
              AND NOT h.returned) AS relay_hops,
           EXISTS (SELECT 1 FROM relay_hops h WHERE h.drop_id = d.id AND h.carrier_id = ${userId}) AS carried_before,
           (SELECT deadline_at FROM relay_hops h WHERE h.drop_id = d.id AND h.carrier_id = ${userId}
              AND h.dropped_at IS NULL) AS carry_deadline
    FROM drops d
    JOIN users u ON u.id = d.creator_id
    LEFT JOIN trail_stops ts ON ts.drop_id = d.id
    LEFT JOIN trails t ON t.id = ts.trail_id
    LEFT JOIN circles c ON c.id = d.circle_id
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
    // The next clue is only for people who have actually reached this stop.
    trail: row.trailId
      ? {
          id: row.trailId,
          title: row.trailTitle,
          seq: row.trailSeq,
          total: row.trailTotal,
          nextClue: row.nextClue,
          completedAt: row.trailCompletedAt,
        }
      : null,
    circle: row.circleId ? { id: row.circleId, name: row.circleName } : null,
    relay: row.isRelay
      ? {
          hops: row.relayHops,
          carrying: row.relayCarrierId === userId,
          carryDeadline: row.carryDeadline,
          // Anyone who opened it (except its creator and past carriers) can carry it on.
          canPickUp: !mine && !row.carriedBefore && row.relayCarrierId == null && row.unlockedAt != null,
        }
      : null,
    thenNow:
      row.type === 'then_now' ? { captureHeading: row.captureHeading, capturePitch: row.capturePitch } : null,
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
  await limitAction(userId, 'unlock');
  await assertTrustedPayload(userId, p);
  const drop = await locateDrop(userId, dropId, p);
  const failure = await evaluateUnlock({
    payload: p,
    previousFix: await previousFix(userId),
    distanceM: drop.distanceM,
    visible: drop.visible,
    trailOrderOk: drop.trailOrderOk,
    unlockAt: drop.unlockAt,
    conditionsMet: async () =>
      !drop.conditions ||
      conditionsMet(drop.conditions, {
        now: new Date(),
        lat: drop.lat,
        lng: drop.lng,
        weather: () => currentWeather(drop.lat, drop.lng),
      }),
  });
  if (failure === 'suspicious') await recordIntegrityEvent(userId, 'impossible_travel', { dropId });
  if (failure) throw new AppError(failure, failure === 'not_visible' ? 404 : 422);

  await recordFix(userId, p);
  await sql`
    INSERT INTO unlocks (user_id, drop_id, accuracy) VALUES (${userId}, ${dropId}, ${p.accuracy})
    ON CONFLICT DO NOTHING`;
  await recordTrailCompletion(userId, dropId);
  return getDropContent(userId, dropId);
}

/** Awards the trail stamp (F-10) once every stop of the drop's trail is unlocked. */
async function recordTrailCompletion(userId: string, dropId: string) {
  await sql`
    INSERT INTO trail_completions (user_id, trail_id)
    SELECT ${userId}, ts.trail_id FROM trail_stops ts
    WHERE ts.drop_id = ${dropId}
      AND NOT EXISTS (
        SELECT 1 FROM trail_stops s
        WHERE s.trail_id = ts.trail_id
          AND NOT EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = s.drop_id AND u.user_id = ${userId}))
    ON CONFLICT DO NOTHING`;
}

interface LocatedDrop {
  visible: boolean;
  trailOrderOk: boolean;
  distanceM: number;
  lat: number;
  lng: number;
  conditions: Conditions | null;
  unlockAt: Date | null;
}

async function locateDrop(userId: string, dropId: string, p: LocationPayload): Promise<LocatedDrop> {
  const [drop] = await sql<LocatedDrop[]>`
    SELECT (${visibleTo(userId)} AND d.status = 'approved') AS visible,
           ${trailOrderOk(userId)} AS trail_order_ok,
           ST_Distance(d.geo, ST_MakePoint(${p.lng}, ${p.lat})::geography) AS distance_m,
           ST_Y(d.geo::geometry) AS lat, ST_X(d.geo::geometry) AS lng,
           d.conditions, d.unlock_at
    FROM drops d WHERE d.id = ${dropId} AND d.status <> 'removed'`;
  if (!drop || !drop.visible) throw notFound();
  return drop;
}

/**
 * Hot/cold compass (F-07): within 100 m, reveal the true point for a few minutes so the
 * final approach can home in on it. Same integrity checks as an unlock.
 */
export async function nearHint(userId: string, dropId: string, p: LocationPayload) {
  await limitAction(userId, 'nearHint');
  await assertTrustedPayload(userId, p);
  const stale = checkFreshness(p);
  if (stale) throw new AppError(stale, 422);
  if (p.accuracy > 80) throw new AppError('low_accuracy', 422);
  if (isImpossibleTravel(await previousFix(userId), p)) throw new AppError('suspicious', 422);

  const drop = await locateDrop(userId, dropId, p);
  if (!drop.trailOrderOk) throw notFound(); // hidden trail stops stay hidden
  if (drop.distanceM > NEAR_HINT_RADIUS_M) throw new AppError('too_far', 422);
  await recordFix(userId, p);
  return {
    point: { lat: drop.lat, lng: drop.lng },
    distanceM: Math.round(distanceM(p, drop)),
    expiresAt: new Date(Date.now() + NEAR_HINT_TTL_MS),
  };
}

/** Proximity check for location-bound actions on a drop other than unlocking it (echoes). */
export async function assertPresentAt(userId: string, dropId: string, p: LocationPayload) {
  await assertTrustedPayload(userId, p);
  const drop = await locateDrop(userId, dropId, p);
  const failure = presenceFailure({ payload: p, previousFix: await previousFix(userId), distanceM: drop.distanceM });
  if (failure === 'suspicious') await recordIntegrityEvent(userId, 'impossible_travel', { dropId });
  if (failure) throw new AppError(failure, 422);
  await recordFix(userId, p);
}
