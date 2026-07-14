-- Replaces the exercise catalog with the curated list in
-- liftr_exercise_catalog.csv (117 exercises), and clears all workout data.
--
-- IMPORTANT -- the "category" column CHANGES MEANING HERE.
--   Was: a body part (chest / back / legs / shoulders / arms / core / cardio).
--   Now: a movement pattern (push / pull / legs / core).
-- Body part now lives in "muscle_group" (chest, back, quads, biceps, ...), which
-- is what the app keys its icons off. Migration 003's note on "category" is
-- superseded by this one.
--
-- DESTRUCTIVE: every logged session, exercise and set is deleted, along with the
-- entire old catalog. Does NOT touch auth.users -- your login survives.
-- Superseded by 008, which adds to the catalog instead of replacing it.
--
-- Generated from liftr_exercise_catalog.csv by scripts/gen_catalog_migration.py.
-- Edit the CSV and re-run that; don't hand-edit this file.
--
-- Safe to re-run.

BEGIN;

-- Compound (multi-joint) vs isolation.
ALTER TABLE exercise_catalog
  ADD COLUMN IF NOT EXISTS is_compound boolean;

-- The RLS policy on this table only exposes shared rows (is_global = true) plus
-- your own (created_by). An INSERT leaving is_global NULL writes rows that are
-- invisible to everyone, including you: the catalog reads back empty and the
-- picker has nothing to offer. The INSERT below sets it; this default means
-- forgetting it can never cause that again.
ALTER TABLE exercise_catalog
  ALTER COLUMN is_global SET DEFAULT true;

-- name_key is the generated, normalized name (lowercased, whitespace collapsed)
-- from 003, so "Bench Press" and "  bench   press " collide. The unique index is
-- what makes the insert below idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS exercise_catalog_name_key_uniq
  ON exercise_catalog (name_key);

