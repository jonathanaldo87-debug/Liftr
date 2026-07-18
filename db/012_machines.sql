-- Machines: the physical stations you train on, and how you set them up.
--
-- Why this exists: two cable machines in the same gym can move in different
-- increments -- one in 2.5 kg steps, one in 5 kg. Which one you use is decided
-- by whichever is free, not by choice. Without recording which station a set
-- happened on, the logged weights are a blend of two incompatible scales, and
-- any suggestion built on them is wrong on at least one of the machines.
--
-- SHAPE -- two tables, because two different things are being modelled:
--
--   user_machines             the physical station. A cable stack is ONE thing
--                             you do curls, pushdowns, face pulls and rows on,
--                             so it is deliberately NOT scoped to an exercise.
--                             Register it once, use it everywhere.
--
--   machine_exercise_settings how you set that station up for ONE exercise.
--                             Seat height for a cable row and a cable curl
--                             differ on the same stack, so this is keyed by the
--                             (machine, exercise) pair rather than by either
--                             one alone.
--
-- The weight increment lives on the station because that is where it physically
-- lives. The seat height lives on the pair because that is where it physically
-- lives. Neither is a property of the exercise in the abstract, which is why
-- neither belongs on exercise_catalog -- that table is global shared reference
-- data (see 009), read-only from the client, and identical for every user.
--
-- ADDITIVE: deletes nothing, and requires nothing. workout_exercises.machine_id
-- is nullable and stays NULL until you actually distinguish a station. NULL
-- honestly means "unspecified", which is exactly what every row logged before
-- today is. Backfilling a guess would attribute history to a station you may
-- not have used -- false precision is worse here than an honest gap.
--
-- Safe to re-run.

BEGIN;

-- ── The physical station ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_machines (
  machine_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid        NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,

  -- Whatever you call it out loud: "5 kg cable", "the one by the window".
  -- Free text on purpose -- the useful name is the one that helps you tell two
  -- machines apart while standing between them, which no vocabulary we invent
  -- can predict.
  label               text        NOT NULL,

  -- The stack's step. NULL means "not known yet", NOT "no increment": the app
  -- infers it from your logged weights and only stores a value here once you
  -- confirm or correct it. Kept out of the app's fallback chain when NULL so an
  -- unconfirmed guess never hardens into a stored fact.
  weight_increment_kg numeric,

  -- Stacks rarely start at zero. Suggesting 10 kg on a stack whose lightest pin
  -- is 15 is confidently impossible, which costs more trust than saying nothing.
  min_weight_kg       numeric,

  notes               text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- Two machines of yours may not share a name: the label is the only thing
-- telling them apart in the picker, so duplicates would make the choice
-- meaningless. Case- and whitespace-insensitive, matching how exercise_catalog
-- normalises its name_key in 003.
CREATE UNIQUE INDEX IF NOT EXISTS user_machines_user_label_key
  ON user_machines (user_id, lower(btrim(label)));

CREATE INDEX IF NOT EXISTS user_machines_user_idx
  ON user_machines (user_id);

-- ── How you set that station up for one exercise ────────────────────────────
CREATE TABLE IF NOT EXISTS machine_exercise_settings (
  machine_id uuid        NOT NULL REFERENCES user_machines (machine_id) ON DELETE CASCADE,
  catalog_id uuid        NOT NULL REFERENCES exercise_catalog (catalog_id) ON DELETE CASCADE,

  -- {"seat": "4", "back pad": "2"} -- free key/value rather than columns.
  -- The vocabulary differs for every machine (seat, pin, lever arm, foot
  -- plate, ...), so columns would mean a migration per machine type forever.
  -- Renders as chips without needing to know what the keys mean.
  settings   jsonb       NOT NULL DEFAULT '{}',

  -- The escape hatch for anything that isn't a key/value.
  notes      text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (machine_id, catalog_id)
);

-- ── Usage: which station a logged exercise happened on ──────────────────────
-- On workout_exercises rather than exercise_sets: you don't change machines
-- mid-exercise, so this is one write per exercise instead of one per set, and
-- getWorkoutExercises already joins catalog detail here -- the machine joins the
-- same way, with no new query shape.
ALTER TABLE workout_exercises
  ADD COLUMN IF NOT EXISTS machine_id uuid REFERENCES user_machines (machine_id) ON DELETE SET NULL;

-- ON DELETE SET NULL, not CASCADE: deleting a machine you no longer train on
-- must never delete the workouts you did on it. The history survives, it just
-- goes back to "unspecified".

-- "Which machines have I used for this exercise?" -- the picker's whole query.
CREATE INDEX IF NOT EXISTS workout_exercises_machine_idx
  ON workout_exercises (machine_id)
  WHERE machine_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS workout_exercises_catalog_machine_idx
  ON workout_exercises (catalog_id, machine_id);

-- ── Row level security ──────────────────────────────────────────────────────
-- Both tables hold personal data, unlike the shared catalog in 009. Without RLS
-- enabled these would be readable by every authenticated user.
ALTER TABLE user_machines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_machines_own ON user_machines;
CREATE POLICY user_machines_own
  ON user_machines FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

ALTER TABLE machine_exercise_settings ENABLE ROW LEVEL SECURITY;

-- Ownership is inherited through the machine: this table has no user_id of its
-- own because duplicating it would let the two disagree. The subquery is what
-- keeps "my settings" and "my machine" the same answer by construction.
DROP POLICY IF EXISTS machine_exercise_settings_own ON machine_exercise_settings;
CREATE POLICY machine_exercise_settings_own
  ON machine_exercise_settings FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM user_machines m
      WHERE m.machine_id = machine_exercise_settings.machine_id
        AND m.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_machines m
      WHERE m.machine_id = machine_exercise_settings.machine_id
        AND m.user_id = auth.uid()
    )
  );

COMMIT;

-- Expect: both tables empty on a fresh run, and every existing workout_exercise
-- on an unspecified machine -- nothing was backfilled, by design.
SELECT
  (SELECT count(*) FROM user_machines)                                AS machines,
  (SELECT count(*) FROM machine_exercise_settings)                    AS machine_settings,
  (SELECT count(*) FROM workout_exercises WHERE machine_id IS NULL)   AS unspecified,
  (SELECT count(*) FROM workout_exercises WHERE machine_id IS NOT NULL) AS assigned;
