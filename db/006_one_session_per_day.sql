-- One workout session per user per day.
--
-- The app used to create a NEW session every time you added an exercise, so a
-- day with two exercises ended up with two sessions pointing at the same date.
-- That also broke the home screen: it reads the day's session with .maybeSingle(),
-- which errors when it finds more than one row.
--
-- This merges any duplicates that already exist (keeping the oldest session and
-- re-pointing its exercises at it), then adds the unique index that stops them
-- coming back. The app fix alone isn't enough — without the constraint, any
-- future bug or a double-tap race can reintroduce the duplicate.
--
-- Small enough to paste into the Supabase SQL editor. Safe to re-run.

BEGIN;

-- Oldest session for each (user, date) wins; everything else is a duplicate.
CREATE TEMP TABLE session_merge ON COMMIT DROP AS
SELECT
  session_id,
  first_value(session_id) OVER (
    PARTITION BY user_id, session_date
    ORDER BY created_at, session_id
  ) AS keep_id
FROM workout_sessions;

-- Move the orphaned exercises onto the surviving session.
UPDATE workout_exercises we
SET session_id = m.keep_id
FROM session_merge m
WHERE we.session_id = m.session_id
  AND m.session_id <> m.keep_id;

DELETE FROM workout_sessions ws
USING session_merge m
WHERE ws.session_id = m.session_id
  AND m.session_id <> m.keep_id;

CREATE UNIQUE INDEX IF NOT EXISTS workout_sessions_user_date_key
  ON workout_sessions (user_id, session_date);

COMMIT;

-- Expect one row per day, all counts = 1.
SELECT session_date, count(*) AS sessions
FROM workout_sessions
GROUP BY session_date
ORDER BY session_date DESC;
