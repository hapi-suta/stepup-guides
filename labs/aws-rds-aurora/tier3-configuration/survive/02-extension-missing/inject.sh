#!/usr/bin/env bash
# SURVIVE 02 - Extension Missing
# Inject: Drop an extension that the application depends on
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

section "SURVIVE 02 - Injecting Missing Extension"

info "First, ensuring pg_stat_statements is installed (setting up the dependency)..."
run_sql "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" || true

info "Creating application table that depends on pg_stat_statements..."
run_sql "
CREATE TABLE IF NOT EXISTS app_query_log (
  id          serial PRIMARY KEY,
  captured_at timestamptz DEFAULT now(),
  query_text  text,
  avg_ms      numeric
);
"

info "Creating a view that depends on pg_stat_statements..."
run_sql "
CREATE OR REPLACE VIEW app_slow_queries AS
SELECT
  LEFT(query, 200) AS query_text,
  calls,
  round(mean_exec_time::numeric, 2) AS avg_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 50;
"

info "Verifying the view works before injection..."
RESULT=$(run_sql "SELECT COUNT(*) FROM app_slow_queries;")
info "app_slow_queries view returns $RESULT rows"

info "Creating a stored procedure that calls the view..."
run_sql "
CREATE OR REPLACE PROCEDURE refresh_query_log()
LANGUAGE plpgsql
AS \$\$
BEGIN
  INSERT INTO app_query_log (query_text, avg_ms)
  SELECT query_text, avg_ms
  FROM app_slow_queries
  WHERE avg_ms > 100;
END;
\$\$;
"

echo ""
info "Setup complete. Now injecting the fault..."
sleep 2

info "Dropping pg_stat_statements extension..."
run_sql "DROP EXTENSION pg_stat_statements CASCADE;" || {
  warn "DROP EXTENSION failed (may require superuser). Trying alternative..."
  # On RDS, rdsadmin can drop extensions; try a workaround
  run_sql "DROP VIEW IF EXISTS app_slow_queries CASCADE;" || true
  run_sql "DROP EXTENSION IF EXISTS pg_stat_statements;" || true
}

info "Verifying extension is gone..."
EXT_STATUS=$(run_sql "SELECT installed_version FROM pg_available_extensions WHERE name = 'pg_stat_statements'")
info "pg_stat_statements installed_version: '$EXT_STATUS'"

echo ""
warn "=================================================================="
warn "INJECT COMPLETE"
warn "=================================================================="
warn "pg_stat_statements has been dropped."
warn "The app_slow_queries view is now broken (depends on missing extension)."
warn "The refresh_query_log() procedure will fail when called."
warn ""
warn "Application error: 'relation pg_stat_statements does not exist'"
warn ""
warn "Student scenario begins now."
warn "=================================================================="
