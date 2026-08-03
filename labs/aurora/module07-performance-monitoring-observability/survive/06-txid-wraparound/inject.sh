#!/usr/bin/env bash
# survive/06-txid-wraparound/inject.sh
# Injects: Simulates approaching TXID wraparound by creating conditions
#          that prevent autovacuum from freezing old transactions.
# Difficulty: Expert
# Idempotent: Yes
#
# NOTE: On Aurora/RDS you cannot directly manipulate the XID counter.
# This inject simulates the conditions that lead to wraparound:
# - A long-running transaction holding back the freeze horizon
# - High transaction rate consuming XIDs rapidly
# - Autovacuum unable to freeze rows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "INJECT: TXID Wraparound Approaching"
echo "============================================"
echo ""

pkill -f "psql.*txid_blocker" 2>/dev/null || true
sleep 2

# Step 1: Create tables that will accumulate unfrozen rows
echo "Creating tables with many rows that need freezing..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
DROP TABLE IF EXISTS txid_test_1;
DROP TABLE IF EXISTS txid_test_2;
DROP TABLE IF EXISTS txid_test_3;

CREATE TABLE txid_test_1 (id BIGSERIAL PRIMARY KEY, data TEXT);
CREATE TABLE txid_test_2 (id BIGSERIAL PRIMARY KEY, data TEXT);
CREATE TABLE txid_test_3 (id BIGSERIAL PRIMARY KEY, data TEXT);

INSERT INTO txid_test_1 (data) SELECT md5(random()::TEXT) FROM generate_series(1, 500000);
INSERT INTO txid_test_2 (data) SELECT md5(random()::TEXT) FROM generate_series(1, 500000);
INSERT INTO txid_test_3 (data) SELECT md5(random()::TEXT) FROM generate_series(1, 500000);
ANALYZE txid_test_1, txid_test_2, txid_test_3;
SQL

# Step 2: Hold a long-running transaction to prevent freezing
echo "Starting long-running transaction to block freeze operations..."
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=0 \
    -c "SET application_name = 'txid_blocker';
        BEGIN;
        SELECT txid_current();
        SELECT pg_sleep(1200);" &>/dev/null &
BLOCKER_PID=$!
echo "$BLOCKER_PID" > "${LOG_DIR}/blocker-pid.txt"

sleep 3

# Step 3: Generate rapid transactions to consume XIDs
echo "Generating rapid transactions to consume XIDs..."
for i in $(seq 1 5); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 \
        -c "SET application_name = 'txid_burner_${i}';
            DO \$\$
            BEGIN
                FOR j IN 1..100000 LOOP
                    UPDATE txid_test_1 SET data = md5(random()::TEXT) WHERE id = (random() * 500000 + 1)::INT;
                END LOOP;
            END;
            \$\$;" &>/dev/null &
done

sleep 3
date > "${LOG_DIR}/inject-time.txt"

# Record current XID age
XID_AGE=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT max(age(datfrozenxid)) FROM pg_database;" 2>/dev/null | tr -d ' ')

echo ""
echo "============================================"
echo "SCENARIO INJECTED: TXID Wraparound Approaching"
echo "============================================"
echo ""
echo "Current max XID age: $XID_AGE"
echo ""
echo "What is happening:"
echo "  - A long-running transaction holds back the freeze horizon"
echo "  - 5 sessions are consuming XIDs rapidly via UPDATE loops"
echo "  - Autovacuum cannot freeze rows older than the blocker's snapshot"
echo "  - XID age is climbing"
echo ""
echo "Symptoms to observe:"
echo "  - CloudWatch MaximumUsedTransactionIDs increasing"
echo "  - pg_database.datfrozenxid age growing"
echo "  - Autovacuum may be running but cannot freeze"
echo ""
echo "WARNING: On a real production database, XID > 1.5B is an emergency."
echo "PostgreSQL shuts down at ~2.1B to prevent data corruption."
echo ""
echo "To stop early:"
echo "  kill $BLOCKER_PID"
echo "  pkill -f 'txid_burner'"
