import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { sql } from '../src/db/client.js';
import { returnOverdueRelays } from '../src/jobs/relays.js';
import { notifyOpenedCapsules } from '../src/jobs/capsules.js';
import { destination, distanceM, type LatLng } from '../src/lib/geo.js';

// A walkable patch of Lahore. Points are metres apart unless a test says otherwise.
const P: LatLng = { lat: 31.5204, lng: 74.3587 };
const at = (bearing: number, meters: number, from = P) => destination(from, bearing, meters);
const fix = (p: LatLng, accuracy = 10) => ({ lat: p.lat, lng: p.lng, accuracy, timestamp: new Date().toISOString() });
const ADMIN = { 'x-admin-token': 'test-admin-token-test-admin-token' };

let app: FastifyInstance;
const users: Record<string, { token: string; id: string }> = {};

async function call(who: string | null, method: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE', url: string, payload?: unknown) {
  const headers = who ? { authorization: `Bearer ${users[who]!.token}` } : {};
  const res = await app.inject({ method, url, payload: payload as never, headers });
  return { status: res.statusCode, body: res.body ? (res.json() as any) : null };
}
const admin = async (method: 'GET' | 'POST', url: string, payload?: unknown) => {
  const res = await app.inject({ method, url, payload: payload as never, headers: ADMIN });
  return { status: res.statusCode, body: res.json() as any };
};

/** Moderation runs after the response; wait for it to settle. */
async function until<T>(fn: () => Promise<T>, ok: (v: T) => boolean, ms = 5000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const v = await fn();
    if (ok(v) || Date.now() > end) return v;
    await new Promise((r) => setTimeout(r, 100));
  }
}

/** Pretend a user's last fix was an hour ago, so a long move isn't "impossible travel". */
const rewind = (who: string) => sql`UPDATE users SET last_fix_at = now() - interval '1 hour' WHERE id = ${users[who]!.id}`;

async function createDrop(who: string, where: LatLng, extra: Record<string, unknown> = {}) {
  await rewind(who);
  const res = await call(who, 'POST', '/v1/drops', { type: 'text', body: `hello from ${who}`, location: fix(where), ...extra });
  expect(res.status, JSON.stringify(res.body)).toBe(201);
  await until(
    async () => (await sql`SELECT status FROM drops WHERE id = ${res.body.id}`)[0]?.status,
    (s) => s !== 'pending_moderation',
  );
  return res.body.id as string;
}

async function nearby(who: string, where: LatLng) {
  const res = await call(who, 'GET', `/v1/drops/nearby?lat=${where.lat}&lng=${where.lng}`);
  expect(res.status).toBe(200);
  return res.body.drops as any[];
}

async function unlock(who: string, id: string, where: LatLng) {
  await rewind(who);
  return call(who, 'POST', `/v1/drops/${id}/unlock`, { location: fix(where) });
}

beforeAll(async () => {
  app = buildApp();
  for (const name of ['alice', 'bob', 'carol', 'dave', 'erin']) {
    const res = await call(null, 'POST', '/v1/auth/dev', { name });
    users[name] = { token: res.body.token, id: res.body.user.id };
    expect((await call(name, 'PATCH', '/v1/me', { handle: name })).status).toBe(200);
  }
});

afterAll(async () => {
  await app.close();
  await sql.end();
});

