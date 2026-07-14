"""Generates a catalog migration from a CSV.

db/liftr_exercise_catalog_v2.csv is the SOURCE OF TRUTH for the exercise
catalog. To add or change exercises, edit that file and re-run this -- don't
hand-edit the generated SQL, and don't delete the CSV (without it there is no
way to produce the next migration).

    # additive: add what's new, refresh what changed, delete nothing
    python scripts/gen_catalog_migration.py upsert \
        db/liftr_exercise_catalog_v2.csv db/009_exercise_catalog_upsert.sql

    # destructive: wipe catalog AND all workout data, then load the CSV
    python scripts/gen_catalog_migration.py replace \
        db/liftr_exercise_catalog_v2.csv db/00X_replace.sql

Two things this handles that hand-written SQL did not:

1. The CHECK constraint lists are derived from the CSV, never typed by hand.
   v2 introduced `forearms`, `neck` and equipment `other`; a hardcoded list
   rejects them with a 23514 at insert time, which is exactly how the first
   attempt at 007 failed.

2. `upsert` mode deletes nothing. `replace` wipes the workout log along with the
   catalog -- that was acceptable while the data was throwaway, and is not once
   real sessions are being logged. Prefer upsert.
"""
import csv
import sys
import textwrap

mode = sys.argv[1] if len(sys.argv) > 1 else 'upsert'
csv_path = sys.argv[2] if len(sys.argv) > 2 else 'db/liftr_exercise_catalog_v2.csv'
out_path = sys.argv[3] if len(sys.argv) > 3 else 'db/008_exercise_catalog_upsert_v2.sql'

if mode not in ('upsert', 'replace'):
    sys.exit(f'unknown mode {mode!r}: expected "upsert" or "replace"')

rows = list(csv.DictReader(open(csv_path, encoding='utf-8-sig')))


def q(s):
    s = (s or '').strip()
    return "'" + s.replace("'", "''") + "'" if s else 'NULL'


def b(s):
    return 'true' if (s or '').strip().lower() == 'true' else 'false'


def allowed(col):
    """The CHECK list for a column, straight from the data."""
    vals = sorted({(r[col] or '').strip() for r in rows if (r[col] or '').strip()})
    body = ', '.join("'" + v + "'" for v in vals)
    return '\n'.join('      ' + line for line in textwrap.wrap(body, 68))


values = ',\n  '.join(
    '({}, {}, {}, {}, {}, true)'.format(
        q(r['name']), q(r['category']), q(r['muscle_group']),
        q(r['equipment']), b(r['is_compound'])
    ) for r in rows
)

# ── Pieces that differ between the two modes ──────────────────────────────────

REPLACE_HEADER = """-- Replaces the exercise catalog with the curated list in
-- {csv} ({n} exercises), and clears all workout data.
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
-- Superseded by 008, which adds to the catalog instead of replacing it."""

UPSERT_HEADER = """-- Brings the exercise catalog up to date with {csv} ({n} exercises).
--
-- ADDITIVE. Unlike 007 this deletes NOTHING -- no sessions, no exercises, no
-- sets, no catalog rows. 007 could wipe the workout log because the data was
-- still throwaway; now that real sessions are being logged, the catalog gets
-- updated in place instead."""

REPLACE_BODY = """
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
"""

CONFLICT_CLAUSE = """
ON CONFLICT (name_key) DO UPDATE SET
  category     = excluded.category,
  muscle_group = excluded.muscle_group,
  equipment    = excluded.equipment,
  is_compound  = excluded.is_compound,
  is_global    = true"""

TEMPLATE = """{header}
--
-- Generated from {csv} by scripts/gen_catalog_migration.py.
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
{cat}
    )),

  ADD CONSTRAINT exercise_catalog_muscle_group_check
    CHECK (muscle_group IS NULL OR muscle_group IN (
{muscle}
    )),

  ADD CONSTRAINT exercise_catalog_equipment_check
    CHECK (equipment IS NULL OR equipment IN (
{equip}
    ));
{body}
-- Keyed on the normalized name: new exercises are inserted, ones already present
-- have their metadata refreshed from the CSV. catalog_id and created_at are left
-- alone, so anything already logged against a row keeps pointing at it.
INSERT INTO exercise_catalog
  (name, category, muscle_group, equipment, is_compound, is_global)
VALUES
  {values}{conflict};

COMMIT;

-- Expect at least {n} exercises, all visible.
SELECT
  count(*)                                   AS catalog,
  count(*) FILTER (WHERE is_global IS TRUE)  AS visible
FROM exercise_catalog;

SELECT muscle_group, count(*)
FROM exercise_catalog
GROUP BY 1
ORDER BY 2 DESC;
"""

sql = TEMPLATE.format(
    header=(REPLACE_HEADER if mode == 'replace' else UPSERT_HEADER).format(
        csv=csv_path, n=len(rows)),
    csv=csv_path,
    n=len(rows),
    values=values,
    conflict='' if mode == 'replace' else CONFLICT_CLAUSE,
    body=REPLACE_BODY if mode == 'replace' else '',
    cat=allowed('category'),
    muscle=allowed('muscle_group'),
    equip=allowed('equipment'),
)

with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(sql)

print(f'wrote {out_path}: mode={mode}, {len(rows)} rows, {len(sql) // 1024} KB')
