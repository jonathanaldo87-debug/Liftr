-- Running: distance intervals as a typed child of workout_sessions.
--
-- 009 set the shape this follows: a skinny shared parent (workout_sessions)
-- carrying a discipline, with a typed child table per discipline. Gym sessions
-- have exercise_sets; running sessions get distance_intervals. The parent stays
-- free of per-discipline nullable columns, which is the whole point of the
-- split -- a run has no reps and a bench press has no pace.
--
-- NOTE -- the 'running' discipline ROW ALREADY EXISTS. 009 seeded it, active,
-- alongside gym. What was missing was never the row; it was a child table to
-- log into and a way for the app to know which UI to open. This adds both.
--
-- ADDITIVE: deletes nothing.
--
-- Safe to re-run.

BEGIN;

-- ── How a discipline is logged ──────────────────────────────────────────────
-- Lets the app pick a logging UI without switching on discipline_key. That
-- matters because 009's whole premise is that adding swimming should be an
-- INSERT rather than a release -- and a hardcoded `if (key == 'running')` in the
-- app quietly takes that promise away. A new discipline that logs distance
-- declares logging_type = 'distance' and gets the running UI for free.
--
-- 'none' is the honest default: a discipline seeded before its UI exists can be
-- logged as a session but has nothing to log into it yet.
ALTER TABLE disciplines
  ADD COLUMN IF NOT EXISTS logging_type text NOT NULL DEFAULT 'none';

UPDATE disciplines SET logging_type = 'sets'     WHERE discipline_key = 'gym';
UPDATE disciplines SET logging_type = 'distance' WHERE discipline_key = 'running';

ALTER TABLE disciplines
  DROP CONSTRAINT IF EXISTS disciplines_logging_type_check;
ALTER TABLE disciplines
  ADD CONSTRAINT disciplines_logging_type_check
  CHECK (logging_type IN ('none', 'sets', 'distance'));

-- ── One leg of a run ────────────────────────────────────────────────────────
-- A session holds one or more intervals. "Go again" after finishing 1 km adds a
-- second row rather than starting a second session -- which also sidesteps 009's
-- unique index on (user_id, session_date, discipline): a second run on the same
-- day is another interval on the same session, not a session the database would
-- refuse to create.
CREATE TABLE IF NOT EXISTS distance_intervals (
  interval_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id             uuid NOT NULL REFERENCES workout_sessions (session_id) ON DELETE CASCADE,

  -- What you set out to run. NULL means a free run -- you went until you
  -- stopped, and there was no target to fall short of. Distinct from 0, which
  -- would be a target you instantly met.
  target_distance_meters numeric,

  -- What you actually covered. Numeric rather than integer because it is
  -- accumulated from GPS fixes in fractions of a metre; rounding at write time
  -- would bake in a bias across a long run.
  actual_distance_meters numeric      NOT NULL DEFAULT 0,

  duration_seconds       integer      NOT NULL DEFAULT 0,

  -- Typed in after the fact rather than tracked live. Kept because the two are
  -- not equally trustworthy: a manual entry is a human estimate, a tracked one
  -- carries GPS error, and anything comparing them later needs to know which is
  -- which. Also the only way a treadmill run gets in at all.
  logged_manually        boolean      NOT NULL DEFAULT false,

  -- Order within the session. Not derivable from created_at once a manual
  -- interval is backdated into a session that already has live ones.
  sort_order             integer      NOT NULL DEFAULT 1,

  created_at             timestamptz  NOT NULL DEFAULT now(),

  -- Cheap guards against nonsense that would poison any total built on it.
  CONSTRAINT distance_intervals_distance_nonneg
    CHECK (actual_distance_meters >= 0),
  CONSTRAINT distance_intervals_duration_nonneg
    CHECK (duration_seconds >= 0),
  CONSTRAINT distance_intervals_target_positive
    CHECK (target_distance_meters IS NULL OR target_distance_meters > 0)
);

-- Every read is "the intervals of this session, in order".
CREATE INDEX IF NOT EXISTS distance_intervals_session_idx
  ON distance_intervals (session_id, sort_order);

-- ── Row level security ──────────────────────────────────────────────────────
ALTER TABLE distance_intervals ENABLE ROW LEVEL SECURITY;

-- Ownership is inherited through the session rather than duplicated as a
-- user_id column, so "my intervals" and "my session" can never disagree. Same
-- reasoning as machine_exercise_settings in 012.
DROP POLICY IF EXISTS distance_intervals_own ON distance_intervals;
CREATE POLICY distance_intervals_own
  ON distance_intervals FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM workout_sessions s
      WHERE s.session_id = distance_intervals.session_id
        AND s.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM workout_sessions s
      WHERE s.session_id = distance_intervals.session_id
        AND s.user_id = auth.uid()
    )
  );

COMMIT;

-- Expect: gym logs sets, running logs distance, and an empty interval table.
SELECT discipline_key, label, logging_type, is_active
FROM disciplines
ORDER BY sort_order;

SELECT count(*) AS intervals FROM distance_intervals;