describe('core loop', () => {
  let dropId: string;

  it('creates a drop on site and fuzzes it on the map', async () => {
    dropId = await createDrop('alice', P, { teaser: 'Look up.' });
    const seen = (await nearby('bob', P)).find((d) => d.id === dropId);
    expect(seen.teaser).toBe('Look up.');
    const offset = distanceM(seen.center, P);
    expect(offset).toBeGreaterThanOrEqual(39);
    expect(offset).toBeLessThanOrEqual(121);
    expect(JSON.stringify(seen)).not.toContain(String(P.lat));
  });

  it('refuses a drop with a weak GPS fix', async () => {
    const res = await call('alice', 'POST', '/v1/drops', { type: 'text', body: 'x', location: fix(at(0, 500), 120) });
    expect(res.body.error).toBe('low_accuracy');
  });

  it('only unlocks on site, then reopens anywhere', async () => {
    expect((await call('bob', 'GET', `/v1/drops/${dropId}`)).body.error).toBe('locked');
    expect((await unlock('bob', dropId, at(90, 400))).body.error).toBe('too_far');
    const opened = await unlock('bob', dropId, at(90, 20));
    expect(opened.status).toBe(200);
    expect(opened.body.body).toBe('hello from alice');
    expect(opened.body.author.handle).toBe('alice');
    expect((await call('bob', 'GET', `/v1/drops/${dropId}`)).status).toBe(200);
  });

  it('flags impossible travel', async () => {
    await call('carol', 'GET', '/v1/me');
    await unlock('carol', dropId, at(0, 15)); // establishes a fresh fix
    const res = await call('carol', 'POST', `/v1/drops/${dropId}/unlock`, { location: fix(at(0, 150_000)) });
    expect(res.body.error).toBe('suspicious');
    const [ev] = await sql`SELECT kind FROM integrity_events WHERE user_id = ${users.carol!.id} AND kind = 'impossible_travel'`;
    expect(ev).toBeDefined();
  });

  it('keeps the passport', async () => {
    const bob = (await call('bob', 'GET', '/v1/me/passport')).body;
    expect(bob.unlocked.map((d: any) => d.id)).toContain(dropId);
    const alice = (await call('alice', 'GET', '/v1/me/passport')).body;
    expect(alice.created.find((d: any) => d.id === dropId).unlockCount).toBeGreaterThanOrEqual(1);
  });

  it('takes echoes only in person, after unlocking', async () => {
    expect((await call('dave', 'POST', `/v1/drops/${dropId}/echoes`, { body: 'hi', location: fix(P) })).body.error).toBe('locked');
    await rewind('bob');
    expect((await call('bob', 'POST', `/v1/drops/${dropId}/echoes`, { body: 'hi', location: fix(at(0, 900)) })).body.error).toBe(
      'too_far',
    );
    await rewind('bob');
    expect((await call('bob', 'POST', `/v1/drops/${dropId}/echoes`, { body: 'Thank you, stranger.', location: fix(P) })).status).toBe(201);
    const echoes = await until(
      async () => (await call('alice', 'GET', `/v1/drops/${dropId}/echoes`)).body.echoes,
      (e: any[]) => e.length === 1,
    );
    expect(echoes[0].authorHandle).toBe('bob');
  });

  it('hides blocked authors', async () => {
    expect((await call('erin', 'POST', `/v1/drops/${dropId}/block-author`)).status).toBe(201);
    expect((await nearby('erin', P)).map((d) => d.id)).not.toContain(dropId);
  });
});

describe('magic layer', () => {
  it('keeps capsules sealed until their date, then notifies', async () => {
    const id = await createDrop('dave', at(180, 300), { unlockAt: new Date(Date.now() + 2 * 86_400_000).toISOString() });
    const res = await unlock('bob', id, at(180, 300));
    expect(res.body.error).toBe('capsule_locked');
    await sql`UPDATE drops SET unlock_at = now() - interval '1 minute' WHERE id = ${id}`;
    expect(await notifyOpenedCapsules()).toBeGreaterThanOrEqual(1);
    expect((await unlock('bob', id, at(180, 300))).status).toBe(200);
  });

  it('keeps conditional drops locked outside their window', async () => {
    const id = await createDrop('dave', at(200, 600), {
      conditions: { all: [{ type: 'dateRange', from: '2020-01-01', to: '2020-01-02', tz: 'Asia/Karachi' }] },
      revealConditions: true,
    });
    const onMap = (await nearby('bob', at(200, 600))).find((d) => d.id === id);
    expect(onMap.badges.conditionKinds).toEqual(['dateRange']);
    expect(onMap.badges.conditions.all[0].from).toBe('2020-01-01');
    expect((await unlock('bob', id, at(200, 600))).body.error).toBe('condition_locked');
  });

  it('gives a near hint only within 100 m', async () => {
    const id = await createDrop('dave', at(220, 800));
    await rewind('bob');
    expect((await call('bob', 'POST', `/v1/drops/${id}/near-hint`, { location: fix(at(220, 1100)) })).body.error).toBe('too_far');
    await rewind('bob');
    const hint = await call('bob', 'POST', `/v1/drops/${id}/near-hint`, { location: fix(at(220, 760)) });
    expect(distanceM(hint.body.point, at(220, 800))).toBeLessThan(1);
  });
});

