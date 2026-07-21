-- Drop the legacy one-session-per-DAY index that 009 was meant to replace.
--
-- One-per-day uniqueness predates disciplines and hides under more than one
-- name. There are three ways it can exist on a given database:
--
--   * workout_sessions_user_id_session_date_key -- the auto-named UNIQUE
--     CONSTRAINT from the original CREATE TABLE, there from the very start.
--   * workout_sessions_user_date_key -- the plain UNIQUE INDEX 006 added, and
--     which re-running 006 after 009 resurrects.
--   * any hand-named variant of either.
--
-- 009 was meant to end the one-per-DAY rule and swap in one-per-(day,
-- discipline) so a gym workout and a run can share a day, but it only dropped
-- the 006 index by name -- the original table constraint was never touched, so
-- on a fresh-ish database it's still there. While ANY of them exists, starting a
-- run on a day that already has a gym session fails with a duplicate-key error
-- on workout_sessions.
--
-- Rather than chase names, this drops whatever enforces uniqueness on exactly
-- (user_id, session_date) -- constraint or bare index -- and leaves the
-- per-discipline rule as the only one standing.
--
-- ADDITIVE: deletes no rows. One-per-day meant there were never two sessions on
-- a day to merge in the first place. Safe to re-run.

BEGIN;

-- Drop every UNIQUE CONSTRAINT whose columns are exactly {user_id,
-- session_date}, whatever it's named. The discipline-scoped one has three
-- columns, so it can never match here.
DO $$
DECLARE
  con text;
BEGIN
  FOR con IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'workout_sessions'
      AND c.contype = 'u'
      AND (
        SELECT array_agg(a.attname::text ORDER BY a.attname)
        FROM unnest(c.conkey) AS k(attnum)
        JOIN pg_attribute a
          ON a.attrelid = c.conrelid AND a.attnum = k.attnum
      ) = ARRAY['session_date', 'user_id']
  LOOP
    EXECUTE format('ALTER TABLE workout_sessions DROP CONSTRAINT %I', con);
  END LOOP;
END $$;

-- Drop any bare UNIQUE INDEX on the same two columns that isn't backing a
-- constraint (the 006 index, and any re-created copy of it).
DO $$
DECLARE
  idx text;
BEGIN
  FOR idx IN
    SELECT i.relname
    FROM pg_index x
    JOIN pg_class i ON i.oid = x.indexrelid
    JOIN pg_class t ON t.oid = x.indrelid
    WHERE t.relname = 'workout_sessions'
      AND x.indisunique
      AND NOT EXISTS (
        SELECT 1 FROM pg_constraint c WHERE c.conindid = x.indexrelid
      )
      AND (
        SELECT array_agg(a.attname::text ORDER BY a.attname)
        FROM unnest(x.indkey) AS k(attnum)
        JOIN pg_attribute a
          ON a.attrelid = t.oid AND a.attnum = k.attnum
      ) = ARRAY['session_date', 'user_id']
  LOOP
    EXECUTE format('DROP INDEX %I', idx);
  END LOOP;
END $$;

-- The rule that should be enforcing uniqueness now: one session per day PER
-- discipline. IF NOT EXISTS so this sits happily alongside 009 having already
-- created it.
CREATE UNIQUE INDEX IF NOT EXISTS workout_sessions_user_date_discipline_key
  ON workout_sessions (user_id, session_date, discipline);

COMMIT;

-- Every unique index left on the table, with its definition -- constraints show
-- up here too, since each is backed by a unique index. Expect the per-day one to
-- include `discipline`; anything still scoped to only (user_id, session_date) is
-- one that slipped through, so send it over.
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'workout_sessions'
  AND indexdef ILIKE '%UNIQUE%'
ORDER BY indexname;
