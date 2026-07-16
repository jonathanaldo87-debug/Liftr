-- One active session at a time.
--
-- You start a session to say what you're doing right now; you can't start a run
-- while a gym session is still open. "Active" is deliberately a flag, not a pair
-- of timestamps -- nothing here times you, and start/end times were explicitly
-- not wanted. The flag answers one question only: which session am I on?
--
-- ADDITIVE: deletes nothing.
--
-- Every session that already exists is marked ENDED (is_active = false) rather
-- than active. Backfilling them as active would be wrong twice over: they're
-- historical, and more than one per user would instantly violate the index
-- below.
--
-- Safe to re-run.

BEGIN;

ALTER TABLE workout_sessions
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT false;

-- The invariant, enforced by the database rather than by app logic.
--
-- A partial unique index on user_id, restricted to active rows: a user may hold
-- at most one active session, while any number of ended ones coexist. Doing this
-- in Dart alone would leave a race between "check for active" and "insert" that
-- a double-tap could slip through -- this makes that insert fail instead.
CREATE UNIQUE INDEX IF NOT EXISTS workout_sessions_one_active_per_user
  ON workout_sessions (user_id)
  WHERE is_active;

-- Finding "my active session" is on the hot path of every home screen load.
CREATE INDEX IF NOT EXISTS workout_sessions_active_idx
  ON workout_sessions (user_id, is_active)
  WHERE is_active;

COMMIT;

-- Expect: every existing session ended, and no user holding more than one
-- active session (the index guarantees the second number can never exceed 1).
SELECT
  count(*) FILTER (WHERE is_active)       AS active,
  count(*) FILTER (WHERE NOT is_active)   AS ended,
  count(*)                                AS total
FROM workout_sessions;