describe('social layer', () => {
  it('shows circle drops to members only', async () => {
    const circle = (await call('alice', 'POST', '/v1/circles', { name: 'Hostel 4' })).body;
    expect(circle.inviteCode).toMatch(/^[2-9A-HJKMNP-Z]{8}$/);
    expect((await call('bob', 'POST', '/v1/circles/join', { code: circle.inviteCode.toLowerCase() })).status).toBe(200);
    const id = await createDrop('alice', at(45, 700), { circleId: circle.id });
    expect((await nearby('bob', at(45, 700))).map((d) => d.id)).toContain(id);
    expect((await nearby('carol', at(45, 700))).map((d) => d.id)).not.toContain(id);
    expect((await call('alice', 'POST', `/v1/circles/${circle.id}/leave`)).body.error).toBe('owner_cannot_leave');
  });

  it('runs a trail in order and stamps the passport', async () => {
    const stops = [at(300, 1000), at(300, 1200), at(300, 1400)];
    const ids: string[] = [];
    for (const s of stops) ids.push(await createDrop('erin', s));
    const trail = await call('erin', 'POST', '/v1/trails', {
      title: 'Old City Hunt',
      stops: ids.map((dropId, i) => ({ dropId, clue: `clue ${i + 1}` })),
    });
    expect(trail.status).toBe(201);

    const map = await nearby('dave', stops[1]!);
    expect(map.map((d) => d.id)).toContain(ids[0]);
    expect(map.map((d) => d.id)).not.toContain(ids[1]);
    expect((await unlock('dave', ids[1]!, stops[1]!)).body.error).toBe('trail_order');

    const first = await unlock('dave', ids[0]!, stops[0]!);
    expect(first.body.trail.nextClue).toBe('clue 2');
    await unlock('dave', ids[1]!, stops[1]!);
    const last = await unlock('dave', ids[2]!, stops[2]!);
    expect(last.body.trail.completedAt).not.toBeNull();
    expect((await call('dave', 'GET', '/v1/me/passport')).body.stamps[0].title).toBe('Old City Hunt');
  });
});

describe('relays', () => {
  it('travels from finder to finder', async () => {
    const start = at(120, 1500);
    const id = await createDrop('carol', start, { isRelay: true });
    expect((await call('bob', 'POST', `/v1/relays/${id}/pickup`, { location: fix(start) })).body.error).toBe('locked');
    await unlock('bob', id, start);
    await rewind('bob');
    const picked = await call('bob', 'POST', `/v1/relays/${id}/pickup`, { location: fix(start) });
    expect(picked.status, JSON.stringify(picked.body)).toBe(200);
    expect((await nearby('dave', start)).map((d) => d.id)).not.toContain(id);
    expect((await call('bob', 'GET', '/v1/relays/carrying')).body.relays[0].id).toBe(id);

    await rewind('bob');
    expect((await call('bob', 'POST', `/v1/relays/${id}/drop`, { location: fix(at(0, 400, start)) })).body.error).toBe('too_close');
    await rewind('bob');
    const dropped = await call('bob', 'POST', `/v1/relays/${id}/drop`, { location: fix(at(0, 1300, start)), note: 'Your turn.' });
    // PostGIS measures on the WGS84 ellipsoid; our helper uses a sphere (~0.3% apart here).
    expect(dropped.body.distanceM).toBeGreaterThan(1280);

    const journey = (await call('carol', 'GET', `/v1/relays/${id}/journey`)).body;
    expect(journey.hops).toHaveLength(1);
    expect(journey.hops[0].note).toBe('Your turn.');
    expect(journey.totalDistanceM).toBeGreaterThan(1280);
  });

  it('goes home when the carrier runs out of time', async () => {
    const start = at(140, 1800);
    const id = await createDrop('carol', start, { isRelay: true });
    await unlock('erin', id, start);
    await rewind('erin');
    await call('erin', 'POST', `/v1/relays/${id}/pickup`, { location: fix(start) });
    await sql`UPDATE relay_hops SET deadline_at = now() - interval '1 minute' WHERE drop_id = ${id}`;
    expect(await returnOverdueRelays()).toBe(1);
    expect((await nearby('dave', start)).map((d) => d.id)).toContain(id);
  });
});

