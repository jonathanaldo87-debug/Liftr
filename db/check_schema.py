"""Reports which migrations are actually applied, and prints what it finds.

Exists because run_migration.py executes a file and prints "ok" without ever
showing the verification SELECTs at the bottom of each migration -- so a
migration can appear to have run and still leave you guessing about what landed.

This only reads. It changes nothing.

Usage (PowerShell):
    $env:DATABASE_URL = "postgresql://postgres:PASSWORD@db.PROJECT.supabase.co:5432/postgres"
    python db/check_schema.py
"""

import os
import sys

import psycopg2

url = os.environ.get("DATABASE_URL")
if not url:
    sys.exit("DATABASE_URL is not set. See the usage note at the top of this file.")

conn = psycopg2.connect(url)


def table_exists(cur, table):
    cur.execute(
        "SELECT to_regclass(%s) IS NOT NULL",
        (f"public.{table}",),
    )
    return cur.fetchone()[0]


def column_exists(cur, table, column):
    cur.execute(
        """
        SELECT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = %s
            AND column_name = %s
        )
        """,
        (table, column),
    )
    return cur.fetchone()[0]


def tick(ok):
    return "OK  " if ok else "MISSING"


with conn.cursor() as cur:
    print("\n-- migration 012 (machines) ------------------------------")
    m_machines = table_exists(cur, "user_machines")
    m_settings = table_exists(cur, "machine_exercise_settings")
    m_column = column_exists(cur, "workout_exercises", "machine_id")
    print(f"  {tick(m_machines)}  table  user_machines")
    print(f"  {tick(m_settings)}  table  machine_exercise_settings")
    print(f"  {tick(m_column)}  column workout_exercises.machine_id")

    print("\n-- migration 013 (running) -------------------------------")
    r_column = column_exists(cur, "disciplines", "logging_type")
    r_table = table_exists(cur, "distance_intervals")
    print(f"  {tick(r_column)}  column disciplines.logging_type")
    print(f"  {tick(r_table)}  table  distance_intervals")

    # The actual answer to "why does running still say it's on the way": the
    # app opens the run logger only when this column reads exactly 'distance'.
    print("\n-- disciplines -------------------------------------------")
    if r_column:
        cur.execute(
            "SELECT discipline_key, label, logging_type, is_active "
            "FROM disciplines ORDER BY sort_order"
        )
        print(f"  {'key':<12} {'label':<12} {'logging_type':<14} active")
        for key, label, logging, active in cur.fetchall():
            print(f"  {key:<12} {label:<12} {logging:<14} {active}")
    else:
        cur.execute(
            "SELECT discipline_key, label, is_active "
            "FROM disciplines ORDER BY sort_order"
        )
        for key, label, active in cur.fetchall():
            print(f"  {key:<12} {label:<12} (no logging_type) {active}")

    print("\n-- data ---------------------------------------------------")
    if r_table:
        cur.execute("SELECT count(*) FROM distance_intervals")
        print(f"  distance_intervals rows: {cur.fetchone()[0]}")
    if m_machines:
        cur.execute("SELECT count(*) FROM user_machines")
        print(f"  user_machines rows:      {cur.fetchone()[0]}")

    print()
    if not (r_column and r_table):
        print("  => Run: python db/run_migration.py db/013_running.sql")
    elif not m_machines:
        print("  => Run: python db/run_migration.py db/012_machines.sql")
    else:
        print("  => Schema is up to date. If running still shows "
              "'logging is on the way',")
        print("     fully restart the app (not hot reload) — the discipline "
              "list is")
        print("     loaded once in initState and hot reload does not re-run it.")

conn.close()
