-- Clears the dummy workout data and the hand-seeded starter catalog, so the
-- free-exercise-db import (005) lands in a clean database.
--
-- Does NOT touch auth.users — your login survives. Only workout content goes.
--
-- Run AFTER 003 (this depends on the external_id column it adds).
--
-- DESTRUCTIVE: every logged session, exercise and set is deleted. Only run
-- this while the data is still throwaway.

BEGIN;

-- Workout logs, child table first to respect the foreign keys.
DELETE FROM exercise_sets;
DELETE FROM workout_exercises;
DELETE FROM workout_sessions;

-- The hand-seeded starter exercises. Imported rows carry an external_id, so
-- restricting to NULL targets only the pre-import catalog and leaves anything
-- from 005 alone (whichever order the two are run in).
DELETE FROM exercise_catalog WHERE external_id IS NULL;

COMMIT;

-- Expect: 0, 0, 0, 0
SELECT
  (SELECT count(*) FROM exercise_sets)                                AS sets,
  (SELECT count(*) FROM workout_exercises)                            AS exercises,
  (SELECT count(*) FROM workout_sessions)                             AS sessions,
  (SELECT count(*) FROM exercise_catalog WHERE external_id IS NULL)   AS old_catalog;