describe('surfaces & admin', () => {
  it('turns a venue code into a drop and a landing page', async () => {
    const dropId = (await nearby('bob', P))[0].id;
    const venue = await admin('POST', '/v1/admin/venues', { dropId, name: 'Chai stall' });
    expect(venue.status).toBe(201);
    expect((await call('bob', 'GET', `/v1/venues/${venue.body.code}`)).body.name).toBe('Chai stall');
    const page = await app.inject({ method: 'GET', url: `/v/${venue.body.code}` });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain('Chai stall');
  });

  it('moderates from the queue and bans', async () => {
    expect((await admin('GET', '/v1/admin/queue')).status).toBe(200);
    expect((await admin('GET', '/v1/admin/reports')).status).toBe(200);
    expect((await admin('GET', '/v1/admin/integrity')).body.summary.length).toBeGreaterThan(0);
    expect((await admin('POST', `/v1/admin/users/${users.erin!.id}/ban`, { banned: true })).status).toBe(200);
    expect((await call('erin', 'GET', '/v1/me')).body.error).toBe('banned');
  });

  it('records events and computes pilot metrics', async () => {
    const now = new Date().toISOString();
    const res = await call('bob', 'POST', '/v1/events', {
      events: [
        { name: 'app_open', at: now },
        { name: 'unlock_attempt', at: now, props: { reason: 'too_far' } },
      ],
    });
    expect(res.status).toBe(204);
    const m = (await admin('GET', '/v1/admin/metrics?days=7')).body;
    expect(m.metrics.newUsers).toBe(5);
    expect(m.metrics.firstSessionUnlockRate).toBeGreaterThan(0);
    // Every target has a matching metric, so the admin dashboard can show them all.
    for (const key of Object.keys(m.targets)) expect(m.metrics, key).toHaveProperty(key);
    expect(m.unlockFailures[0]).toEqual({ reason: 'too_far', count: 1 });
  });
});

describe('push devices', () => {
  it('registers, moves between accounts, and unregisters', async () => {
    const token = 'f'.repeat(64);
    expect((await call('alice', 'POST', '/v1/devices', { token, platform: 'ios' })).status).toBe(204);
    // Same phone, different account: the token follows whoever registered it last.
    expect((await call('bob', 'POST', '/v1/devices', { token, platform: 'ios' })).status).toBe(204);
    const [row] = await sql`SELECT user_id FROM devices WHERE token = ${token}`;
    expect(row!.userId).toBe(users.bob!.id);
    // Only the owner can remove it.
    await call('alice', 'DELETE', `/v1/devices/${token}`);
    expect((await sql`SELECT 1 FROM devices WHERE token = ${token}`).length).toBe(1);
    await call('bob', 'DELETE', `/v1/devices/${token}`);
    expect((await sql`SELECT 1 FROM devices WHERE token = ${token}`).length).toBe(0);
  });
});

