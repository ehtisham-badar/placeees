# Trace — MVP Specification

> A place-anchored social network. Content lives at physical locations, not in a feed.
> You can see that something exists nearby — you can only open it by being there.

---

## 0. How to use this doc

- This is the single source of truth for the MVP. Keep it in the repo root as `TRACE_MVP.md`.
- Feature IDs (`F-01`, `F-02`, …) are referenced in issues, branches, and commits.
- When working with AI coding tools, paste the relevant section (feature + data model + API) as context.
- Update the **Decision Log** (§14) whenever something changes.

---

## 1. Product principles

1. **Presence is the price of content.** Drops can only be created and opened on-site. No exceptions in the MVP.
2. **No global feed, no follower counts.** Discovery happens through the map and physically moving.
3. **Never expose a user's live location.** Only drop locations are stored and shown — and even those are fuzzed on the map.
4. **Rarity over volume.** Every interaction (reply, unlock, relay) costs real-world effort.
5. **Safe by default.** Moderation, exclusion zones, and anti-spoofing ship on day one.

---

## 2. Core loop to validate

```
Create drop on-site → Others see a fuzzy marker → They travel there
→ Proximity unlock → Content revealed → They echo / leave their own drop
```

**MVP succeeds if:** ≥60% of new users unlock at least one drop in their first session, and D7 retention ≥ 25% on the pilot campus.

---

## 3. Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Mobile | Flutter 3.47 (Dart 3.13), iOS + Android | `provider` + `ChangeNotifier`; app lives in `app/` |
| Maps | `flutter_map` (raster tiles) | Fuzzy circles via `CircleLayer`; tile URL via `MAP_TILE_URL` |
| Location | `geolocator` | Foreground only in phase 1; region monitoring later (F-15) |
| Haptics | Core Haptics | Hot/cold compass |
| Motion | CoreMotion | Heading/pitch for Then/Now alignment |
| Integrity | App Attest (iOS) / Play Integrity (Android) | Signs location payloads (F-17) |
| Auth | Sign in with Apple (iOS) + Google (iOS/Android) | Server issues JWT |
| Backend | Node.js + TypeScript + Fastify | Raw SQL via `postgres` (porsager) |
| DB | PostgreSQL 16 + PostGIS | GIST index on `geography` columns |
| Media | Cloudflare R2 (S3-compatible) | Pre-signed upload / signed read URLs |
| Jobs | BullMQ + Redis (or `pg-boss`) | Conditions, relay deadlines, capsule notifications |
| Push | APNs (token-based auth) | |
| Weather | Open-Meteo (free) or WeatherKit REST | Server-side condition evaluation |
| Sun position | `suncalc` (server) | Sunset/sunrise/night conditions |
| Moderation | OpenAI moderation API / AWS Rekognition | Text + image screening before publish |
| Hosting | Railway (API + Postgres + Redis) | |

---

## 4. Feature list

### Must ship (MVP)

| ID | Feature | Priority |
|---|---|---|
| F-01 | Auth (Sign in with Apple / Google) + handle | P0 |
| F-02 | Create drop on-site (photo / text / voice) | P0 |
| F-03 | Nearby map with fuzzy markers | P0 |
| F-04 | Proximity unlock (server-validated) | P0 |
| F-05 | Moderation pipeline + report/block | P0 |
| F-06 | Passport (private profile of unlocks & drops) | P0 |
| F-07 | Hot/cold haptic compass | P1 |
| F-08 | Conditional drops (sun / weather / time / date) | P1 |
| F-09 | Time capsules (place + future date) | P1 |
| F-10 | Trails (sequential unlock with clues) | P1 |
| F-11 | Echoes (location-bound replies) | P1 |
| F-12 | Circles (private groups) | P1 |
| F-13 | Relay drops (travelling drops) | P1 |
| F-14 | Then/Now drops (historical photo overlay) | P1 |
| F-15 | Widgets + Live Activities | P2 |
| F-16 | App Clip (QR/NFC venue drops) | P2 |
| F-17 | Anti-spoof hardening | P0 (iterative) |

### Deferred to v1.1

- Co-presence unlock (N people together)
- Fog-of-war map
- AR view (ARKit geo anchors)
- Place pulse heatmap
- Monetization (branded trails, venue accounts)

---

## 5. Feature specs

### F-02 — Create drop

**Flow:** Tap `+` → choose type → capture/record/write → add teaser (≤60 chars) → visibility (Public / Circle / Specific people) → optional conditions → Post.

