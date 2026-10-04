import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth/plugin.js';
import { sql } from '../db/client.js';
import { fuzzyCircle } from '../drops/fuzz.js';
import { assertPresentAt, HOME_ZONE_RADIUS_M, MAX_CREATE_ACCURACY_M } from '../drops/service.js';
import { previousFix, recordFix } from '../integrity/fixes.js';
import { checkFreshness, isImpossibleTravel, LocationPayload } from '../integrity/location.js';
import { AppError, notFound } from '../lib/errors.js';
import { geohash } from '../lib/geo.js';
import { assertTrustedPayload } from '../integrity/verify.js';
import { limitAction } from '../lib/rateLimit.js';
import { moderate } from '../moderation/moderate.js';
import { carryDeadline, dropFailure, pickupFailure } from './rules.js';

const IdParam = z.object({ id: z.uuid() });

export async function relayRoutes(app: FastifyInstance) {
  app.addHook('preHandler', requireAuth);

  /** Relays you're carrying, with where you picked them up and when they're due. */
  app.get('/v1/relays/carrying', async (req) => {
    const relays = await sql`
      SELECT d.id, d.type, d.teaser, h.picked_at, h.deadline_at,
             ST_Y(h.pickup_geo::geometry) AS pickup_lat, ST_X(h.pickup_geo::geometry) AS pickup_lng
      FROM relay_hops h JOIN drops d ON d.id = h.drop_id
      WHERE h.carrier_id = ${req.userId} AND h.dropped_at IS NULL
      ORDER BY h.deadline_at`;
    return { relays };
  });

  app.post('/v1/relays/:id/pickup', async (req) => {
    const { id } = IdParam.parse(req.params);
    const { location } = z.object({ location: LocationPayload }).parse(req.body);
    await limitAction(req.userId, 'relay');

    const [row] = await sql<{
      isRelay: boolean;
      creatorId: string;
      carrierId: string | null;
      unlocked: boolean;
      carriedBefore: boolean;
      carrying: number;
    }[]>`
      SELECT d.is_relay, d.creator_id, d.relay_carrier_id AS carrier_id,
             EXISTS (SELECT 1 FROM unlocks u WHERE u.drop_id = d.id AND u.user_id = ${req.userId}) AS unlocked,
             EXISTS (SELECT 1 FROM relay_hops h WHERE h.drop_id = d.id AND h.carrier_id = ${req.userId}) AS carried_before,
             (SELECT count(*)::int FROM relay_hops h WHERE h.carrier_id = ${req.userId} AND h.dropped_at IS NULL) AS carrying
      FROM drops d WHERE d.id = ${id} AND d.status = 'approved'`;
    if (!row) throw notFound();

    const failure = pickupFailure({
      isRelay: row.isRelay,
      isCreator: row.creatorId === req.userId,
      carriedBefore: row.carriedBefore,
      carrierId: row.carrierId,
      unlocked: row.unlocked,
      carryingCount: row.carrying,
    });
    if (failure) throw new AppError(failure, failure === 'already_carried' ? 409 : 422);
    await assertPresentAt(req.userId, id, location);

    const deadlineAt = carryDeadline(new Date());
    await sql.begin(async (tx) => {
      // Claim atomically: two people standing at the same relay can't both take it.
      const [claimed] = await tx`
        UPDATE drops SET relay_carrier_id = ${req.userId}
        WHERE id = ${id} AND relay_carrier_id IS NULL AND is_relay
        RETURNING id`;
      if (!claimed) throw new AppError('already_carried', 409);
      await tx`
        INSERT INTO relay_hops (drop_id, carrier_id, pickup_geo, deadline_at)
        SELECT id, ${req.userId}, geo, ${deadlineAt} FROM drops WHERE id = ${id}`;
    });
    return { carrying: true, deadlineAt };
  });

  app.post('/v1/relays/:id/drop', async (req) => {
    const { id } = IdParam.parse(req.params);
    const body = z
      .object({ location: LocationPayload, note: z.string().trim().max(140).optional() })
      .parse(req.body);
    const p = body.location;
    await limitAction(req.userId, 'relay');

    const [hop] = await sql<{ id: string; distanceM: number; inHome: boolean; inZone: boolean }[]>`
      SELECT h.id,
             ST_Distance(h.pickup_geo, ST_MakePoint(${p.lng}, ${p.lat})::geography) AS distance_m,
             EXISTS (SELECT 1 FROM users WHERE id = ${req.userId} AND home_zone IS NOT NULL
               AND ST_DWithin(home_zone, ST_MakePoint(${p.lng}, ${p.lat})::geography, ${HOME_ZONE_RADIUS_M})) AS in_home,
             EXISTS (SELECT 1 FROM exclusion_zones
               WHERE ST_Intersects(geo, ST_MakePoint(${p.lng}, ${p.lat})::geography)) AS in_zone
      FROM relay_hops h JOIN drops d ON d.id = h.drop_id
      WHERE h.drop_id = ${id} AND h.carrier_id = ${req.userId} AND h.dropped_at IS NULL
        AND d.relay_carrier_id = ${req.userId}`;
    if (!hop) throw new AppError('not_carrying', 422);

    // Same integrity bar as leaving a new drop.
    const stale = checkFreshness(p);
    if (stale) throw new AppError(stale, 422);
    if (p.accuracy > MAX_CREATE_ACCURACY_M) throw new AppError('low_accuracy', 422);
    await assertTrustedPayload(req.userId, p);
    if (isImpossibleTravel(await previousFix(req.userId), p)) throw new AppError('suspicious', 422);
    const tooClose = dropFailure(hop.distanceM);
    if (tooClose) throw new AppError(tooClose, 422);
    if (hop.inHome) throw new AppError('home_zone', 422);
    if (hop.inZone) throw new AppError('exclusion_zone', 422);

    let note = body.note || null;
    if (note && !(await moderate({ text: note })).approved) throw new AppError('note_rejected', 422);

    await recordFix(req.userId, p);
    await sql.begin(async (tx) => {
      await tx`
        UPDATE drops
        SET geo = ST_MakePoint(${p.lng}, ${p.lat})::geography, geohash7 = ${geohash(p, 7)}, relay_carrier_id = NULL
        WHERE id = ${id}`;
      await tx`
        UPDATE relay_hops
        SET dropped_at = now(), dropped_geo = ST_MakePoint(${p.lng}, ${p.lat})::geography, note = ${note}
        WHERE id = ${hop.id}`;
    });
    return { dropped: true, distanceM: Math.round(hop.distanceM) };
  });

  /**
   * Where a relay has been (spec F-13). Points are fuzzed like map markers, so a journey never
   * pinpoints where the relay rests now. Distances use the true points.
   */
  app.get('/v1/relays/:id/journey', async (req) => {
    const { id } = IdParam.parse(req.params);
    const [drop] = await sql<{
      isRelay: boolean;
      creatorId: string;
      creatorHandle: string | null;
      isAnonymous: boolean;
      createdAt: Date;
      lat: number;
      lng: number;
      carrierHandle: string | null;
      allowed: boolean;
    }[]>`
      SELECT d.is_relay, d.creator_id, u.handle AS creator_handle, d.is_anonymous, d.created_at,
             ST_Y(d.geo::geometry) AS lat, ST_X(d.geo::geometry) AS lng,
             (SELECT handle FROM users c WHERE c.id = d.relay_carrier_id) AS carrier_handle,
             (d.creator_id = ${req.userId}
               OR EXISTS (SELECT 1 FROM unlocks x WHERE x.drop_id = d.id AND x.user_id = ${req.userId})
               OR EXISTS (SELECT 1 FROM relay_hops h WHERE h.drop_id = d.id AND h.carrier_id = ${req.userId})) AS allowed
      FROM drops d JOIN users u ON u.id = d.creator_id
      WHERE d.id = ${id} AND d.status = 'approved'`;
    if (!drop || !drop.isRelay) throw notFound();
    if (!drop.allowed) throw new AppError('locked', 403);

    const hops = await sql<{
      id: string;
      handle: string | null;
      pickedAt: Date;
      droppedAt: Date | null;
      returned: boolean;
      note: string | null;
      fromLat: number;
      fromLng: number;
      toLat: number | null;
      toLng: number | null;
      distanceM: number | null;
    }[]>`
      SELECT h.id, u.handle, h.picked_at, h.dropped_at, h.returned, h.note,
             ST_Y(h.pickup_geo::geometry) AS from_lat, ST_X(h.pickup_geo::geometry) AS from_lng,
             ST_Y(h.dropped_geo::geometry) AS to_lat, ST_X(h.dropped_geo::geometry) AS to_lng,
             ST_Distance(h.pickup_geo, h.dropped_geo) AS distance_m
      FROM relay_hops h JOIN users u ON u.id = h.carrier_id
      WHERE h.drop_id = ${id}
      ORDER BY h.picked_at`;

    const legs = hops.filter((h) => h.droppedAt && !h.returned);
    const resting = !drop.carrierHandle;
    const fuzz = (key: string, lat: number, lng: number) => fuzzyCircle(key, { lat, lng }).center;
    // The last point is where it rests now; fuzz it with the drop id so it matches the map circle.
    const origin = legs[0] ? { lat: legs[0].fromLat, lng: legs[0].fromLng } : { lat: drop.lat, lng: drop.lng };

    return {
      totalDistanceM: Math.round(legs.reduce((sum, h) => sum + (h.distanceM ?? 0), 0)),
      origin: {
        ...(legs.length === 0 && resting ? fuzzyCircle(id, origin).center : fuzz(`${id}:origin`, origin.lat, origin.lng)),
        at: drop.createdAt,
        handle: drop.isAnonymous ? null : drop.creatorHandle,
      },
      hops: legs.map((h, i) => ({
        handle: h.handle,
        pickedAt: h.pickedAt,
        droppedAt: h.droppedAt,
        distanceM: Math.round(h.distanceM ?? 0),
        note: h.note,
        to: i === legs.length - 1 && resting ? fuzzyCircle(id, { lat: h.toLat!, lng: h.toLng! }).center : fuzz(h.id, h.toLat!, h.toLng!),
      })),
      carriedBy: drop.carrierHandle ? { handle: drop.carrierHandle } : null,
    };
  });
}