describe('voice drops (local media store)', () => {
  it('uploads, gates behind an unlock, and plays back', async () => {
    const where = at(30, 1900);
    const presign = await call('alice', 'POST', '/v1/media/presign', { contentType: 'audio/mp4' });
    expect(presign.status).toBe(200);
    expect(presign.body.key).toMatch(/\.m4a$/);
    const audio = Buffer.from('fake-aac-bytes-for-test');
    const put = await app.inject({
      method: 'PUT',
      url: presign.body.url.replace('http://localhost', ''),
      payload: audio,
      headers: { 'content-type': 'audio/mp4' },
    });
    expect(put.statusCode).toBe(200);

    // A photo key can't masquerade as a voice drop, and vice versa.
    await rewind('alice');
    expect(
      (await call('alice', 'POST', '/v1/drops', { type: 'photo', mediaKey: presign.body.key, location: fix(where) })).body.error,
    ).toBe('wrong_media_type');

    const waveform = Array.from({ length: 32 }, (_, i) => (i % 8) / 8);
    const id = await createDrop('alice', where, { type: 'voice', mediaKey: presign.body.key, waveform, teaser: 'Listen.' });
    expect((await call('bob', 'GET', `/v1/drops/${id}`)).body.error).toBe('locked');

    const opened = await unlock('bob', id, where);
    expect(opened.body.type).toBe('voice');
    expect(opened.body.waveform).toHaveLength(32);
    const file = await app.inject({ method: 'GET', url: opened.body.mediaUrl.replace('http://localhost', '') });
    expect(file.statusCode).toBe(200);
    expect(file.headers['content-type']).toBe('audio/mp4');
    expect(file.rawPayload.equals(audio)).toBe(true);

    // Tampering with the signed URL is refused.
    const tampered = opened.body.mediaUrl.replace('http://localhost', '').replace(/sig=[^&]+/, 'sig=nope');
    expect((await app.inject({ method: 'GET', url: tampered })).statusCode).toBe(403);
  });
});

describe('home quiet zone', () => {
  it('blocks public drops at home, allows circle drops, and can be turned off', async () => {
    const home = at(270, 2500);
    await rewind('dave');
    expect((await call('dave', 'PUT', '/v1/me/home-zone', { lat: home.lat, lng: home.lng })).body.hasHomeZone).toBe(true);

    await rewind('dave');
    const pub = await call('dave', 'POST', '/v1/drops', { type: 'text', body: 'hi', location: fix(at(0, 30, home)) });
    expect(pub.body.error).toBe('home_zone');

    const circle = (await call('dave', 'POST', '/v1/circles', { name: 'Family' })).body;
    await rewind('dave');
    const inCircle = await call('dave', 'POST', '/v1/drops', {
      type: 'text',
      body: 'for family',
      circleId: circle.id,
      location: fix(at(0, 30, home)),
    });
    expect(inCircle.status).toBe(201);

    expect((await call('dave', 'DELETE', '/v1/me/home-zone')).body.hasHomeZone).toBe(false);
    await rewind('dave');
    expect((await call('dave', 'POST', '/v1/drops', { type: 'text', body: 'hi', location: fix(at(0, 30, home)) })).status).toBe(201);
  });
});

describe('admin users', () => {
  it('lists accounts with provider and counts, and searches by handle', async () => {
    const all = (await admin('GET', '/v1/admin/users')).body.users;
    const bob = all.find((u: any) => u.handle === 'bob');
    expect(bob.provider).toBe('dev');
    expect(bob.unlocks).toBeGreaterThan(0);
    expect(Object.keys(bob)).not.toContain('appleSub');
    expect(JSON.stringify(all)).not.toMatch(/googleSub|appleSub|lastFixGeo/);
    const found = (await admin('GET', '/v1/admin/users?q=ali')).body.users;
    expect(found.map((u: any) => u.handle)).toEqual(['alice']);
  });
});

describe('pre-upload check', () => {
  it('refuses before any upload, and passes when the drop would be accepted', async () => {
    const home = at(300, 3200);
    await rewind('carol');
    await call('carol', 'PUT', '/v1/me/home-zone', { lat: home.lat, lng: home.lng });
    await rewind('carol');
    const atHome = await call('carol', 'POST', '/v1/drops/check', { type: 'photo', location: fix(at(0, 20, home)) });
    expect(atHome.body.error).toBe('home_zone');
    await rewind('carol');
    const weak = await call('carol', 'POST', '/v1/drops/check', { type: 'voice', location: fix(at(0, 900, home), 120) });
    expect(weak.body.error).toBe('low_accuracy');
    await rewind('carol');
    const ok = await call('carol', 'POST', '/v1/drops/check', { type: 'voice', location: fix(at(0, 900, home)) });
    expect(ok.status).toBe(204);
    // Nothing was created by checking.
    const [{ count }] = await sql`SELECT count(*)::int FROM drops WHERE creator_id = ${users.carol!.id} AND type = 'voice'`;
    expect(count).toBe(0);
  });
});
