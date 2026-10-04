-- F-08: creators may reveal the exact rule on the map.
ALTER TABLE drops ADD COLUMN conditions_revealed BOOLEAN NOT NULL DEFAULT false;
-- F-09: set once the "capsule opened" push has gone out.
ALTER TABLE drops ADD COLUMN capsule_notified_at TIMESTAMPTZ;
CREATE INDEX drops_capsule_due_idx ON drops (unlock_at) WHERE unlock_at IS NOT NULL AND capsule_notified_at IS NULL;

CREATE TABLE devices (
  token      TEXT PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform   TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX devices_user_idx ON devices (user_id);
