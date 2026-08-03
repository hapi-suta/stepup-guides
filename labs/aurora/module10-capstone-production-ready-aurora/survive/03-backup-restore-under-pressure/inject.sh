#!/usr/bin/env bash
# SURVIVE Scenario 03: Backup Restore Under Pressure
# Injects: Simulates data loss by dropping a critical table.
# Idempotent: Recreates the table if it does not exist before dropping.
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
echo "  SURVIVE Scenario 03: Backup Restore Under Pressure"
echo "============================================="
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Step 1: Ensure the table exists with data
echo "Ensuring app.critical_data table exists with test data..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "
  CREATE SCHEMA IF NOT EXISTS app;
  CREATE TABLE IF NOT EXISTS app.critical_data (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_name TEXT NOT NULL,
    account_balance NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  TRUNCATE app.critical_data;
  INSERT INTO app.critical_data (customer_name, account_balance)
  SELECT
    'Customer ' || generate_series(1, 1000),
    (random() * 100000)::numeric(12,2);
" 2>/dev/null

echo "Inserted 1,000 customer records into app.critical_data."
echo ""

# Record the time AFTER data insertion (this is the PITR target)
sleep 5
SAFE_RESTORE_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Safe restore point: $SAFE_RESTORE_TIME"
echo "(Data existed at this point - restore to this time to recover)"
echo ""

# Step 2: Wait and then drop the table
sleep 5
echo "SIMULATING DATA LOSS: Dropping app.critical_data..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "
  DROP TABLE IF EXISTS app.critical_data CASCADE;
" 2>/dev/null

DROP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Table dropped at: $DROP_TIME"
echo ""

echo "YOUR MISSION:"
echo "  1. Verify the table is gone (SELECT from it - should fail)"
echo "  2. Identify the latest restorable time for the cluster"
echo "  3. Perform a point-in-time restore to: $SAFE_RESTORE_TIME"
echo "  4. Create an instance in the restored cluster"
echo "  5. Verify the data exists in the restored cluster"
echo "  6. Clean up the restored cluster when done"
echo ""
echo "SAFE RESTORE TIME: $SAFE_RESTORE_TIME"
echo "TABLE DROPPED AT:  $DROP_TIME"
echo ""
echo "You have 15 minutes. CLOCK IS TICKING."
