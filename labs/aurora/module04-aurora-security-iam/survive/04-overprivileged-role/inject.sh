#!/usr/bin/env bash
# Scenario 04 - Overprivileged Role
# inject.sh: Creates a database role with excessive privileges.
#
# What this does:
#   1. Creates a financedb database with multiple tables
#   2. Creates a report_user role with ALL PRIVILEGES (too much)
#   3. Students must audit and fix the privileges to least privilege
#
# Usage:
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/04-overprivileged-role/inject.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 04 - Injecting: Overprivileged Role"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ENDPOINT MASTER_USER MASTER_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Export it before running this script."
    exit 1
  fi
done

# ── Create database and schema ──────────────────────────────────────────────
echo "[INFO] Setting up scenario database and tables..."

PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --command="SELECT 'CREATE DATABASE financedb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'financedb');" 2>/dev/null

PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --command="CREATE DATABASE financedb;" 2>/dev/null || true

PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=financedb user=$MASTER_USER sslmode=require" << 'EOSQL' 2>/dev/null
CREATE SCHEMA IF NOT EXISTS finance;

CREATE TABLE IF NOT EXISTS finance.accounts (
    id SERIAL PRIMARY KEY,
    account_number TEXT UNIQUE,
    owner_name TEXT,
    balance NUMERIC(15,2)
);

CREATE TABLE IF NOT EXISTS finance.transactions (
    id SERIAL PRIMARY KEY,
    account_id INT,
    amount NUMERIC(15,2),
    type TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS finance.audit_trail (
    id SERIAL PRIMARY KEY,
    action TEXT,
    performed_by TEXT,
    performed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS finance.internal_notes (
    id SERIAL PRIMARY KEY,
    note TEXT,
    confidentiality TEXT DEFAULT 'internal'
);

INSERT INTO finance.accounts (account_number, owner_name, balance)
VALUES
  ('ACC-001', 'Alice Corp', 50000.00),
  ('ACC-002', 'Bob Ltd', 125000.00)
ON CONFLICT DO NOTHING;

INSERT INTO finance.internal_notes (note, confidentiality)
VALUES
  ('Q3 audit findings - do not share', 'confidential'),
  ('Executive salary data for review', 'restricted')
ON CONFLICT DO NOTHING;
EOSQL

echo "[OK] Schema and tables created."

# ── Create the overprivileged role ──────────────────────────────────────────
echo "[INFO] Creating role 'report_user' with excessive privileges..."

PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=financedb user=$MASTER_USER sslmode=require" << 'EOSQL' 2>/dev/null
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'report_user') THEN
    CREATE ROLE report_user WITH LOGIN PASSWORD 'ReportPass1!';
  ELSE
    ALTER ROLE report_user WITH LOGIN PASSWORD 'ReportPass1!';
  END IF;
END $$;

GRANT CONNECT ON DATABASE financedb TO report_user;
GRANT USAGE ON SCHEMA finance TO report_user;

-- THE PROBLEM: report_user should only have SELECT on accounts and transactions
-- but was accidentally given ALL on everything
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA finance TO report_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA finance TO report_user;
GRANT CREATE ON SCHEMA finance TO report_user;
EOSQL

echo "[OK] Role 'report_user' created with excessive privileges."

# ── Save scenario state ─────────────────────────────────────────────────────
STATE_FILE="/tmp/module04-scenario04-state.sh"
cat > "$STATE_FILE" << EOF
export SCENARIO04_ROLE="report_user"
export SCENARIO04_DB="financedb"
export SCENARIO04_SCHEMA="finance"
export SCENARIO04_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

echo ""
echo "============================================"
echo "  INJECTION COMPLETE - SECURITY AUDIT FINDING"
echo "============================================"
echo ""
echo "  Situation:"
echo "    A quarterly security audit has just completed."
echo "    The audit found that 'report_user' has excessive privileges."
echo "    This role is used by the BI reporting tool and should be read-only."
echo "    Instead, it has FULL read/write/delete access to ALL tables including"
echo "    confidential tables (audit_trail, internal_notes) it should not see."
echo ""
echo "  Your job:"
echo "    1. Audit what 'report_user' can currently access"
echo "    2. Determine what it SHOULD be able to access"
echo "    3. Revoke the excessive privileges"
echo "    4. Grant only the correct privileges"
echo "    5. Verify the role cannot do what it should not"
echo ""
echo "  Expected final state for report_user:"
echo "    finance.accounts     - SELECT only"
echo "    finance.transactions - SELECT only"
echo "    finance.audit_trail  - NO ACCESS"
echo "    finance.internal_notes - NO ACCESS"
echo "    No INSERT, UPDATE, DELETE, or CREATE on anything"
echo ""
echo "  Runbook:  survive/04-overprivileged-role/runbook.md"
echo "  Validate: bash survive/04-overprivileged-role/validate.sh"
echo ""
echo "============================================"
