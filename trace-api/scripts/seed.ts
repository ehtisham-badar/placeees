/**
 * Seeds a pilot campus (spec §12): founder accounts, notes around landmarks, trails and relays.
 *   npm run seed -- seed/campus.example.json
 * Idempotent per founder handle: running it twice adds the content twice, so seed a fresh database.
 */
import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { sql } from '../src/db/client.js';
import { destination, geohash, type LatLng } from '../src/lib/geo.js';

const Point = z.object({ lat: z.number(), lng: z.number() });
const Note = z.object({ teaser: z.string().max(60).optional(), body: z.string().max(500), by: z.string().optional() });

const Seed = z.object({
  campus: z.string(),
  founders: z.array(z.string().regex(/^[a-z0-9_.]{3,20}$/)).min(1),
  landmarks: z.array(
    z.object({
      name: z.string(),
      at: Point,
      /** Notes scattered within ~60 m of the landmark. */
      notes: z.array(Note),
    }),
  ),
  trails: z.array(
    z.object({
      title: z.string().max(60),
      by: z.string(),
      stops: z.array(Note.extend({ at: Point, clue: z.string().max(200) })).min(3).max(15),
    }),
  ),
  relays: z.array(Note.extend({ at: Point })),
});
type Seed = z.infer<typeof Seed>;

function scatter(center: LatLng, i: number): LatLng {
  // Deterministic spread so re-reading the file gives the same layout.
  const bearing = (i * 137.5) % 360;
  const meters = 15 + ((i * 23) % 45);
  return destination(center, bearing, meters);
}

async function main() {
  const file = process.argv[2];
  if (!file) throw new Error('usage: npm run seed -- <seed.json>');
  const seed: Seed = Seed.parse(JSON.parse(await readFile(file, 'utf8')));

  await sql.begin(async (tx) => {
    const ids = new Map<string, string>();
    for (const handle of seed.founders) {
      const [u] = await tx<{ id: string }[]>`
        INSERT INTO users (dev_sub, handle) VALUES (${`seed:${handle}`}, ${handle})
        ON CONFLICT (handle) DO UPDATE SET handle = EXCLUDED.handle RETURNING id`;
      ids.set(handle, u!.id);
    }
    const author = (h?: string, i = 0) => ids.get(h ?? seed.founders[i % seed.founders.length]!) ?? ids.get(seed.founders[0]!)!;

    const insertDrop = async (by: string, at: LatLng, n: z.infer<typeof Note>, extra: { isRelay?: boolean } = {}) => {
      const [d] = await tx<{ id: string }[]>`
        INSERT INTO drops (creator_id, geo, geohash7, type, body, teaser, status, is_relay)
        VALUES (${by}, ST_MakePoint(${at.lng}, ${at.lat})::geography, ${geohash(at, 7)}, 'text',
                ${n.body}, ${n.teaser ?? null}, 'approved', ${extra.isRelay ?? false})
        RETURNING id`;
      return d!.id;
    };

    let notes = 0;
    for (const lm of seed.landmarks) {
      for (const [i, n] of lm.notes.entries()) {
        await insertDrop(author(n.by, notes), scatter(lm.at, i), n);
        notes++;
      }
    }

    for (const t of seed.trails) {
      const by = author(t.by);
      const [trail] = await tx<{ id: string }[]>`INSERT INTO trails (creator_id, title) VALUES (${by}, ${t.title}) RETURNING id`;
      for (const [i, s] of t.stops.entries()) {
        const dropId = await insertDrop(by, s.at, s);
        await tx`INSERT INTO trail_stops (trail_id, drop_id, seq, clue) VALUES (${trail!.id}, ${dropId}, ${i + 1}, ${s.clue})`;
      }
    }

    for (const [i, r] of seed.relays.entries()) await insertDrop(author(r.by, i), r.at, r, { isRelay: true });

    console.log(
      `Seeded ${seed.campus}: ${seed.founders.length} founders, ${notes} notes, ` +
        `${seed.trails.length} trails, ${seed.relays.length} relays.`,
    );
  });
  await sql.end();
}

main().catch(async (err) => {
  console.error(err);
  await sql.end();
  process.exit(1);
});
