#!/usr/bin/env bash
# survive/06-txid-wraparound/inject.sh
# Simulates approaching TXID wraparound by creating a table with artificially
# aged relfrozenxid and blocking autovacuum freeze.
# Difficulty: Expert
#
# NOTE: We cannot actually age transaction IDs to 2.1B in a lab (it requires
# executing billions of transactions). Instead, we simulate the scenario by:
# 1. Creating a table with many dead tuples
# 2. Setting autovacuum_freeze_max_age very low so the warning condition triggers
# 3. Blocking autovacuum with a long-running transaction
# The student must understand the wraparound risk, find the danger table,
# and perform emergency VACUUM FREEZE.

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "INJECT: TXID Wraparound Approaching"
log "Setting up wraparound simulation"

# Create a table that has not been vacuumed in a long time
psql_exec "
DROP TABLE IF EXISTS wraparound_risk;
CREATE TABLE wraparound_risk (
    id BIGSERIAL PRIMARY KEY,
    payload TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
);

-- Insert 1M rows across many transactions to age the XIDs
DO \$\$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        INSERT INTO wraparound_risk (payload, status)
        SELECT md5(random()::TEXT), 'active'
        FROM generate_series(1, 10000);
        PERFORM pg_sleep(0.01);
    END LOOP;
END \$\$;

-- Generate dead tuples
UPDATE wraparound_risk SET status = 'updated' WHERE id % 3 = 0;
UPDATE wraparound_risk SET status = 'active' WHERE id % 3 = 0;
DELETE FROM wraparound_risk WHERE id % 7 = 0;
"

log "Table created with dead tuples. Setting up autovacuum block..."

# Start a long transaction to block autovacuum freeze
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "BEGIN; SELECT count(*) FROM wraparound_risk; SELECT pg_sleep(1800);" &>/dev/null &
BLOCKER_PID=$!
echo "$BLOCKER_PID" > "${SURVIVE_LOG_DIR}/06-blocker-pid.txt"

# Set autovacuum_freeze_max_age very low to simulate near-wraparound condition
# (In reality this would take billions of transactions; we simulate the urgency)
psql_exec "
ALTER TABLE wraparound_risk SET (autovacuum_freeze_max_age = 100000);
"

echo "$(date)" > "${SURVIVE_LOG_DIR}/06-inject-time.txt"

# Show the current XID age of the table
XID_AGE=$(psql_exec "SELECT age(relfrozenxid) FROM pg_class WHERE relname = 'wraparound_risk'")
DB_XID_AGE=$(psql_exec "SELECT max(age(datfrozenxid)) FROM pg_database")

log "Table relfrozenxid age: $XID_AGE"
log "Database datfrozenxid age: $DB_XID_AGE"

echo ""
echo "=========================================="
echo "SCENARIO INJECTED: TXID Wraparound Risk"
echo "=========================================="
echo ""
echo "What the student sees:"
echo "  - CloudWatch MaximumUsedTransactionIDs alarm is firing (simulated)"
echo "  - pg_class shows the wraparound_risk table has high XID age"
echo "  - A long-running transaction is blocking autovacuum from freezing"
echo "  - autovacuum_freeze_max_age is set to 100000 (very aggressive)"
echo ""
echo "The student must:"
echo "  1. Identify the highest-risk table"
echo "  2. Identify and kill the blocking transaction"
echo "  3. Run VACUUM FREEZE on the at-risk table"
echo "  4. Verify XID age drops to near 0"
echo "  5. Set up monitoring to prevent recurrence"
echo ""
echo "Table XID age: $XID_AGE"
echo "Database XID age: $DB_XID_AGE"
echo ""
echo "Blocker PID: $BLOCKER_PID"
