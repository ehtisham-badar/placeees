CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  apple_sub     TEXT UNIQUE,
  google_sub    TEXT UNIQUE,
  dev_sub       TEXT UNIQUE,
  handle        TEXT UNIQUE,                   -- NULL until chosen during onboarding
  attest_key_id TEXT,
  home_zone     GEOGRAPHY(Point),              -- fuzzed, private
  last_fix_geo  GEOGRAPHY(Point),              -- single most recent fix, for impossible-travel checks
  last_fix_at   TIMESTAMPTZ,
  banned_at     TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now(),
  CHECK (apple_sub IS NOT NULL OR google_sub IS NOT NULL OR dev_sub IS NOT NULL),
  CHECK (handle IS NULL OR handle ~ '^[a-z0-9_.]{3,20}$')
);

CREATE TYPE drop_type AS ENUM ('photo', 'text', 'voice', 'then_now');
CREATE TYPE drop_status AS ENUM ('pending_moderation', 'approved', 'rejected', 'removed');

CREATE TABLE drops (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id       UUID NOT NULL REFERENCES users(id),
  geo              GEOGRAPHY(Point) NOT NULL,
  geohash7         TEXT NOT NULL,
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
  is_anonymous     BOOLEAN NOT NULL DEFAULT false,
  is_relay         BOOLEAN NOT NULL DEFAULT false,
  relay_carrier_id UUID,
  capture_heading  REAL,
  capture_pitch    REAL,
  status           drop_status NOT NULL DEFAULT 'pending_moderation',
  moderation_note  TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX drops_geo_idx ON drops USING GIST (geo);
CREATE INDEX drops_status_idx ON drops (status);
CREATE INDEX drops_creator_day_idx ON drops (creator_id, created_at);
CREATE INDEX drops_cell_day_idx ON drops (geohash7, created_at);

CREATE TABLE unlocks (
  user_id     UUID REFERENCES users(id),
  drop_id     UUID REFERENCES drops(id),
  accuracy    REAL,
  unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, drop_id)
);
CREATE INDEX unlocks_drop_idx ON unlocks (drop_id);

CREATE TABLE reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES users(id),
  target_type TEXT NOT NULL CHECK (target_type IN ('drop', 'echo', 'user')),
  target_id   UUID NOT NULL,
  reason      TEXT,
  resolved_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE blocks (
  blocker_id UUID REFERENCES users(id),
  blocked_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE exclusion_zones (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  geo  GEOGRAPHY(Polygon) NOT NULL
);
CREATE INDEX exclusion_geo_idx ON exclusion_zones USING GIST (geo);
