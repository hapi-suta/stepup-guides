#!/usr/bin/env bash
#
# SURVIVE scenario: data-quality-regression
# validate.sh - exits 0 when the data is cleaned AND a contract loader exists that
#               rejects a bad batch; 1 otherwise.
#
# Passing criteria (all must hold):
#   1. dq_curated has exactly 7 rows (duplicate removed, orphan kept/attributed).
#   2. Revenue sum is 305.00 (double-count removed; orphan 25.00 retained/attributed).
#   3. No duplicate order_id remains.
#   4. No NULL customer_id remains.
#   5. contract_load.py exists and REJECTS a batch containing a duplicate/null
#      (proves the durable fix, not just a manual cleanup).
#
# Run on your lab server as ec2-user. Self-contained. Uses labdb.

LAB="${HOME}/survive-dq-lab"
PGHOST=127.0.0.1
PGDB=labdb
PGUSER=labuser
export PGPASSWORD=labpass

q() { psql -h "$PGHOST" -U "$PGUSER" -d "$PGDB" -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }
fail() { echo "[validate] FAIL: $1"; exit 1; }

# 0. table exists
EXISTS="$(q "SELECT to_regclass('public.dq_curated') IS NOT NULL")"
[ "$EXISTS" = "t" ] || fail "table dq_curated missing - run inject.sh then the runbook."

# 1. exactly 7 rows
ROWS="$(q "SELECT count(*) FROM dq_curated")"
[ "$ROWS" = "7" ] || fail "expected 7 rows, found ${ROWS:-0} - clean the duplicate (runbook step 6)."

# 2. revenue 305.00 (duplicate 80.00 removed; orphan 25.00 retained/attributed)
REV="$(q "SELECT sum(amount) FROM dq_curated")"
[ "$REV" = "305.00" ] || fail "revenue is ${REV:-none}, expected 305.00 - remove the duplicate 80.00 and attribute (not drop) the orphan (runbook step 6)."

# 3. no duplicate order_id
DUPES="$(q "SELECT count(*) FROM (SELECT order_id FROM dq_curated GROUP BY order_id HAVING count(*)>1) d")"
[ "$DUPES" = "0" ] || fail "${DUPES} duplicate order_id groups remain (runbook step 6)."

# 4. no null customer_id
NULLS="$(q "SELECT count(*) FROM dq_curated WHERE customer_id IS NULL")"
[ "$NULLS" = "0" ] || fail "${NULLS} rows still have NULL customer_id (runbook step 6)."

# 5. contract_load.py must exist and reject a bad batch (non-zero exit).
[ -f "${LAB}/contract_load.py" ] || fail "contract_load.py not found in ${LAB} (runbook step 7)."

PY="${LAB}/.venv/bin/python"
[ -x "$PY" ] || PY=python3
REJECT_OUT="$(cd "$LAB" && "$PY" contract_load.py 2>&1)"
REJECT_CODE=$?
if [ "$REJECT_CODE" -eq 0 ]; then
    fail "contract_load.py accepted a bad batch (exit 0) - it must reject duplicates/nulls (runbook step 7)."
fi
echo "$REJECT_OUT" | grep -qiE "reject|violation|duplicate|null" \
    || fail "contract_load.py exited non-zero but did not report a contract violation (runbook step 7)."

echo "[validate] PASS: data cleaned (305.00, 7 rows, no dupes, no nulls) and contract_load.py enforces a contract"
exit 0
