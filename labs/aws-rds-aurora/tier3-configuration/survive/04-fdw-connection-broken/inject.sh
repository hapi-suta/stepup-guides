#!/usr/bin/env bash
# SURVIVE 04 - FDW Connection Broken
# Inject: Corrupt the foreign server host to simulate the remote RDS instance
# becoming unreachable (hostname change, security group, endpoint rotation)
#
# INSTRUCTOR USE ONLY

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: Set PGPASSWORD environment variable before running inject.sh"
  exit 1
fi

section "SURVIVE 04 - Injecting Broken FDW Connection"

info "Ensuring postgres_fdw extension is installed..."
run_sql "CREATE EXTENSION IF NOT EXISTS postgres_fdw;" || true

info "Saving the current foreign server configuration (if any)..."
EXISTING_SERVERS=$(run_sql "SELECT srvname FROM pg_foreign_server;" 2>/dev/null || echo "")
info "Existing foreign servers: $EXISTING_SERVERS"

info "Creating a foreign server pointing to a VALID endpoint..."
# First, set up a working foreign server pointing back to the same instance
# (self-referential FDW to simulate remote connectivity)
run_sql "
DROP SERVER IF EXISTS remote_data_server CASCADE;
CREATE SERVER remote_data_server
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (
    host '$RDS_ENDPOINT',
    port '$RDS_PORT',
    dbname '$RDS_DBNAME'
  );
" || {
  warn "Could not create foreign server - extension may not be loaded. Continuing."
}

info "Creating user mapping..."
run_sql "
CREATE USER MAPPING IF NOT EXISTS FOR $RDS_USERNAME
  SERVER remote_data_server
  OPTIONS (
    user '$RDS_USERNAME',
    password '${PGPASSWORD}'
  );
" || true

info "Creating a test foreign table schema and importing..."
run_sql "
CREATE SCHEMA IF NOT EXISTS remote_source;
" || true

# Create a local table that the foreign table will "point to"
run_sql "
CREATE TABLE IF NOT EXISTS public.source_data (
  id      serial PRIMARY KEY,
  name    text NOT NULL,
  value   numeric
);
INSERT INTO public.source_data (name, value)
SELECT 'record_' || i, random() * 1000
FROM generate_series(1, 100) i
ON CONFLICT DO NOTHING;
" || true

run_sql "
DROP FOREIGN TABLE IF EXISTS remote_source.source_data;
CREATE FOREIGN TABLE remote_source.source_data (
  id    integer,
  name  text,
  value numeric
)
SERVER remote_data_server
OPTIONS (schema_name 'public', table_name 'source_data');
" || true

info "Verifying FDW works BEFORE breaking it..."
COUNT=$(run_sql "SELECT COUNT(*) FROM remote_source.source_data;" 2>/dev/null || echo "ERROR")
info "Pre-inject count: $COUNT"

echo ""
info "Now injecting the fault: corrupting the foreign server host..."
sleep 2

# Change the host to a non-existent endpoint - simulates endpoint rotation or SG change
run_sql "
ALTER SERVER remote_data_server
OPTIONS (SET host 'nonexistent-rds-endpoint.invalid.us-east-1.rds.amazonaws.com');
"

info "Verifying the connection is now broken..."
BROKEN_TEST=$(run_sql "SELECT COUNT(*) FROM remote_source.source_data;" 2>/dev/null || echo "CONNECTION_FAILED")
info "Post-inject test: $BROKEN_TEST"

echo ""
warn "=================================================================="
warn "INJECT COMPLETE"
warn "=================================================================="
warn "The foreign server 'remote_data_server' now points to a non-existent host."
warn ""
warn "Application error: 'could not connect to server \"remote_data_server\"'"
warn "Application error: 'server name lookup failure'"
warn ""
warn "Legitimate causes this simulates:"
warn "  - Remote RDS endpoint was rotated (rename or restore to new instance)"
warn "  - Security group rule was removed, blocking port 5432"
warn "  - Remote RDS instance was deleted and recreated"
warn "  - DNS change pointing to new endpoint"
warn ""
warn "SAVED CORRECT ENDPOINT: $RDS_ENDPOINT"
warn "Students need to figure out the correct endpoint and restore the server config."
warn ""
warn "Student scenario begins now."
warn "=================================================================="
