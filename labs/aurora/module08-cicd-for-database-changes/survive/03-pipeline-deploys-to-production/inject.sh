#!/bin/bash
set -euo pipefail

# =============================================================================
# SURVIVE 03: Pipeline Deploys to Production
# Scenario: CI/CD pipeline targets the wrong environment - production gets
# a migration meant only for staging.
#
# This script is IDEMPOTENT - safe to run multiple times.
#
# What it does:
#   1. Creates two databases: survive_staging and survive_production
#   2. Sets up identical schemas in both (simulating a well-managed environment)
#   3. Applies a destructive migration to "production" that:
#      - Drops a column with data
#      - Adds a test table that should only exist in staging
#      - Inserts test data that should never be in production
#
# The student must assess the damage, remediate, and implement guardrails.
# =============================================================================

AURORA_ENDPOINT="${AURORA_ENDPOINT:-localhost}"
DB_USER="${DB_USER:-postgres}"

echo "=== SURVIVE 03: Pipeline Deploys to Production - Injecting Scenario ==="
echo ""

# Step 1: Create both databases
echo "Step 1: Creating staging and production databases..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "DROP DATABASE IF EXISTS survive_staging;" 2>/dev/null || true
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "DROP DATABASE IF EXISTS survive_production;" 2>/dev/null || true
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "CREATE DATABASE survive_staging;"
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -c "CREATE DATABASE survive_production;"
echo "  Both databases created."

# Step 2: Set up identical schemas
echo "Step 2: Setting up identical schemas in both databases..."
for DB in survive_staging survive_production; do
    psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB}" -c "
    CREATE TABLE customers (
        customer_id  SERIAL PRIMARY KEY,
        name         VARCHAR(100) NOT NULL,
        email        VARCHAR(255) UNIQUE,
        phone        VARCHAR(20),
        tier         VARCHAR(20) DEFAULT 'free',
        created_at   TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE orders (
        order_id     SERIAL PRIMARY KEY,
        customer_id  INTEGER REFERENCES customers(customer_id),
        status       VARCHAR(20) DEFAULT 'pending',
        total_amount NUMERIC(12,2) DEFAULT 0,
        ordered_at   TIMESTAMPTZ DEFAULT now()
    );

    CREATE INDEX idx_orders_customer_id ON orders (customer_id);
    CREATE INDEX idx_orders_status ON orders (status);
    "
done
echo "  Identical schemas created."

# Step 3: Add production data (staging gets less data)
echo "Step 3: Populating databases with data..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d survive_staging -c "
INSERT INTO customers (name, email, phone, tier)
SELECT 'Test User ' || i, 'test' || i || '@staging.com', '+1-555-0000', 'free'
FROM generate_series(1, 100) AS i;
"

psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d survive_production -c "
INSERT INTO customers (name, email, phone, tier)
SELECT 'Real Customer ' || i, 'customer' || i || '@realcompany.com', '+1-' || lpad((5550000 + i)::text, 8, '0'),
    CASE (i % 3) WHEN 0 THEN 'free' WHEN 1 THEN 'pro' ELSE 'enterprise' END
FROM generate_series(1, 50000) AS i;

INSERT INTO orders (customer_id, status, total_amount, ordered_at)
SELECT
    (random() * 49999 + 1)::int,
    CASE (random() * 3)::int WHEN 0 THEN 'pending' WHEN 1 THEN 'confirmed' WHEN 2 THEN 'shipped' ELSE 'delivered' END,
    (random() * 500 + 10)::numeric(12,2),
    now() - (random() * 180)::int * interval '1 day'
FROM generate_series(1, 200000) AS i;
"
echo "  Staging: 100 test users, 0 orders."
echo "  Production: 50,000 real customers, 200,000 real orders."

# Step 4: Simulate the wrong-environment deployment
echo "Step 4: Simulating migration deployed to wrong environment..."
psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d survive_production -c "
-- This migration was meant for staging only:
-- It drops the phone column (testing a migration for a future feature)
ALTER TABLE customers DROP COLUMN phone;

-- It creates a test table with fake data
CREATE TABLE test_load_data (
    id SERIAL PRIMARY KEY,
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO test_load_data (payload)
SELECT jsonb_build_object('test_key', 'test_value_' || i, 'environment', 'staging')
FROM generate_series(1, 10000) AS i;

-- It resets all customer tiers to 'free' (test data reset script)
UPDATE customers SET tier = 'free';
"
echo "  Destructive migration applied to production."

echo ""
echo "=== Scenario Injected ==="
echo ""
echo "Current state:"
echo "  STAGING (survive_staging):"
echo "    - Schema: customers (with phone column), orders"
echo "    - Data: 100 test users, 0 orders"
echo "    - Status: CLEAN (migration was not applied here)"
echo ""
echo "  PRODUCTION (survive_production):"
echo "    - Schema: customers (phone column DROPPED), orders, test_load_data"
echo "    - Data: 50,000 real customers (all tiers reset to 'free'), 200,000 orders"
echo "    - Damage:"
echo "      1. phone column dropped - all phone numbers LOST"
echo "      2. test_load_data table exists (should not be in production)"
echo "      3. All customer tiers reset to 'free' (enterprise/pro lost)"
echo ""
echo "Your mission:"
echo "  1. Assess the full damage (what was changed, what data was lost)"
echo "  2. Determine what can be recovered and what cannot"
echo "  3. Remediate: remove test data, restore what you can"
echo "  4. Document the incident"
echo "  5. Implement guardrails to prevent this from happening again"
echo ""
echo "Connect to production:"
echo "  psql -h ${AURORA_ENDPOINT} -U ${DB_USER} -d survive_production"
echo ""
echo "Connect to staging (for reference):"
echo "  psql -h ${AURORA_ENDPOINT} -U ${DB_USER} -d survive_staging"
