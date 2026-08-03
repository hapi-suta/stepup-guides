#!/usr/bin/env bash
#
# SURVIVE scenario: schema-evolution
# validate.sh - exits 0 when the drift is adapted and the data is correct, 1 if not.
#
# Passing criteria (all must hold):
#   1. schema_curated has a 'phone' column (new column was backfilled).
#   2. schema_curated has exactly 4 rows (row 4 arrived during the break and loaded).
#   3. No NULL full_name (the rename was adapted, not silently null-loaded).
#   4. Row 4 (Dee Spacer) is present with its phone (proves the break-time row loaded).
#
# Run on your lab server as ec2-user. Self-contained. Uses labdb.

PGHOST=127.0.0.1
PGDB=labdb
PGUSER=labuser
export PGPASSWORD=labpass

q() { psql -h "$PGHOST" -U "$PGUSER" -d "$PGDB" -tAc "$1" 2>/dev/null; }

fail() { echo "[validate] FAIL: $1"; exit 1; }

# 0. Table must exist.
EXISTS="$(q "SELECT to_regclass('public.schema_curated') IS NOT NULL")"
[ "$EXISTS" = "t" ] || fail "table schema_curated does not exist - run load.py after inject.sh (runbook step 6)."

# 1. phone column must exist.
HAS_PHONE="$(q "SELECT count(*) FROM information_schema.columns WHERE table_name='schema_curated' AND column_name='phone'")"
[ "$HAS_PHONE" = "1" ] || fail "no 'phone' column - backfill the new column with ALTER TABLE ADD COLUMN (runbook step 5)."

# 2. exactly 4 rows.
ROWS="$(q "SELECT count(*) FROM schema_curated")"
[ "$ROWS" = "4" ] || fail "expected 4 rows, found ${ROWS:-0} - adapt the loader and re-run load.py (runbook step 6)."

# 3. no null full_name (rename adapted, not null-loaded).
NULLS="$(q "SELECT count(*) FROM schema_curated WHERE full_name IS NULL OR full_name=''")"
[ "$NULLS" = "0" ] || fail "found ${NULLS} rows with empty full_name - the rename was silently null-loaded; add the RENAMES map (runbook step 5)."

# 4. row 4 present with its phone.
ROW4="$(q "SELECT count(*) FROM schema_curated WHERE customer_id=4 AND phone='555-0004'")"
[ "$ROW4" = "1" ] || fail "customer_id 4 with phone 555-0004 not found - the break-time row did not load (runbook step 6)."

echo "[validate] PASS: schema drift adapted, phone backfilled, row 4 loaded, no nulls"
exit 0
