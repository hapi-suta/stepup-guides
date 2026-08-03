#!/usr/bin/env bash
#
# SURVIVE scenario: data-quality-regression
# inject.sh - a loader with a weakened check lets duplicates and nulls slip into
#             a curated table that downstream reports trust.
#
# What this does (the "break"):
#   1. Builds a self-contained lab in ~/survive-dq-lab with a curated table
#      (dq_curated) in labdb and a "report" query that sums revenue.
#   2. Seeds the table with 5 clean orders and prints the correct total.
#   3. Runs a WEAK loader that (a) has no dedup and (b) allows null customer_id,
#      then loads a batch that contains a duplicated order and a null-customer
#      order - so revenue is now overstated and a customer is unattributable.
#   4. Leaves the bad rows in place. The report total is now WRONG but nothing
#      errored - a silent data-quality regression.
#
# Safe to run on CentOS Stream 9 as ec2-user. Self-contained. Idempotent.
# Requires: python3.12 (or python3) with psycopg2, and labdb reachable.

set -u

LAB="${HOME}/survive-dq-lab"
PY=python3.12
command -v "${PY}" >/dev/null 2>&1 || PY=python3

echo "[inject] Setting up data-quality-regression scenario in ${LAB}"
rm -rf "${LAB}"
mkdir -p "${LAB}"
cd "${LAB}" || exit 1

"${PY}" -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --quiet psycopg2-binary >/dev/null 2>&1

# --- reset the curated table and seed 5 clean orders ---
export PGPASSWORD=labpass
psql -h 127.0.0.1 -U labuser -d labdb >/dev/null 2>&1 <<'SQL'
DROP TABLE IF EXISTS dq_curated;
CREATE TABLE dq_curated (
    order_id     INTEGER,
    customer_id  INTEGER,
    amount       NUMERIC(10,2)
);
INSERT INTO dq_curated (order_id, customer_id, amount) VALUES
  (1, 101, 50.00),
  (2, 102, 30.00),
  (3, 103, 80.00),
  (4, 104, 20.00),
  (5, 105, 40.00);
SQL

echo "[inject] Seeded 5 clean orders. Correct revenue total should be 220.00"
# (adding a legitimate order6=60.00 brings the correct total to 280.00; the
#  duplicate and the null-customer row are what corrupt it beyond that.)

# --- the WEAK loader: no dedup, allows null customer_id (the regression) ---
cat > weak_load.py <<'PY'
import psycopg2

# A batch that arrived from an upstream retry + a broken source row.
BATCH = [
    (6, 106, 60.00),
    (3, 103, 80.00),      # DUPLICATE of order_id 3 (a retry re-sent it)
    (7, None, 25.00),     # NULL customer_id (source glitch) - unattributable revenue
]

conn = psycopg2.connect(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")
with conn.cursor() as cur:
    for order_id, customer_id, amount in BATCH:
        # BUG: blind INSERT, no dedup, no null check. Silently accepts bad rows.
        cur.execute(
            "INSERT INTO dq_curated (order_id, customer_id, amount) VALUES (%s,%s,%s)",
            (order_id, customer_id, amount),
        )
conn.commit()
conn.close()
print(f"[weak_load] inserted {len(BATCH)} rows (no checks)")
PY

echo "[inject] Running the WEAK loader (the regression)..."
python weak_load.py || { echo "[inject] load failed - is labdb reachable?"; exit 1; }

# --- show the now-wrong report ---
WRONG=$(psql -h 127.0.0.1 -U labuser -d labdb -tAc "SELECT sum(amount) FROM dq_curated")
echo
echo "[inject] DONE. Revenue report now reads: ${WRONG} (should be 280.00 = 220 + 60)."
echo "[inject]   (the extra 105.00 = a double-counted 80.00 duplicate + a 25.00 orphan)"
echo "[inject]   - order_id 3 was DUPLICATED (a retry double-counted 80.00)"
echo "[inject]   - order_id 7 has a NULL customer_id (unattributable revenue)"
echo "[inject] Nothing errored - this is a SILENT data-quality regression."
echo "[inject] Your job: RCA it, clean it, and add a data contract that blocks it."
echo "[inject] See runbook.md. Then run: bash validate.sh"
