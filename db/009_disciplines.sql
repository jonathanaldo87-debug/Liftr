-- Adds disciplines (gym / running / ...) as a first-class concept.
--
-- Liftr is becoming a general exercise app rather than a gym-only logger. A
-- discipline is reference data in its own table, not an enum or a CHECK list,
-- specifically so adding swimming or cycling later is one INSERT -- no schema
-- change, no app release, no migration.
--
-- Shape: a skinny shared parent (workout_sessions) that now carries a
-- discipline, with typed children hanging off it. Gym sessions keep their
-- exercise_sets; a future running session gets its own child table. The parent
-- stays free of per-discipline nullable columns.
--
-- ADDITIVE: deletes nothing. Existing sessions default to 'gym', so every
-- workout already logged keeps working untouched.
--
-- Safe to re-run.

BEGIN;

-- ── The catalog of disciplines ──────────────────────────────────────────────
-- Keyed by a stable text slug rather than a uuid: it's a natural key, it makes
-- workout_sessions.discipline readable in raw queries, and the app can hardcode
-- 'gym' without a lookup.
CREATE TABLE IF NOT EXISTS disciplines (
  discipline_key text PRIMARY KEY,
  label          text        NOT NULL,
  emoji          text        NOT NULL,
  -- The one-line blurb under the label on the onboarding card. Lives here, not
  -- in Dart, so a new discipline brings its own copy with it.
  description    text        NOT NULL DEFAULT '',
  -- Controls the order of the onboarding cards and the home chips.
  sort_order     int         NOT NULL DEFAULT 0,
  -- Lets a discipline be added to the table before its logging UI exists --
  -- seed it inactive, flip to true on the release that can handle it.
  is_active      boolean     NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- Re-runnable on a table that predates the description column.
ALTER TABLE disciplines
  ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '';

-- Emoji go in as Postgres unicode escapes, not literal characters, so this file
-- stays pure ASCII. Pasted as raw UTF-8 they get mangled by any client that
-- decodes them as Windows-1252 -- which is exactly what happened on the first
-- run of this migration and needed 011 to repair. Add future emoji the same way.
--   U&'\+01F3CB' = barbell, U&'\+00FE0F' = emoji variation selector,
--   U&'\+01F3C3' = runner.
INSERT INTO disciplines
  (discipline_key, label, emoji, description, sort_order, is_active)
VALUES
  ('gym',     'Gym',     U&'\+01F3CB\+00FE0F', 'Weights & machines', 1, true),
  ('running', 'Running', U&'\+01F3C3',         'Distance & pace',    2, true)
ON CONFLICT (discipline_key) DO UPDATE SET
  label       = excluded.label,
  emoji       = excluded.emoji,
  description = excluded.description,
  sort_order  = excluded.sort_order,
  is_active   = excluded.is_active;

-- Shared reference data, same as exercise_catalog: everyone reads it, nobody
-- writes it from the client. Without RLS enabled the table would be wide open.
ALTER TABLE disciplines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS disciplines_read_all ON disciplines;
CREATE POLICY disciplines_read_all
  ON disciplines FOR SELECT
  USING (true);
-- No insert/update/delete policy on purpose: with RLS on, writes are denied to
-- anon and authenticated by default. Seed new disciplines via migration.

-- ── Sessions gain a discipline ──────────────────────────────────────────────
-- Defaulting to 'gym' is what makes this safe for the rows already in the table.
ALTER TABLE workout_sessions
  ADD COLUMN IF NOT EXISTS discipline text NOT NULL DEFAULT 'gym';

-- Backfill defensively in case the column existed but held NULLs.
UPDATE workout_sessions SET discipline = 'gym' WHERE discipline IS NULL;

-- The FK is what turns "add a row to disciplines" into a real new discipline,
-- and stops a typo'd session discipline from ever landing.
ALTER TABLE workout_sessions
  DROP CONSTRAINT IF EXISTS workout_sessions_discipline_fkey;
ALTER TABLE workout_sessions
  ADD CONSTRAINT workout_sessions_discipline_fkey
  FOREIGN KEY (discipline) REFERENCES disciplines (discipline_key);

-- ── One session per day, PER DISCIPLINE ─────────────────────────────────────
-- 006 enforced UNIQUE (user_id, session_date) -- one session per day, full stop.
-- That was right when gym was the only thing here, but it now blocks doing a gym
-- workout AND a run on the same day: the second insert would fail. Widening the
-- index is what makes multi-discipline days possible at all.
DROP INDEX IF EXISTS workout_sessions_user_date_key;

CREATE UNIQUE INDEX IF NOT EXISTS workout_sessions_user_date_discipline_key
  ON workout_sessions (user_id, session_date, discipline);

CREATE INDEX IF NOT EXISTS workout_sessions_discipline_idx
  ON workout_sessions (discipline);

COMMIT;

-- Expect: 2 disciplines, and every existing session tagged 'gym'.
SELECT discipline_key, label, emoji, description, sort_order, is_active
FROM disciplines
ORDER BY sort_order;

SELECT discipline, count(*) AS sessions
FROM workout_sessions
GROUP BY 1
ORDER BY 1;
