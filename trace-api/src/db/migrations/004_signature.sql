-- F-13 Relay drops: one row per carry. The drop itself moves (drops.geo) when it's dropped.
CREATE TABLE relay_hops (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drop_id     UUID NOT NULL REFERENCES drops(id),
  carrier_id  UUID NOT NULL REFERENCES users(id),
  picked_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  pickup_geo  GEOGRAPHY(Point) NOT NULL,
  deadline_at TIMESTAMPTZ NOT NULL,
  dropped_at  TIMESTAMPTZ,
  dropped_geo GEOGRAPHY(Point),
  note        TEXT CHECK (note IS NULL OR char_length(note) <= 140),
  returned    BOOLEAN NOT NULL DEFAULT false,      -- deadline passed; went back to the pickup point
  warned_at   TIMESTAMPTZ,                         -- "one day left" push sent
  UNIQUE (drop_id, carrier_id)                     -- nobody carries the same relay twice
);
CREATE INDEX relay_hops_drop_idx ON relay_hops (drop_id, picked_at);
CREATE INDEX relay_hops_open_idx ON relay_hops (deadline_at) WHERE dropped_at IS NULL;
CREATE INDEX drops_carrier_idx ON drops (relay_carrier_id) WHERE relay_carrier_id IS NOT NULL;

-- F-14 Then/Now: visitors' present-day photos of a historical spot.
CREATE TABLE now_photos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drop_id    UUID NOT NULL REFERENCES drops(id),
  user_id    UUID NOT NULL REFERENCES users(id),
  media_key  TEXT NOT NULL,
  heading    REAL,
  pitch      REAL,
  status     drop_status NOT NULL DEFAULT 'pending_moderation',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX now_photos_drop_idx ON now_photos (drop_id, created_at);
