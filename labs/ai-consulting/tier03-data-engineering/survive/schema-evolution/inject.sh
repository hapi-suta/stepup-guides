#!/usr/bin/env bash
#
# SURVIVE scenario: schema-evolution
# inject.sh - a source system renames a column and adds a new one, silently
#             breaking a pipeline that expected the old schema.
#
# What this does (the "break"):
#   1. Creates a self-contained mini pipeline in ~/survive-schema-lab that reads
#      a CSV source and loads a curated table in labdb.
#   2. Runs it once against the ORIGINAL schema so a good baseline exists.
#   3. Rewrites the source CSV with an EVOLVED schema:
#         - renames  full_name  ->  customer_name   (rename of a required column)
#         - adds     phone                          (a brand-new column)
#   4. Leaves the pipeline pointing at the OLD column names, so the next run
#      either crashes or silently loads nulls - the classic schema-drift failure.
#
# Safe to run on CentOS Stream 9 as ec2-user. Self-contained. Idempotent.
# Requires: python3.12 (or python3) with pandas + psycopg2, and labdb reachable.

set -u

LAB="${HOME}/survive-schema-lab"
PY=python3.12
command -v "${PY}" >/dev/null 2>&1 || PY=python3

echo "[inject] Setting up schema-evolution scenario in ${LAB}"
rm -rf "${LAB}"
mkdir -p "${LAB}"
cd "${LAB}" || exit 1

# --- venv with the libs the pipeline needs ---
"${PY}" -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --quiet pandas psycopg2-binary >/dev/null 2>&1

# --- the ORIGINAL source CSV (full_name, no phone) ---
cat > source.csv <<'CSV'
customer_id,email,full_name,region
1,ada@example.com,Ada Lovelace,East
2,ben@example.com,Ben Franklin,West
3,cy@example.com,Cy Young,East
CSV

# --- the pipeline, written to expect the ORIGINAL schema ---
cat > load.py <<'PY'
import sys
import pandas as pd
import psycopg2

DB = dict(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")
EXPECTED = ["customer_id", "email", "full_name", "region"]   # the schema we were built for

def main():
    df = pd.read_csv("source.csv")

    # Naive loader: assumes the columns it was built for are present.
    # (This is the bug: no schema check. A rename makes full_name KeyError,
    #  or if you switch to .get() it silently loads nulls.)
    conn = psycopg2.connect(**DB)
    with conn.cursor() as cur:
        cur.execute("""CREATE TABLE IF NOT EXISTS schema_curated (
            customer_id INTEGER PRIMARY KEY,
            email TEXT,
            full_name TEXT,
            region TEXT)""")
        for _, r in df.iterrows():
            cur.execute(
                """INSERT INTO schema_curated (customer_id, email, full_name, region)
                   VALUES (%s,%s,%s,%s)
                   ON CONFLICT (customer_id) DO UPDATE SET
                     email=EXCLUDED.email, full_name=EXCLUDED.full_name, region=EXCLUDED.region""",
                (int(r["customer_id"]), r["email"], r["full_name"], r["region"]),
            )
    conn.commit()
    conn.close()
    print(f"[load] loaded {len(df)} rows")

if __name__ == "__main__":
    main()
PY

echo "[inject] Running the pipeline once on the ORIGINAL schema (baseline)..."
python load.py || { echo "[inject] baseline run failed - is labdb reachable?"; exit 1; }

# --- NOW EVOLVE THE SOURCE SCHEMA (the break) ---
cat > source.csv <<'CSV'
customer_id,email,customer_name,region,phone
1,ada@example.com,Ada Lovelace,East,555-0001
2,ben@example.com,Ben Franklin,West,555-0002
3,cy@example.com,Cy Young,East,555-0003
4,dee@example.com,Dee Spacer,North,555-0004
CSV

echo
echo "[inject] DONE. The source schema changed under the pipeline:"
echo "[inject]   - 'full_name' was RENAMED to 'customer_name'"
echo "[inject]   - a new 'phone' column was ADDED"
echo "[inject]   - a new row (customer_id 4) also arrived"
echo "[inject] The next run of load.py will break (KeyError on full_name)."
echo "[inject] Your job: detect the drift, adapt the loader, and backfill row 4."
echo "[inject] See runbook.md. Then run: bash validate.sh"
