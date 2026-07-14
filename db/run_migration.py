"""Runs .sql files against the database over a direct Postgres connection.

The Supabase web SQL editor silently truncates large pastes, which corrupts
the import files. This connects straight to Postgres instead, so file size
stops mattering.

The connection string is read from the DATABASE_URL environment variable so
that the password is never written to a file or committed.

Usage (PowerShell):
    $env:DATABASE_URL = "postgresql://postgres:PASSWORD@db.PROJECT.supabase.co:5432/postgres"
    python db/run_migration.py db/003_exercise_catalog_extend.sql db/004_reset_dummy_data.sql db/005_exercise_catalog_import.sql
"""

import os
import sys

import psycopg2

url = os.environ.get("DATABASE_URL")
if not url:
    sys.exit("DATABASE_URL is not set. See the usage note at the top of this file.")

files = sys.argv[1:]
if not files:
    sys.exit("Pass one or more .sql files to run, in order.")

conn = psycopg2.connect(url)
conn.autocommit = False

for path in files:
    with open(path, encoding="utf-8") as f:
        sql = f.read()
    print(f"running {path} ({len(sql) // 1024} KB)... ", end="", flush=True)
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()
        print("ok")
    except Exception as e:
        conn.rollback()
        print("FAILED")
        sys.exit(f"  {type(e).__name__}: {e}")

with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM exercise_catalog")
    total = cur.fetchone()[0]
    cur.execute(
        "SELECT category, count(*) FROM exercise_catalog GROUP BY 1 ORDER BY 1"
    )
    rows = cur.fetchall()

print(f"\nexercise_catalog now holds {total} exercises:")
for category, n in rows:
    print(f"  {category:<10} {n}")

conn.close()
