#!/usr/bin/env bash
# SURVIVE Scenario 05: Schema Migration Gone Wrong
# Injects: Runs a bad migration that adds a NOT NULL column without a default,
#          causing application errors, and creates a long-running lock.
# Idempotent: Drops chaos objects before recreating.
#
# Usage: bash inject.sh
# Requires: psql, DB_HOST/DB_USER/DB_PASSWORD set

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"
DB_HOST="${DB_HOST:-$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Endpoint' --output text --region "$REGION")}"
DB_USER="${DB_USER:-dbadmin}"
DB_PASSWORD="${DB_PASSWORD:?ERROR: Set DB_PASSWORD environment variable}"

echo "============================================="
echo "  SURVIVE Scenario 05: Schema Migration Gone Wrong"
echo "============================================="
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Step 1: Create a table simulating a production table
echo "Setting up production-like table..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "
  CREATE SCHEMA IF NOT EXISTS app;
  DROP TABLE IF EXISTS app.orders CASCADE;
  CREATE TABLE app.orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  INSERT INTO app.orders (customer_id, total_amount, status)
  SELECT
    (random() * 10000)::bigint,
    (random() * 1000)::numeric(12,2),
    CASE WHEN random() > 0.5 THEN 'completed' ELSE 'pending' END
  FROM generate_series(1, 50000);
" 2>/dev/null

echo "Created app.orders with 50,000 rows."
echo ""

# Step 2: Simulate a bad migration - hold a lock on the table
echo "Simulating a bad migration that holds an ACCESS EXCLUSIVE lock..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "
  BEGIN;
  LOCK TABLE app.orders IN ACCESS EXCLUSIVE MODE;
  -- This simulates a migration that runs ALTER TABLE but takes forever
  SELECT pg_sleep(300);
  COMMIT;
" &>/dev/null &
LOCK_PID=$!

echo "Lock holder PID (local): $LOCK_PID"
echo "A migration is holding an ACCESS EXCLUSIVE lock on app.orders."
echo "All queries to app.orders will block."
echo ""

# Step 3: Attempt a bad ALTER TABLE (will queue behind the lock)
echo "Queuing a bad ALTER TABLE (NOT NULL without default)..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "
  SET statement_timeout = '10s';
  ALTER TABLE app.orders ADD COLUMN shipping_address TEXT NOT NULL;
" &>/dev/null &

sleep 2

echo ""
echo "YOUR MISSION:"
echo "  1. Detect the blocking lock using pg_stat_activity"
echo "  2. Identify the blocked queries"
echo "  3. Terminate the lock-holding session"
echo "  4. Fix the bad migration (add column WITH a default)"
echo "  5. Verify the table is accessible again"
echo "  6. Document the incident and write a prevention plan"
echo ""
echo "HINT: The lock will expire in 5 minutes due to statement_timeout."
echo "      But your application is DOWN right now. Fix it faster."
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