**Rules**
- Drop location = device location at post time. No manual pin placement.
- Reject if `horizontalAccuracy > 65 m` ("Move to open sky for a better fix").
- Reject if inside the user's private exclusion zone (home) or a public exclusion zone (schools) for public drops.
- Max 10 drops/user/day, max 3 drops/user per geohash-7 cell per day.
- Media uploaded via pre-signed URL; drop is `pending_moderation` until screening passes.

**Acceptance criteria**
- [ ] Photo ≤ 10 MB compressed to HEIC/JPEG ≤ 1.5 MB before upload
- [ ] Voice ≤ 30 s, AAC
- [ ] Text ≤ 500 chars
- [ ] Drop is invisible to others until moderation status = `approved`

---

### F-03 — Nearby map

- Query radius: 2 km around the user (configurable).
- Markers are **fuzzy circles**: center offset 40–120 m from the real point, radius 150 m.
- Offset is **deterministic** per drop (seeded by drop ID) so markers don't jump between refreshes.
- Marker shows: type icon, age ("3 days"), teaser, lock badges (condition / capsule / trail / relay).
- Never return exact coordinates of locked drops to the client.

---

### F-04 — Proximity unlock

**Client sends a signed location payload:**

```json
{
  "lat": 31.5204,
  "lng": 74.3587,
  "accuracy": 18.4,
  "speed": 0.8,
  "timestamp": "2026-10-04T14:22:11Z",
  "assertion": "<App Attest assertion over payload hash>"
}
```

**Server validation (pseudocode):**

```ts
function canUnlock(drop, p, user): Result {
  verifyAppAttest(p.assertion, hash(p), user.attestKey)        // integrity
  if (now() - p.timestamp > 30s)            return fail("stale")
  if (p.accuracy > 80)                      return fail("low_accuracy")
  if (impossibleTravel(user.lastFix, p))    return fail("suspicious")  // > 300 km/h

  const radius = clamp(40 + p.accuracy, 40, 80)
  if (!stDWithin(drop.geo, point(p), radius)) return fail("too_far")

  if (!visibleTo(drop, user))               return fail("not_visible")
  if (!conditionsMet(drop.conditions, p))   return fail("condition_locked")
  if (drop.unlockAt && now() < drop.unlockAt) return fail("capsule_locked")
  if (drop.trailStop && !prevStopUnlocked(user, drop)) return fail("trail_order")

  recordUnlock(user, drop, p)
  return ok(signedMediaUrl(drop, ttl = 10min))
}
```

**Acceptance criteria**
- [ ] Unlock works within 40 m in open areas, up to 80 m in dense areas
- [ ] Media URLs are only issued after a successful unlock and expire in 10 minutes
- [ ] Once unlocked, the drop stays in the user's Passport and can be reopened anywhere

---

### F-07 — Hot/cold haptic compass

- Activates when a drop is within 300 m and the user taps "Find".
- Haptic pulse interval scales with distance: 2.0 s at 300 m → 0.15 s at < 20 m.
- Intensity rises as heading aligns with the bearing to the fuzzy target.
- Works with the screen locked (background location during an active hunt, max 15 min).
- Uses the **fuzzy** center until within 100 m, then switches to the true point (server returns a short-lived "near hint" token).

---

### F-08 — Conditional drops

Conditions are stored as JSON and evaluated server-side at unlock time.

```json
{
  "all": [
    { "type": "sun", "phase": "sunset", "windowMinutes": 45 },
    { "type": "weather", "is": "rain" },
    { "type": "timeRange", "from": "20:00", "to": "04:00", "tz": "Asia/Karachi" },
    { "type": "dateRange", "from": "2026-12-01", "to": "2026-12-31" }
  ]
}
```

| Type | Source | Notes |
|---|---|---|
| `sun` | `suncalc` | `sunrise`, `sunset`, `night`, `goldenHour` |
| `weather` | Open-Meteo current conditions | `rain`, `clear`, `cloudy`, `fog`; cache per geohash-5 for 10 min |
| `timeRange` | Server clock + tz | Supports overnight ranges |
| `dateRange` | Server clock | Inclusive |

The map marker shows the condition icon (🌅 / 🌧️ / 🌙) but not the exact rule unless the creator chooses to reveal it.

---

### F-09 — Time capsules

