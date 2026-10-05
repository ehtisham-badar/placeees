# Trace — pilot runbook (Phase 6)

Everything here needs your accounts (Railway, Cloudflare, Apple, Google), so it's a checklist for you
rather than something the repo can do on its own. Spec references: `TRACE_MVP.md` §10–§12.

## Current deployment (2026-10-06)

- Railway project **trace**: `postgis` (postgis/postgis:16-3.4 on a volume, private network only) and
  `api` (this repo's Dockerfile, public at `https://api-production-c9db.up.railway.app`).
- Media: `LOCAL_MEDIA_DIR=/data/media` on an `api` volume until R2 is set up.
- Sign-in: dev sign-in guarded by `DEV_LOGIN_CODE` until Google/Apple sign-in is configured.
- Deploy: automatic. Every push to `main` that touches `trace-api/` builds and deploys the `api`
  service (config in `trace-api/.railway/railway.ts`; preview changes with `railway config plan`).
- Secrets (JWT, admin token, DB password, dev login code) live only in Railway variables.
- Railway config is infrastructure-as-code (`.railway/railway.ts`); secrets use `preserve()` so they
  never enter the repo. Always run `railway config plan` before `apply`: anything not declared is removed.

## 1. Deploy the API (Railway)

1. Create a Railway project → **Add PostgreSQL**. In its *Data* tab run `CREATE EXTENSION postgis;`
   (or use Railway's PostGIS template).
2. **New service → GitHub repo**, root directory `trace-api`. Railway picks up `railway.json` and the
   `Dockerfile`; migrations run on every boot (they're transactional and idempotent).
3. Variables (see `trace-api/.env.example`):
   | Variable | Value |
   |---|---|
   | `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
   | `JWT_SECRET` | 48+ random characters |
   | `ADMIN_TOKEN` | another 48+ random characters |
   | `APPLE_BUNDLE_ID` / `APPLE_TEAM_ID` | `app.trace.mobile` / your team id |
   | `GOOGLE_CLIENT_IDS` | iOS + Android + web OAuth client ids |
   | `R2_*` | Cloudflare R2 bucket + key (photos) |
   | `OPENAI_API_KEY` | moderation |
   | `INTEGRITY_MODE` | `report` for the pilot (see §5) |
   | `PUBLIC_WEB_URL` | your domain, e.g. `https://trace.app` |
4. Point the domain at the service. `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json`
   and `/v/<code>` are served by the API.
5. Check: `GET /health` → `{"ok":true}`; open `/admin` with the admin token.

## 2. Seed the campus

1. Copy `trace-api/seed/campus.example.json`, replace the landmarks (gates, cafeterias, libraries) with
   real coordinates and write the founders' content (target: ~150 notes, 3 trails, 5 relays).
2. `DATABASE_URL=<railway url> npm run seed -- seed/<campus>.json` from `trace-api/`.
3. Then/Now spots need photos, so create those in the app on site.
4. Print venue QR posters: `/admin` → Venues → create a code per poster spot → print the URL as a QR.

## 3. Build the apps

```bash
cd app
# iOS → TestFlight (Xcode: Product → Archive → Distribute → TestFlight)
flutter build ipa --release \
  --dart-define=TRACE_API_URL=https://api.trace.app \
  --dart-define=MAP_TILE_URL='https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}.png?key=KEY' \
  --dart-define=GOOGLE_IOS_CLIENT_ID=... --dart-define=GOOGLE_SERVER_CLIENT_ID=...

# Android → Play internal testing
flutter build appbundle --release \
  --dart-define=TRACE_API_URL=https://api.trace.app \
  --dart-define=MAP_TILE_URL='...' --dart-define=GOOGLE_SERVER_CLIENT_ID=... \
  --dart-define=PLAY_CLOUD_PROJECT_NUMBER=...
```

Before the first store build:
- **Android signing:** create an upload key and `app/android/key.properties`
  (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). It's git-ignored.
- **iOS capabilities** (Runner target): Sign in with Apple, App Attest, Push Notifications,
  Associated Domains (`applinks:trace.app`), App Groups (`group.app.trace.mobile`, for the widget).
- **iOS widget:** add the extension target once (`app/ios/TraceWidget/README.md`).
- **Map tiles:** the default darkened OpenStreetMap tiles are for development only. Use a paid
  provider (MapTiler, Stadia) via `MAP_TILE_URL` for the pilot.
- **Push:** set `APNS_*` and `FCM_*` on the API. (The app doesn't register device tokens yet; add
  Firebase Messaging before relying on capsule/relay pushes.)

## 4. Launch week

- Recruit ~10 founding droppers; give them the app a week before the event.
- Run the orientation trail as the launch hunt.
- Watch `/admin` → **Metrics** daily against the §11 targets, and **Queue** for moderation.

## 5. Integrity rollout

`INTEGRITY_MODE=report` for the first weeks. In `/admin` → **Integrity**, false positives should be
rare before switching to `enforce`. Mock-location and impossible-travel events are always logged.

## 6. What's verified, and what isn't

| Verified in this repo | Not yet verified |
|---|---|
| Unit tests (API + app), PostGIS integration suite, CI | Real Apple/Google sign-in, App Attest, Play Integrity |
| Release builds for iOS (simulator) and Android (device) | Push delivery, background geofence alerts on a walk |
| Demo-mode walkthrough on simulator and a Galaxy S24 | iOS widget extension, App Clip, Live Activities |
