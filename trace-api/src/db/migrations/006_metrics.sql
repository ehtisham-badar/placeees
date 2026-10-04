-- §11 pilot metrics: product events from the app.
CREATE TABLE app_events (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  props       JSONB,
  at          TIMESTAMPTZ NOT NULL,          -- when it happened on the device
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX app_events_name_at_idx ON app_events (name, at);
CREATE INDEX app_events_user_at_idx ON app_events (user_id, at);