- A drop with `unlock_at` set in the future (min 24 h, max 25 years).
- Optional `recipients[]` — only those users can open it.
- Job queue schedules a push to creator + recipients on `unlock_at`.
- Marker shows a countdown.

---

### F-10 — Trails

- A trail is an ordered list of 3–15 drops created by one user.
- Each stop has a `clue` text revealed after unlocking the previous stop.
- Stop 1 is visible on the map; later stops are hidden until reached in order.
- Completion awards a stamp in the Passport.
- Active trail runs a Live Activity: stop N of M, distance to next stop.

---

### F-11 — Echoes

- Replies to a drop, allowed only when the user passes the same proximity check as F-04.
- Text only, ≤ 280 chars, moderated.
- Shown under the drop in chronological order with the date of each visit.

---

### F-12 — Circles

- Private groups (max 50 members in the MVP), joined by invite link.
- Drop visibility: `public` | `circle:<id>` | `users:[ids]`.
- Circle drops appear only on members' maps.

---

### F-13 — Relay drops

- Created like a normal drop, with `is_relay = true`.
- When unlocked, the user can **pick it up**: the drop leaves the map and enters their inventory.
- The carrier must **drop it** at a new location ≥ 1 km from the pickup point within 7 days, adding a short note.
- If they don't, it auto-returns to the last location.
- The relay's journey (all hops) is shown as a polyline on a dedicated screen.
- One carrier at a time; a user can't carry the same relay twice.

---

### F-14 — Then/Now drops

- Creator uploads a historical photo **while standing at the spot**, plus the capture heading and pitch (CoreMotion).
- On unlock, the camera opens with:
  - the old photo as a ghost overlay with an opacity slider
  - alignment guides showing heading/pitch delta until within ±5°
- Visitors can capture a "Now" photo; all Now photos form a timeline for the place.

---

### F-15 — Widgets & Live Activities

- **Widget (small/medium):** "3 drops within 500 m" → deep link to the compass.
- **Live Activity:** active trail progress, relay deadline countdown.
- **Region monitoring:** rotate the 20 nearest eligible drops into `CLMonitor` as the user moves. Notify at most 3 times/day.

---

### F-16 — App Clip

- A venue places a QR code or NFC tag at a location.
- Scanning opens an App Clip that shows the venue's drop after a proximity check.
- CTA: "Get Trace to leave your own drop."

---

### F-05 / F-17 — Safety & integrity

- [ ] Text + image moderation before a drop goes live
- [ ] Report drop / echo / user; block user
- [ ] Private home exclusion zone (200 m), set during onboarding, stored hashed/fuzzed
- [ ] Public exclusion zones (schools) for public drops — seeded list, admin-editable
- [ ] Never store user location history beyond `unlocks` and short-TTL presence data
- [ ] App Attest on all location-bearing requests
- [ ] Impossible-travel detection, rate limits per user and per geohash
- [ ] Anonymous drops allowed but always tied to an account server-side
- [ ] Minimal admin panel: moderation queue, takedowns, user bans

---

## 6. Data model (PostgreSQL + PostGIS)

