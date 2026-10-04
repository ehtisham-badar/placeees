# Trace

A place-anchored social network. Content lives at physical locations, not in a feed.
You can see that something exists nearby — you can only open it by being there.

The full product spec is in [`TRACE_MVP.md`](TRACE_MVP.md).

| Folder | What |
|---|---|
| `app/` | Flutter app (iOS + Android) |
| `trace-api/` | Node.js + TypeScript + Fastify API on PostgreSQL/PostGIS |

## Run the app (demo mode — no backend needed)

```bash
cd app
flutter pub get
flutter run
```

Without `TRACE_API_URL` the app runs against an in-memory demo backend that seeds hand-written
drops around your location. Tap a glow, then **Demo: walk there** to feel the unlock. The demo also seeds a three-stop trail,
a circle you're in, one you can join with the code `WANDER29`, a relay that has already
travelled across the city, and a Then/Now spot from 1965.
Add `--dart-define=DEMO_AUTOSTART=true` to skip sign-in and onboarding.

## Run against the API

```bash
cd trace-api
cp .env.example .env              # set ALLOW_DEV_LOGIN=true for local work
docker compose up -d db           # PostGIS 16
npm install
npm run migrate
npm run dev                       # http://localhost:3000

cd ../app
flutter run --dart-define=TRACE_API_URL=http://localhost:3000
```

(Android emulator: use `http://10.0.2.2:3000`.)

### Configuration

| Where | Key | Purpose |
|---|---|---|
| app | `TRACE_API_URL` | API base URL. Empty = demo mode |
| app | `MAP_TILE_URL` | Dark raster tile URL for production (MapTiler, Stadia, …). Empty = recoloured OSM tiles, dev only |
| app | `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` | Google sign-in client ids |
| api | `APPLE_BUNDLE_ID` | Audience for Sign in with Apple tokens (`app.trace.mobile`) |
| api | `GOOGLE_CLIENT_IDS` | Accepted Google token audiences |
| api | `R2_*` | Cloudflare R2 for photo uploads |
| api | `OPENAI_API_KEY` | Text + image moderation (local word filter otherwise) |
| api | `APNS_*`, `FCM_*` | Push for opened time capsules (skipped when unset) |
| api | `RUN_JOBS` | Run the capsule notification job in this process (default `true`) |

Google sign-in on iOS also needs the reversed client id added as a URL scheme in
`ios/Runner/Info.plist`; Sign in with Apple needs a signing team with the capability enabled.

## Tests

```bash
cd trace-api && npm test          # fuzzing, unlock rules, travel checks, geohash
cd app && flutter test            # formatting, fuzzing/sun parity, conditions, compass, demo flows

# UI walkthrough with screenshots saved to app/build/screenshots/
cd app && flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screens_test.dart --dart-define=DEMO_AUTOSTART=true -d <device>
```

## Status

**Phase 1 — core loop (done):** sign-in + handle, onboarding with location promises and home
quiet zone, night map with fuzzy markers, on-site photo/text drops, server-validated unlock,
moderation + report/block, Passport.

**Phase 2 — magic layer (done):** hot/cold haptic compass with a server near-hint inside 100 m
(F-07), conditional drops on sun phase, weather, time window and date range (F-08), time capsules
with recipients and an "opened" push job (F-09).

Still open from phase 2: hunting with the screen locked (background location) and registering
device push tokens in the app (needs Firebase/APNs credentials).

**Phase 3 — social layer (done):** trails with ordered clues, hidden later stops and passport
stamps (F-10); echoes that can only be left in person (F-11); circles with invite codes and
members-only drops (F-12).

**Phase 4 — signature features (done):** relay drops you pick up, carry ≥ 1 km within 7 days and
drop again, with a journey map and auto-return (F-13); Then/Now drops with a saved camera angle,
a ghost-overlay alignment camera and a "now" timeline (F-14).

**Next — Phase 5 (surfaces & hardening):** widgets and region notifications (F-15), App Clip /
Android instant link (F-16), App Attest + Play Integrity, rate limits (F-17).
