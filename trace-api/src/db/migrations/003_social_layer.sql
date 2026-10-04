-- F-12 Circles
CREATE TABLE circles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    UUID NOT NULL REFERENCES users(id),
  name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
  invite_code TEXT UNIQUE NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE circle_members (
  circle_id UUID REFERENCES circles(id) ON DELETE CASCADE,
  user_id   UUID REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (circle_id, user_id)
);
CREATE INDEX circle_members_user_idx ON circle_members (user_id);

ALTER TABLE drops ADD CONSTRAINT drops_circle_fk FOREIGN KEY (circle_id) REFERENCES circles(id);

-- F-10 Trails
CREATE TABLE trails (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES users(id),
  title      TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- `clue` on stop N leads to stop N; it is revealed once stop N-1 is unlocked (stop 1's from the start).
CREATE TABLE trail_stops (
  trail_id UUID REFERENCES trails(id) ON DELETE CASCADE,
  drop_id  UUID NOT NULL UNIQUE REFERENCES drops(id),   -- a drop belongs to at most one trail
  seq      INT NOT NULL CHECK (seq >= 1),
  clue     TEXT CHECK (clue IS NULL OR char_length(clue) <= 200),
  PRIMARY KEY (trail_id, seq)
);

CREATE TABLE trail_completions (
  user_id      UUID REFERENCES users(id) ON DELETE CASCADE,
  trail_id     UUID REFERENCES trails(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, trail_id)
);

-- F-11 Echoes
CREATE TABLE echoes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drop_id         UUID NOT NULL REFERENCES drops(id),
  user_id         UUID NOT NULL REFERENCES users(id),
  body            TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 280),
  status          drop_status NOT NULL DEFAULT 'pending_moderation',
  moderation_note TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX echoes_drop_idx ON echoes (drop_id, created_at);
CREATE INDEX echoes_user_day_idx ON echoes (user_id, created_at);
