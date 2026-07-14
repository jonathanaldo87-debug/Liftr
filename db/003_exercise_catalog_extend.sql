-- Extends exercise_catalog to carry the free-exercise-db fields.
--
-- Note on `category`: this column keeps its EXISTING meaning in this app —
-- a body-part bucket (chest / back / legs / shoulders / arms / core / cardio),
-- which the UI groups and picks emoji by. free-exercise-db's own "category"
-- field means something different (strength / stretching / plyometrics / ...),
-- so it is imported into the new `exercise_type` column instead of clobbering
-- this one.
--
-- Safe to re-run.

ALTER TABLE exercise_catalog
  ADD COLUMN IF NOT EXISTS external_id       text,        -- free-exercise-db id; makes re-import idempotent
  ADD COLUMN IF NOT EXISTS exercise_type     text,        -- strength | stretching | plyometrics | powerlifting | olympic weightlifting | strongman | cardio
  ADD COLUMN IF NOT EXISTS equipment         text,        -- barbell | dumbbell | machine | cable | body only | ...
  ADD COLUMN IF NOT EXISTS level             text,        -- beginner | intermediate | expert
  ADD COLUMN IF NOT EXISTS force             text,        -- push | pull | static
  ADD COLUMN IF NOT EXISTS mechanic          text,        -- compound | isolation
  ADD COLUMN IF NOT EXISTS primary_muscles   text[],
  ADD COLUMN IF NOT EXISTS secondary_muscles text[],
  ADD COLUMN IF NOT EXISTS instructions      text[],
  ADD COLUMN IF NOT EXISTS image_paths       text[];      -- relative, e.g. {Bench_Press/0.jpg}; app prefixes a base URL

-- One row per source exercise: lets the import re-run without duplicating.
CREATE UNIQUE INDEX IF NOT EXISTS exercise_catalog_external_id_key
  ON exercise_catalog (external_id)
  WHERE external_id IS NOT NULL;

-- Normalized name key: makes "  bench   press " and "Bench Press" collide,
-- which is what lets free-text entry safely get-or-create.
ALTER TABLE exercise_catalog
  ADD COLUMN IF NOT EXISTS name_key text
  GENERATED ALWAYS AS (lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))) STORED;

-- Search: the picker filters by name across ~900 rows.
CREATE INDEX IF NOT EXISTS exercise_catalog_name_key_idx
  ON exercise_catalog (name_key);

CREATE INDEX IF NOT EXISTS exercise_catalog_category_idx
  ON exercise_catalog (category);
