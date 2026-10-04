-- F-17: iOS App Attest keys (one per install) and one-time challenges.
CREATE TABLE attest_keys (
  key_id     TEXT PRIMARY KEY,                    -- base64 SHA-256 of the public key
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  public_key TEXT NOT NULL,                       -- SPKI PEM
  counter    BIGINT NOT NULL DEFAULT 0,
  env        TEXT NOT NULL CHECK (env IN ('development', 'production')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX attest_keys_user_idx ON attest_keys (user_id);

CREATE TABLE attest_challenges (
  challenge  TEXT PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL
);

-- Everything suspicious, for review and for risk decisions.
CREATE TABLE integrity_events (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,       -- mock_location | impossible_travel | attest_failed | integrity_failed | rate_limited
  detail     JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX integrity_events_user_idx ON integrity_events (user_id, created_at DESC);

-- F-16: venue codes printed as QR posters / written to NFC tags.
CREATE TABLE venues (
  code       TEXT PRIMARY KEY,
  drop_id    UUID NOT NULL REFERENCES drops(id),
  name       TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- F-05: who moderated what.
ALTER TABLE drops ADD COLUMN moderated_at TIMESTAMPTZ;
ALTER TABLE reports ADD COLUMN resolution TEXT;
