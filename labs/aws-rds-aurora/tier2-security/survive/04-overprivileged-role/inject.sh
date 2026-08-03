#!/usr/bin/env bash
# Scenario 04 - Overprivileged Role
# inject.sh: Creates a database role with excessive privileges that a security
#            audit has just discovered.
#
# Usage:
#   source survive/config.sh
#   bash survive/04-overprivileged-role/inject.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "Scenario 04 - Injecting: Overprivileged Role"

check_aws_cli
check_psql
check_config_loaded

# ─── Create database and schema ────────────────────────────────────────────────
info "Setting up scenario database and tables..."

PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=require" << 'EOSQL' 2>/dev/null
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'financedb') THEN
    CREATE DATABASE financedb;
  END IF;
END $$;
EOSQL

PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=financedb user=$RDS_MASTER_USER sslmode=require" << 'EOSQL' 2>/dev/null
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

success "Schema and tables created."

# ─── Create the overprivileged role ────────────────────────────────────────────
info "Creating role 'report_user' with excessive privileges..."

PGPASSWORD="$RDS_MASTER_PASSWORD" psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=financedb user=$RDS_MASTER_USER sslmode=require" << 'EOSQL' 2>/dev/null
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'report_user') THEN
    CREATE ROLE report_user WITH LOGIN PASSWORD 'ReportPass1!';
  ELSE
    ALTER ROLE report_user WITH LOGIN PASSWORD 'ReportPass1!';
  END IF;
END $$;

-- Connect access
GRANT CONNECT ON DATABASE financedb TO report_user;
GRANT USAGE ON SCHEMA finance TO report_user;

-- THE PROBLEM: report_user should only have SELECT on accounts and transactions
-- but was accidentally given ALL on everything
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA finance TO report_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA finance TO report_user;
GRANT CREATE ON SCHEMA finance TO report_user;
EOSQL

success "Role 'report_user' created with excessive privileges."

# ─── Save scenario state ───────────────────────────────────────────────────────
STATE_FILE="/tmp/tier2-scenario04-state.sh"
cat > "$STATE_FILE" << EOF
export SCENARIO04_ROLE="report_user"
export SCENARIO04_DB="financedb"
export SCENARIO04_SCHEMA="finance"
export SCENARIO04_INJECT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# The report_user role should ONLY have:
#   SELECT on finance.accounts
#   SELECT on finance.transactions
# It should NOT have access to audit_trail, internal_notes, or any write privileges
EOF

separator
warn "INJECTION COMPLETE - SECURITY AUDIT FINDING"
warn ""
warn "Situation:"
warn "  A quarterly security audit has just completed."
warn "  The audit found that the 'report_user' database role has excessive privileges."
warn "  This role is used by the BI reporting tool and should be read-only."
warn "  Instead, it has FULL read/write/delete access to ALL tables including"
warn "  confidential tables (audit_trail, internal_notes) it should not see at all."
warn ""
warn "Your job:"
warn "  1. Audit what 'report_user' can currently access"
warn "  2. Determine what it SHOULD be able to access"
warn "  3. Revoke the excessive privileges"
warn "  4. Grant only the correct privileges"
warn "  5. Verify the role cannot do what it should not be able to do"
warn ""
warn "Expected final state for report_user:"
warn "  finance.accounts     - SELECT only"
warn "  finance.transactions - SELECT only"
warn "  finance.audit_trail  - NO ACCESS"
warn "  finance.internal_notes - NO ACCESS"
warn "  No INSERT, UPDATE, DELETE, or CREATE on anything"
warn ""
warn "Runbook:  survive/04-overprivileged-role/runbook.md"
warn "Validate: bash survive/04-overprivileged-role/validate.sh"
separator
