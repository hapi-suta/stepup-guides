#!/bin/bash
set -euo pipefail

# =============================================================================
# SURVIVE 01: Migration Lock Timeout
# Scenario: ALTER TABLE is blocked by a long-running query
#
# This script is IDEMPOTENT - safe to run multiple times.
#
# What it does:
#   1. Creates a test database (survive_lock_timeout)
#   2. Creates a large table with sample data
#   3. Starts a long-running SELECT that holds a lock
#   4. Attempts an ALTER TABLE that gets blocked by the SELECT
#
# The student must identify the blocking query, kill it, and apply the
# ALTER TABLE with proper lock_timeout settings.
# =============================================================================

AURORA_ENDPOINT="${AURORA_ENDPOINT:-localhost}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="survive_lock_timeout"

echo "=== SURVIVE 01: Migration Lock Timeout - Injecting Scenario ==="
echo ""

# Step 1: Create database (idempotent)
echo "Step 1: Creating database ${DB_NAME}..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "CREATE DATABASE ${DB_NAME};"
echo "  Database created."

# Step 2: Create table with data
echo "Step 2: Creating table with 500,000 rows..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB_NAME}" -c "
CREATE TABLE IF NOT EXISTS transactions (
    txn_id      SERIAL PRIMARY KEY,
    account_id  INTEGER NOT NULL,
    amount      NUMERIC(12,2) NOT NULL,
    txn_type    VARCHAR(20) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    description TEXT
);

TRUNCATE transactions;

INSERT INTO transactions (account_id, amount, txn_type, created_at, description)
SELECT
    (random() * 10000)::int + 1,
    (random() * 10000)::numeric(12,2),
    CASE (random() * 2)::int WHEN 0 THEN 'debit' WHEN 1 THEN 'credit' ELSE 'transfer' END,
    now() - (random() * 365)::int * interval '1 day',
    'Transaction ' || i
FROM generate_series(1, 500000) AS i;

ANALYZE transactions;
"
echo "  Table created and populated."

# Step 3: Start a long-running query in the background
# This holds a lock that will block ALTER TABLE
echo "Step 3: Starting long-running query (holds lock for ~120 seconds)..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB_NAME}" -c "
BEGIN;
-- This SELECT with FOR SHARE holds a SHARE lock on every row it touches
SELECT count(*) FROM transactions WHERE pg_sleep(0.0002) IS NOT NULL;
COMMIT;
" &
BLOCKING_PID=$!
echo "  Long-running query started (local PID: ${BLOCKING_PID})."
echo ""

# Give the query a moment to start
sleep 3

# Step 4: Start the migration that will get blocked
echo "Step 4: Starting ALTER TABLE (this will be blocked by the long query)..."
echo "  The ALTER TABLE is waiting for a lock..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB_NAME}" -c "
-- This migration does NOT have lock_timeout - it will wait forever
ALTER TABLE transactions ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
" &
MIGRATION_PID=$!
echo "  Migration started (local PID: ${MIGRATION_PID})."
echo ""

echo "=== Scenario Injected ==="
echo ""
echo "Current state:"
echo "  - A long-running SELECT is holding a lock on the transactions table"
echo "  - An ALTER TABLE is waiting to acquire ACCESS EXCLUSIVE lock"
echo "  - Any new queries on the transactions table are also blocked"
echo ""
echo "Your mission:"
echo "  1. Identify the blocking query using pg_stat_activity"
echo "  2. Find the lock queue using pg_locks"
echo "  3. Decide: wait or kill?"
echo "  4. Cancel the blocking query with pg_cancel_backend()"
echo "  5. Verify the ALTER TABLE completes or rewrite with lock_timeout"
echo ""
echo "Start by connecting to the database:"
echo "  psql -h ${AURORA_ENDPOINT} -U ${DB_USER} -d ${DB_NAME}"
echo ""
echo "Background PIDs: blocking=${BLOCKING_PID}, migration=${MIGRATION_PID}"
echo "To clean up manually: kill ${BLOCKING_PID} ${MIGRATION_PID} 2>/dev/null"
