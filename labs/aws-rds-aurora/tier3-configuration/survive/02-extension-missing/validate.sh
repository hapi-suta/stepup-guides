#!/usr/bin/env bash
# SURVIVE 02 - Validate extension recovery

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: Set PGPASSWORD environment variable before running validate.sh"
  exit 1
fi

section "SURVIVE 02 - Validating Extension Recovery"

# -------------------------------------------------------
# Check 1: pg_stat_statements is installed
# -------------------------------------------------------
info "Checking pg_stat_statements extension..."
EXT_VERSION=$(run_sql "SELECT installed_version FROM pg_available_extensions WHERE name = 'pg_stat_statements'" 2>/dev/null | tr -d '[:space:]')
if [[ -n "$EXT_VERSION" && "$EXT_VERSION" != "NULL" ]]; then
  success "pg_stat_statements is installed (version: $EXT_VERSION)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "pg_stat_statements is NOT installed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: pg_stat_statements view is queryable
# -------------------------------------------------------
info "Checking pg_stat_statements is queryable..."
QUERY_COUNT=$(run_sql "SELECT COUNT(*) FROM pg_stat_statements" 2>/dev/null | tr -d '[:space:]')
if [[ "$QUERY_COUNT" =~ ^[0-9]+$ ]]; then
  success "pg_stat_statements view is queryable (rows: $QUERY_COUNT)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "Cannot query pg_stat_statements (error or not accessible)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: app_slow_queries view exists
# -------------------------------------------------------
info "Checking app_slow_queries view..."
VIEW_EXISTS=$(run_sql "SELECT COUNT(*) FROM pg_views WHERE viewname = 'app_slow_queries'" 2>/dev/null | tr -d '[:space:]')
if [[ "$VIEW_EXISTS" == "1" ]]; then
  success "app_slow_queries view exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "app_slow_queries view does not exist - needs to be recreated"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: app_slow_queries view is queryable (not broken)
# -------------------------------------------------------
info "Checking app_slow_queries view is functional..."
VIEW_QUERY=$(run_sql "SELECT COUNT(*) FROM app_slow_queries" 2>/dev/null | tr -d '[:space:]')
if [[ "$VIEW_QUERY" =~ ^[0-9]+$ ]]; then
  success "app_slow_queries view is functional (rows: $VIEW_QUERY)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "app_slow_queries view is broken (query failed)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: refresh_query_log procedure exists
# -------------------------------------------------------
info "Checking refresh_query_log procedure..."
PROC_EXISTS=$(run_sql "SELECT COUNT(*) FROM pg_proc WHERE proname = 'refresh_query_log'" 2>/dev/null | tr -d '[:space:]')
if [[ "$PROC_EXISTS" == "1" ]]; then
  success "refresh_query_log procedure exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "refresh_query_log procedure does not exist - needs to be recreated"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: procedure executes without error
# -------------------------------------------------------
info "Testing refresh_query_log procedure execution..."
CALL_RESULT=$(run_sql "CALL refresh_query_log();" 2>&1)
if [[ "$CALL_RESULT" != *"ERROR"* ]]; then
  success "refresh_query_log() executes without errors"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "refresh_query_log() failed: $CALL_RESULT"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 7: pg_stat_statements tracks new queries
# -------------------------------------------------------
info "Verifying pg_stat_statements is tracking queries..."
# Reset to get a clean baseline
run_sql "SELECT pg_stat_statements_reset();" > /dev/null 2>&1 || true
# Run a distinctive query
run_sql "SELECT 'tier3_survive_02_test_marker' AS marker;" > /dev/null 2>&1

# Check if it was tracked
TRACKED=$(run_sql "SELECT COUNT(*) FROM pg_stat_statements WHERE query LIKE '%tier3_survive_02_test_marker%'" 2>/dev/null | tr -d '[:space:]')
if [[ "$TRACKED" == "1" ]]; then
  success "pg_stat_statements is actively tracking queries"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "pg_stat_statements is not tracking queries - check pg_stat_statements.track parameter"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

print_summary