```sql
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  apple_sub     TEXT UNIQUE NOT NULL,
  handle        TEXT UNIQUE NOT NULL,
  attest_key_id TEXT,
  home_zone     GEOGRAPHY(Point),          -- fuzzed, private
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TYPE drop_type AS ENUM ('photo', 'text', 'voice', 'then_now');
CREATE TYPE drop_status AS ENUM ('pending_moderation', 'approved', 'rejected', 'removed');

CREATE TABLE drops (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id       UUID REFERENCES users(id),
  geo              GEOGRAPHY(Point) NOT NULL,
  type             drop_type NOT NULL,
  body             TEXT,
  media_key        TEXT,
  teaser           TEXT,
  visibility       TEXT NOT NULL DEFAULT 'public',   -- public | circle | users
  circle_id        UUID,
  recipient_ids    UUID[],
  conditions       JSONB,
  unlock_at        TIMESTAMPTZ,
  expires_after    INT,                               -- unlock count, NULL = permanent
  is_anonymous     BOOLEAN DEFAULT false,
  is_relay         BOOLEAN DEFAULT false,
  relay_carrier_id UUID,
  capture_heading  REAL,                              -- then/now
  capture_pitch    REAL,
  status           drop_status DEFAULT 'pending_moderation',
  created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX drops_geo_idx ON drops USING GIST (geo);
CREATE INDEX drops_status_idx ON drops (status);

CREATE TABLE unlocks (
  user_id     UUID REFERENCES users(id),
  drop_id     UUID REFERENCES drops(id),
  accuracy    REAL,
  unlocked_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, drop_id)
);

CREATE TABLE echoes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drop_id    UUID REFERENCES drops(id),
  user_id    UUID REFERENCES users(id),
  body       TEXT NOT NULL,
  status     drop_status DEFAULT 'pending_moderation',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE trails (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID REFERENCES users(id),
  title      TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE trail_stops (
  trail_id UUID REFERENCES trails(id),
  drop_id  UUID REFERENCES drops(id),
  seq      INT NOT NULL,
  clue     TEXT,
  PRIMARY KEY (trail_id, seq)
);

CREATE TABLE circles (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   UUID REFERENCES users(id),
  name       TEXT NOT NULL,
  invite_code TEXT UNIQUE NOT NULL
);

CREATE TABLE circle_members (
  circle_id UUID REFERENCES circles(id),
  user_id   UUID REFERENCES users(id),
  PRIMARY KEY (circle_id, user_id)
);

CREATE TABLE relay_hops (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drop_id     UUID REFERENCES drops(id),
  carrier_id  UUID REFERENCES users(id),
  picked_at   TIMESTAMPTZ NOT NULL,
  pickup_geo  GEOGRAPHY(Point) NOT NULL,
  dropped_at  TIMESTAMPTZ,
  dropped_geo GEOGRAPHY(Point),
  note        TEXT
);

CREATE TABLE now_photos (            -- then/now contributions
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drop_id    UUID REFERENCES drops(id),
  user_id    UUID REFERENCES users(id),
  media_key  TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID REFERENCES users(id),
  target_type TEXT NOT NULL,          -- drop | echo | user
  target_id   UUID NOT NULL,
  reason      TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE exclusion_zones (
  id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name   TEXT,
  geo    GEOGRAPHY(Polygon) NOT NULL
);
CREATE INDEX exclusion_geo_idx ON exclusion_zones USING GIST (geo);
```

**Nearby query:**

```sql
SELECT id, type, teaser, created_at, conditions IS NOT NULL AS has_condition,
       unlock_at, is_relay, ST_AsText(geo) AS true_geo   -- fuzz before returning!
FROM drops
WHERE status = 'approved'
  AND relay_carrier_id IS NULL
  AND ST_DWithin(geo, ST_MakePoint($lng, $lat)::geography, $radius)
LIMIT 200;
```

---

## 7. API (v1)

All endpoints require `Authorization: Bearer <jwt>` except auth.
Location-bearing requests include the signed payload from F-04.

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/auth/apple` | Exchange Apple identity token for JWT |
| POST | `/v1/attest/register` | Register App Attest key |
| GET | `/v1/me` | Current user |
| PUT | `/v1/me/home-zone` | Set private exclusion zone |
| GET | `/v1/me/passport` | Unlocked + created drops, stamps |
| POST | `/v1/media/presign` | Get pre-signed upload URL |
| POST | `/v1/drops` | Create drop (with location payload) |
| GET | `/v1/drops/nearby?lat&lng&radius` | Fuzzy markers |
| POST | `/v1/drops/:id/near-hint` | Get true point when within 100 m (compass) |
| POST | `/v1/drops/:id/unlock` | Validate + return content and signed media URL |
| GET | `/v1/drops/:id` | Content (only if unlocked) |
| GET | `/v1/drops/:id/echoes` | List echoes |
| POST | `/v1/drops/:id/echoes` | Create echo (with location payload) |
| POST | `/v1/drops/:id/now-photos` | Then/Now contribution |
| POST | `/v1/relays/:id/pickup` | Pick up relay |
| POST | `/v1/relays/:id/drop` | Drop relay at new location |
| GET | `/v1/relays/:id/journey` | Hop polyline |
| POST | `/v1/trails` | Create trail |
| GET | `/v1/trails/:id` | Trail with progress |
| POST | `/v1/circles` | Create circle |
| POST | `/v1/circles/join` | Join by invite code |
| POST | `/v1/reports` | Report content/user |
| POST | `/v1/blocks/:userId` | Block user |
| POST | `/v1/devices` | Register APNs token |

**Error codes (unlock):** `too_far`, `low_accuracy`, `stale`, `suspicious`, `condition_locked`, `capsule_locked`, `trail_order`, `not_visible`.

---

## 8. iOS project structure

```
Trace/
├── App/
│   ├── TraceApp.swift
│   ├── AppRouter.swift
│   └── DependencyContainer.swift
├── Core/
│   ├── Networking/        APIClient, Endpoints, AuthInterceptor
│   ├── Location/          LocationService, RegionMonitor, LocationPayloadSigner
│   ├── Integrity/         AppAttestService
│   ├── Haptics/           HotColdEngine
│   ├── Motion/            HeadingPitchProvider
│   ├── Media/             ImageCompressor, VoiceRecorder, Uploader
│   └── Persistence/       SwiftData cache (passport, drafts)
├── Features/
│   ├── Onboarding/        SignIn, HomeZoneSetup, Permissions
│   ├── Map/               NearbyMapView, FuzzyMarker, MapViewModel
│   ├── CreateDrop/        Composer, ConditionsPicker, VisibilityPicker
│   ├── Unlock/            UnlockView, DropDetailView
│   ├── Compass/           CompassView, CompassViewModel
│   ├── Echoes/
│   ├── Trails/            TrailBuilder, TrailRunner
│   ├── Relays/            Inventory, RelayJourneyView
│   ├── ThenNow/           OverlayCameraView, AlignmentGuide
│   ├── Circles/
│   └── Passport/
├── Widgets/               TraceWidget, TrailLiveActivity
├── AppClip/
└── Tests/
    ├── Unit/
    └── UI/
