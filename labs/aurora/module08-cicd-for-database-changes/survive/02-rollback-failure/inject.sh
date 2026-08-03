#!/bin/bash
set -euo pipefail

# =============================================================================
# SURVIVE 02: Rollback Failure
# Scenario: A migration partially applied. The undo script fails.
#
# This script is IDEMPOTENT - safe to run multiple times.
#
# What it does:
#   1. Creates a test database (survive_rollback_failure)
#   2. Creates a table with 1M rows
#   3. Simulates a partially-applied migration:
#      - Column was added
#      - 400,000 of 1,000,000 rows were backfilled
#      - NOT NULL constraint was never applied
#   4. Creates a fake flyway_schema_history with a failed entry
#
# The student must assess the state, decide to roll forward,
# complete the backfill, add the constraint, and fix Flyway history.
# =============================================================================

AURORA_ENDPOINT="${AURORA_ENDPOINT:-localhost}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="survive_rollback_failure"

echo "=== SURVIVE 02: Rollback Failure - Injecting Scenario ==="
echo ""

# Step 1: Create database (idempotent)
echo "Step 1: Creating database ${DB_NAME}..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "CREATE DATABASE ${DB_NAME};"
echo "  Database created."

# Step 2: Create table with data and simulate partial migration
echo "Step 2: Creating table with 1,000,000 rows and simulating partial migration..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB_NAME}" -c "
-- Create the original table
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    email        VARCHAR(255),
    total_orders INTEGER DEFAULT 0,
    created_at   TIMESTAMPTZ DEFAULT now()
);

-- Insert 1 million rows
INSERT INTO customers (name, email, total_orders)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com',
    (random() * 50)::int
FROM generate_series(1, 1000000) AS i;

-- Simulate the partially-applied migration:
-- Step A: Column was added successfully
ALTER TABLE customers ADD COLUMN loyalty_tier VARCHAR(20);

-- Step B: Only 400,000 rows were backfilled before the migration crashed
UPDATE customers
SET loyalty_tier = CASE
    WHEN total_orders >= 20 THEN 'gold'
    WHEN total_orders >= 10 THEN 'silver'
    ELSE 'bronze'
END
WHERE customer_id <= 400000;

-- Step C: Create fake flyway_schema_history to simulate Flyway state
CREATE TABLE IF NOT EXISTS flyway_schema_history (
    installed_rank INTEGER PRIMARY KEY,
    version        VARCHAR(50),
    description    VARCHAR(200),
    type           VARCHAR(20),
    script         VARCHAR(1000),
    checksum       INTEGER,
    installed_by   VARCHAR(100),
    installed_on   TIMESTAMPTZ DEFAULT now(),
    execution_time INTEGER,
    success        BOOLEAN
);

-- V1 succeeded, V2 failed
INSERT INTO flyway_schema_history VALUES
(1, '1', 'create customers', 'SQL', 'V1__create_customers.sql', 12345, 'flyway_user', now() - interval '30 days', 150, true),
(2, '2', 'add loyalty tier and backfill', 'SQL', 'V2__add_loyalty_tier.sql', 67890, 'flyway_user', now() - interval '5 minutes', 45000, false);

ANALYZE customers;
"
echo "  Table created with partial migration state."

echo ""
echo "=== Scenario Injected ==="
echo ""
echo "Current state:"
echo "  - customers table has 1,000,000 rows"
echo "  - loyalty_tier column exists (added by the migration)"
echo "  - 400,000 rows have loyalty_tier populated"
echo "  - 600,000 rows have loyalty_tier = NULL"
echo "  - NOT NULL constraint was never applied"
echo "  - flyway_schema_history shows V2 as FAILED"
echo "  - Flyway will refuse to run any new migrations"
echo ""
echo "Your mission:"
echo "  1. Assess the current state (how many NULLs? how many backfilled?)"
echo "  2. Decide: roll forward or roll back?"
echo "  3. Complete the backfill (batched, with progress reporting)"
echo "  4. Add the NOT NULL constraint safely (NOT VALID + VALIDATE)"
echo "  5. Fix Flyway history (repair or manual fix)"
echo "  6. Verify everything is clean"
echo ""
echo "Connect to the database:"
echo "  psql -h ${AURORA_ENDPOINT} -U ${DB_USER} -d ${DB_NAME}"