-- Widen the CHECK constraints before inserting, or new vocabulary is rejected
-- with a 23514. (The original schema allowed only body parts in `category`;
-- "push" violates it.)
--
-- Dropping by name is not enough: the checks on muscle_group and equipment may
-- be named differently and would fail the same way, one error at a time. This
-- finds every check constraint touching the three columns whose vocabulary is
-- changing, and drops exactly those.
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT con.conname
    FROM pg_constraint con
    WHERE con.conrelid = 'exercise_catalog'::regclass
      AND con.contype = 'c'
      AND EXISTS (
        SELECT 1
        FROM unnest(con.conkey) AS key(attnum)
        JOIN pg_attribute att
          ON att.attrelid = con.conrelid
         AND att.attnum = key.attnum
        WHERE att.attname IN ('category', 'muscle_group', 'equipment')
      )
  LOOP
    EXECUTE format('ALTER TABLE exercise_catalog DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

-- These lists are generated from the CSV, so a new muscle group or equipment
-- type can never fail the insert with a constraint violation. The vocabulary is
-- a superset of what's already in the table, so re-adding them validates the
-- existing rows without complaint.
--
-- NULL stays legal on purpose: a user-created exercise may not know its movement
-- pattern, and a CHECK forbidding that would block free-text entry later.
ALTER TABLE exercise_catalog
  ADD CONSTRAINT exercise_catalog_category_check
    CHECK (category IS NULL OR category IN (
      'core', 'legs', 'pull', 'push'
    )),

  ADD CONSTRAINT exercise_catalog_muscle_group_check
    CHECK (muscle_group IS NULL OR muscle_group IN (
      'abs', 'back', 'biceps', 'calves', 'chest', 'glutes', 'hamstrings',
      'lower_back', 'quads', 'shoulders', 'triceps'
    )),

  ADD CONSTRAINT exercise_catalog_equipment_check
    CHECK (equipment IS NULL OR equipment IN (
      'barbell', 'bodyweight', 'cable', 'dumbbell', 'machine'
    ));

-- Drop the free-exercise-db columns that 003 added. That catalog is gone, so
-- nothing writes these and the app no longer reads them.
--
-- NOTE: this makes migrations 003 and 005 non-re-runnable, which is fine -- they
-- describe a catalog this one replaces.
ALTER TABLE exercise_catalog
  DROP COLUMN IF EXISTS external_id,
  DROP COLUMN IF EXISTS exercise_type,
  DROP COLUMN IF EXISTS level,
  DROP COLUMN IF EXISTS force,
  DROP COLUMN IF EXISTS mechanic,
  DROP COLUMN IF EXISTS primary_muscles,
  DROP COLUMN IF EXISTS secondary_muscles,
  DROP COLUMN IF EXISTS instructions,
  DROP COLUMN IF EXISTS image_paths;

-- Workout logs, child table first to respect the foreign keys.
DELETE FROM exercise_sets;
DELETE FROM workout_exercises;
DELETE FROM workout_sessions;

-- workout_exercises is empty by now, so nothing references these.
DELETE FROM exercise_catalog;

-- Keyed on the normalized name: new exercises are inserted, ones already present
-- have their metadata refreshed from the CSV. catalog_id and created_at are left
-- alone, so anything already logged against a row keeps pointing at it.
INSERT INTO exercise_catalog
  (name, category, muscle_group, equipment, is_compound, is_global)
VALUES
  ('Barbell Bench Press', 'push', 'chest', 'barbell', true, true),
  ('Incline Barbell Bench Press', 'push', 'chest', 'barbell', true, true),
  ('Decline Barbell Bench Press', 'push', 'chest', 'barbell', true, true),
  ('Dumbbell Bench Press', 'push', 'chest', 'dumbbell', true, true),
  ('Incline Dumbbell Bench Press', 'push', 'chest', 'dumbbell', true, true),
  ('Decline Dumbbell Bench Press', 'push', 'chest', 'dumbbell', true, true),
  ('Dumbbell Fly', 'push', 'chest', 'dumbbell', false, true),
  ('Incline Dumbbell Fly', 'push', 'chest', 'dumbbell', false, true),
  ('Chest Press Machine', 'push', 'chest', 'machine', false, true),
  ('Incline Chest Press Machine', 'push', 'chest', 'machine', false, true),
  ('Pec Deck', 'push', 'chest', 'machine', false, true),
  ('Cable Fly', 'push', 'chest', 'cable', false, true),
  ('High to Low Cable Fly', 'push', 'chest', 'cable', false, true),
  ('Low to High Cable Fly', 'push', 'chest', 'cable', false, true),
  ('Cable Crossover', 'push', 'chest', 'cable', false, true),
  ('Dips', 'push', 'chest', 'bodyweight', true, true),
  ('Push Up', 'push', 'chest', 'bodyweight', true, true),
  ('Overhead Barbell Press', 'push', 'shoulders', 'barbell', true, true),
  ('Seated Barbell Press', 'push', 'shoulders', 'barbell', true, true),
  ('Overhead Dumbbell Press', 'push', 'shoulders', 'dumbbell', true, true),
  ('Seated Dumbbell Press', 'push', 'shoulders', 'dumbbell', true, true),
  ('Arnold Press', 'push', 'shoulders', 'dumbbell', true, true),
  ('Shoulder Press Machine', 'push', 'shoulders', 'machine', true, true),
  ('Viking Press', 'push', 'shoulders', 'machine', true, true),
  ('Dumbbell Lateral Raise', 'push', 'shoulders', 'dumbbell', false, true),
  ('Cable Lateral Raise', 'push', 'shoulders', 'cable', false, true),
  ('Lateral Raise Machine', 'push', 'shoulders', 'machine', false, true),
  ('Dumbbell Front Raise', 'push', 'shoulders', 'dumbbell', false, true),
  ('Cable Front Raise', 'push', 'shoulders', 'cable', false, true),
  ('Rear Delt Fly', 'push', 'shoulders', 'dumbbell', false, true),
  ('Rear Delt Machine', 'push', 'shoulders', 'machine', false, true),
  ('Face Pull', 'pull', 'shoulders', 'cable', false, true),
  ('Cable Reverse Fly', 'pull', 'shoulders', 'cable', false, true),
  ('Barbell Row', 'pull', 'back', 'barbell', true, true),
  ('Pendlay Row', 'pull', 'back', 'barbell', true, true),
  ('T-Bar Row', 'pull', 'back', 'barbell', true, true),
  ('Dumbbell Row', 'pull', 'back', 'dumbbell', true, true),
  ('Chest-Supported Dumbbell Row', 'pull', 'back', 'dumbbell', true, true),
  ('Seated Cable Row', 'pull', 'back', 'cable', true, true),
  ('Cable Row Wide Grip', 'pull', 'back', 'cable', true, true),
  ('Chest-Supported Row Machine', 'pull', 'back', 'machine', true, true),
  ('Iso-Lateral Row Machine', 'pull', 'back', 'machine', true, true),
  ('Lat Pulldown', 'pull', 'back', 'cable', true, true),
  ('Wide Grip Lat Pulldown', 'pull', 'back', 'cable', true, true),
  ('Close Grip Lat Pulldown', 'pull', 'back', 'cable', true, true),
  ('Reverse Grip Lat Pulldown', 'pull', 'back', 'cable', true, true),
  ('Straight Arm Pulldown', 'pull', 'back', 'cable', false, true),
  ('Pull Up', 'pull', 'back', 'bodyweight', true, true),
  ('Chin Up', 'pull', 'back', 'bodyweight', true, true),
  ('Assisted Pull Up Machine', 'pull', 'back', 'machine', true, true),
  ('Pullover Machine', 'pull', 'back', 'machine', false, true),
  ('Deadlift', 'pull', 'back', 'barbell', true, true),
  ('Sumo Deadlift', 'pull', 'back', 'barbell', true, true),
  ('Rack Pull', 'pull', 'back', 'barbell', true, true),
  ('Shrug', 'pull', 'back', 'barbell', false, true),
  ('Dumbbell Shrug', 'pull', 'back', 'dumbbell', false, true),
  ('Barbell Curl', 'pull', 'biceps', 'barbell', false, true),
  ('EZ Bar Curl', 'pull', 'biceps', 'barbell', false, true),
  ('Dumbbell Curl', 'pull', 'biceps', 'dumbbell', false, true),
  ('Incline Dumbbell Curl', 'pull', 'biceps', 'dumbbell', false, true),
  ('Hammer Curl', 'pull', 'biceps', 'dumbbell', false, true),
  ('Preacher Curl', 'pull', 'biceps', 'barbell', false, true),
  ('Machine Preacher Curl', 'pull', 'biceps', 'machine', false, true),
  ('Biceps Curl Machine', 'pull', 'biceps', 'machine', false, true),
  ('Cable Curl', 'pull', 'biceps', 'cable', false, true),
  ('Cable Hammer Curl', 'pull', 'biceps', 'cable', false, true),
  ('Concentration Curl', 'pull', 'biceps', 'dumbbell', false, true),
  ('Close Grip Bench Press', 'push', 'triceps', 'barbell', true, true),
  ('Skull Crusher', 'push', 'triceps', 'barbell', false, true),
  ('Overhead Triceps Extension', 'push', 'triceps', 'dumbbell', false, true),
  ('Cable Triceps Pushdown', 'push', 'triceps', 'cable', false, true),
  ('Cable Rope Pushdown', 'push', 'triceps', 'cable', false, true),
  ('Cable Overhead Extension', 'push', 'triceps', 'cable', false, true),
  ('Triceps Extension Machine', 'push', 'triceps', 'machine', false, true),
  ('Dips for Triceps', 'push', 'triceps', 'bodyweight', true, true),
  ('Triceps Kickback', 'push', 'triceps', 'dumbbell', false, true),
  ('Back Squat', 'legs', 'quads', 'barbell', true, true),
  ('Front Squat', 'legs', 'quads', 'barbell', true, true),
  ('High Bar Squat', 'legs', 'quads', 'barbell', true, true),
  ('Low Bar Squat', 'legs', 'quads', 'barbell', true, true),
  ('Bulgarian Split Squat', 'legs', 'quads', 'dumbbell', true, true),
  ('Dumbbell Lunge', 'legs', 'quads', 'dumbbell', true, true),
  ('Walking Lunge', 'legs', 'quads', 'dumbbell', true, true),
  ('Hack Squat', 'legs', 'quads', 'machine', true, true),
  ('Leg Press', 'legs', 'quads', 'machine', true, true),
  ('Pendulum Squat', 'legs', 'quads', 'machine', true, true),
  ('Leg Extension', 'legs', 'quads', 'machine', false, true),
  ('Sissy Squat', 'legs', 'quads', 'bodyweight', false, true),
  ('Romanian Deadlift', 'legs', 'hamstrings', 'barbell', true, true),
  ('Dumbbell Romanian Deadlift', 'legs', 'hamstrings', 'dumbbell', true, true),
  ('Stiff Leg Deadlift', 'legs', 'hamstrings', 'barbell', true, true),
  ('Lying Leg Curl', 'legs', 'hamstrings', 'machine', false, true),
  ('Seated Leg Curl', 'legs', 'hamstrings', 'machine', false, true),
  ('Nordic Curl', 'legs', 'hamstrings', 'bodyweight', false, true),
  ('Good Morning', 'legs', 'hamstrings', 'barbell', true, true),
  ('Barbell Hip Thrust', 'legs', 'glutes', 'barbell', true, true),
  ('Dumbbell Hip Thrust', 'legs', 'glutes', 'dumbbell', true, true),
  ('Hip Thrust Machine', 'legs', 'glutes', 'machine', true, true),
  ('Glute Bridge', 'legs', 'glutes', 'bodyweight', false, true),
  ('Cable Kickback', 'legs', 'glutes', 'cable', false, true),
  ('Kickback Machine', 'legs', 'glutes', 'machine', false, true),
  ('Hip Abduction Machine', 'legs', 'glutes', 'machine', false, true),
  ('Hip Adduction Machine', 'legs', 'glutes', 'machine', false, true),
  ('Standing Calf Raise', 'legs', 'calves', 'machine', false, true),
  ('Seated Calf Raise', 'legs', 'calves', 'machine', false, true),
  ('Leg Press Calf Raise', 'legs', 'calves', 'machine', false, true),
  ('Plank', 'core', 'abs', 'bodyweight', false, true),
  ('Side Plank', 'core', 'abs', 'bodyweight', false, true),
  ('Hanging Leg Raise', 'core', 'abs', 'bodyweight', false, true),
  ('Cable Crunch', 'core', 'abs', 'cable', false, true),
  ('Ab Crunch Machine', 'core', 'abs', 'machine', false, true),
  ('Roman Chair Sit Up', 'core', 'abs', 'bodyweight', false, true),
  ('Ab Wheel Rollout', 'core', 'abs', 'bodyweight', false, true),
  ('Russian Twist', 'core', 'abs', 'bodyweight', false, true),
  ('Cable Woodchopper', 'core', 'abs', 'cable', false, true),
  ('Back Extension', 'core', 'lower_back', 'bodyweight', false, true),
  ('Reverse Hyperextension', 'core', 'lower_back', 'machine', false, true);

COMMIT;

-- Expect at least 117 exercises, all visible.
SELECT
  count(*)                                   AS catalog,
  count(*) FILTER (WHERE is_global IS TRUE)  AS visible
FROM exercise_catalog;

SELECT muscle_group, count(*)
FROM exercise_catalog
GROUP BY 1
ORDER BY 2 DESC;