```

**Info.plist keys:** `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSMotionUsageDescription`.

**Capabilities:** Sign in with Apple, Push Notifications, Background Modes (location, remote notifications), App Attest, App Groups (widgets), Associated Domains (App Clip).

---

## 9. Backend structure

```
trace-api/
├── src/
│   ├── server.ts
│   ├── config.ts
│   ├── db/              client.ts, migrations/
│   ├── auth/            apple.ts, jwt.ts
│   ├── integrity/       appAttest.ts, travelCheck.ts
│   ├── drops/           routes.ts, service.ts, fuzz.ts, unlock.ts
│   ├── conditions/      evaluate.ts, sun.ts, weather.ts
│   ├── trails/
│   ├── relays/
│   ├── circles/
│   ├── moderation/      text.ts, image.ts, queue.ts
│   ├── media/           r2.ts
│   ├── push/            apns.ts
│   └── jobs/            capsules.ts, relayDeadlines.ts
├── test/
└── docker-compose.yml   (postgis + redis for local dev)
```

---

## 10. Milestones

### Week 1–3 — Core loop
- [x] Repo setup (Flutter app + API), local docker-compose with PostGIS — CI pending
- [x] F-01 Sign in with Apple / Google + JWT + handle
- [x] F-02 Create drop (text + photo; voice later)
- [x] F-03 Nearby map with deterministic fuzzing
- [x] F-04 Unlock with server validation (attestation enforced in F-17)
- [x] F-05 Moderation pipeline (auto) + report/block — admin panel pending
- [x] F-06 Passport
- [ ] Deploy API to Railway

### Week 4–5 — Magic layer
- [x] F-07 Haptic compass (foreground; locked-screen hunting pending)
- [x] F-08 Conditional drops (sun, weather, time window, date range)
- [x] F-09 Time capsules + scheduled push (server side; app push registration pending)

### Week 6–7 — Social layer
- [x] F-10 Trails (Live Activity pending, ships with F-15)
- [x] F-11 Echoes
- [x] F-12 Circles

### Week 8–9 — Signature features
- [x] F-13 Relay drops + journey view
- [x] F-14 Then/Now overlay camera

### Week 10 — Surfaces & hardening
- [ ] F-15 Widgets + region-monitoring notifications
- [ ] F-16 App Clip
- [ ] F-17 App Attest, impossible-travel, rate limits

### Week 11–12 — Pilot
- [ ] Seed one campus: ~150 drops, 3 trails, 5 relays, 10 Then/Now spots
- [ ] TestFlight closed beta (50–100 users)
- [ ] Instrument metrics (§11)

---

## 11. Metrics

| Metric | Target (pilot) |
|---|---|
| First-session unlock rate | ≥ 60% |
| D1 / D7 retention | ≥ 45% / ≥ 25% |
| Drops created per WAU | ≥ 1.5 |
| Unlocks per drop (median) | ≥ 3 |
| Relay hops per relay | ≥ 4 |
| Trail completion rate | ≥ 35% |
| Moderation false-negative reports | < 1% of drops |

**Events to track:** `app_open`, `map_view`, `compass_start`, `unlock_attempt` (with failure reason), `unlock_success`, `drop_created`, `echo_created`, `trail_started`, `trail_completed`, `relay_picked`, `relay_dropped`, `capsule_opened`.

---

## 12. Seeding plan

- Pick one campus with high foot traffic.
- Create drops at gates, cafeterias, libraries, and landmarks before launch.
- Launch with a campus hunt (trail) tied to an event or orientation.
- Recruit 10 "founding droppers" from the student body to seed content in week one.
- Print QR posters for App Clip drops at 3–5 popular spots.

---

## 13. Open questions

- [ ] Default unlock radius — 40 m enough on campus, or start at 50 m?
- [ ] Should anonymous drops be allowed in the pilot, or added later?
- [ ] Weather provider: Open-Meteo (free, simpler) vs WeatherKit (Apple-native, quota)?
- [ ] Relay distance minimum — 1 km too much for a campus-only pilot?
- [ ] Name/brand: "Trace" availability (App Store, domain, trademark)

---

## 14. Decision log

| Date | Decision | Reason |
|---|---|---|
| — | Drops can only be created on-site | Core integrity of the product |
| — | No exact coordinates sent for locked drops | Preserve exploration + prevent scraping |
| — | Co-presence unlock and AR deferred to v1.1 | Scope; relays + conditions carry the virality |
| — | TimeLens merged as Then/Now drop type | Same core mechanic; avoid two products |
| 2026-10-04 | Mobile app built in Flutter instead of native SwiftUI | Ship iOS and Android from one codebase |
| 2026-10-04 | Google sign-in added alongside Sign in with Apple | Android users need a native sign-in option |
| 2026-10-04 | Play Integrity joins App Attest for F-17 | Android has no App Attest |
| 2026-10-04 | `users.handle` nullable until onboarding completes | Handle is chosen after the first sign-in |
| 2026-10-04 | Drops auto-hide after 3 distinct reports, pending review | Limits harm before a moderator looks |
| 2026-10-04 | Conditional drops stay `condition_locked` until F-08 ships | No unlock path skips the rule engine |
| 2026-10-04 | Capsule notifications run as an in-process minute job, not BullMQ/pg-boss | One atomic `UPDATE … RETURNING` claim is enough at pilot scale; no Redis needed yet |
| 2026-10-04 | Conditions carry an IANA time zone (`tz`) on time and date rules | "20:00" must mean the creator's local evening |
| 2026-10-04 | Unknown weather (provider down) never satisfies a weather rule | Fail closed: a drop never opens on a guess |
| 2026-10-04 | Capsule checks run before condition checks on unlock | A sealed capsule never triggers a weather lookup |
| 2026-10-04 | Compass haptics use platform impact levels (light/medium/heavy) | Flutter has no Core Haptics intensity curve; three levels read clearly |
| 2026-10-05 | Trail clue on stop N leads to stop N; stop 1's clue shows from the start | One clue per stop, revealed in order |
| 2026-10-05 | Trail stops must be the creator's own public drops, each in at most one trail | Keeps visibility simple; circle trails can come later |
| 2026-10-05 | Echoes require an unlock **and** the F-04 presence check | Replies stay as rare and place-bound as the drops |
| 2026-10-05 | Circle owners can't leave; no kick/delete in the MVP | Smallest safe surface; revisit after the pilot |
| 2026-10-05 | School exclusion zones apply to public drops only; home zone applies to all | Matches §5 F-02 wording |
| 2026-10-05 | A drop goes to a circle or to named recipients, never both | Avoids ambiguous visibility |
| 2026-10-05 | Relays can't be picked up by their creator, and must be unlocked first | Carrying is for finders |
| 2026-10-05 | A user carries at most 3 relays at once | Stops hoarding |
| 2026-10-05 | Relay journey points are fuzzed like map markers (current spot matches the map circle) | A journey must never pinpoint where the relay rests now |
| 2026-10-05 | Relays are always public (no capsule, circle or recipients) | Matches "travelling drop" intent; simpler visibility |
| 2026-10-05 | Background jobs share one minute tick (`jobs/index.ts`): capsules, relay returns, deadline warnings | Each job claims rows atomically |
| 2026-10-05 | Then/Now alignment tolerance ±5° on heading and pitch; pitch from the accelerometer | Matches spec; no gyro fusion needed at this tolerance |
