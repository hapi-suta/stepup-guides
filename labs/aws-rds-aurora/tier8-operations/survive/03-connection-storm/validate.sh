#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 03: Validate - Connection Storm Resolved
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 03: Validation - Connection Storm"

t8_validate_config || exit 1
check_aws_auth || exit 1

PASS_COUNT=0
FAIL_COUNT=0

if [[ -f "${SCRIPT_DIR}/.inject-state" ]]; then
  source "${SCRIPT_DIR}/.inject-state"
fi

# -----------------------------------------------------------------------
# Check 1: Database is accessible
# -----------------------------------------------------------------------
log_step "Check 1: Database is accepting new connections"

if check_db_connectivity; then
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "Cannot connect to database."
  echo "  The connection storm may still be active."
  echo "  Try connecting as the superuser and terminating idle-in-transaction sessions."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 2: No idle-in-transaction sessions older than 5 minutes
# -----------------------------------------------------------------------
log_step "Check 2: No stale idle-in-transaction sessions"

IDLE_IN_TX=$(run_sql "
  SELECT count(*)
  FROM pg_stat_activity
  WHERE state = 'idle in transaction'
  AND now() - xact_start > interval '5 minutes';
" | tr -d ' ')

if [[ "${IDLE_IN_TX}" == "0" ]]; then
  validate_check "No idle-in-transaction sessions older than 5 minutes" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "No idle-in-transaction sessions older than 5 minutes" "fail" \
    "Found ${IDLE_IN_TX} stale idle-in-transaction sessions"
  echo "  Fix:"
  echo "  SELECT pg_terminate_backend(pid)"
  echo "  FROM pg_stat_activity"
  echo "  WHERE state = 'idle in transaction'"
  echo "  AND now() - xact_start > interval '5 minutes';"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 3: Connection count is below 80% of max_connections
# -----------------------------------------------------------------------
log_step "Check 3: Connection count is below 80% of max_connections"

CONN_DATA=$(run_sql "
  SELECT count(*) AS total,
         current_setting('max_connections')::int AS max_conn
  FROM pg_stat_activity;" | tr -d ' ')

TOTAL_CONN=$(run_sql "SELECT count(*) FROM pg_stat_activity;" | tr -d ' ')
MAX_CONN=$(run_sql "SHOW max_connections;" | tr -d ' ')
THRESHOLD=$(( MAX_CONN * 80 / 100 ))

if [[ ${TOTAL_CONN} -lt ${THRESHOLD} ]]; then
  validate_check "Connections (${TOTAL_CONN}) below 80% of max (${MAX_CONN})" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Connections (${TOTAL_CONN}) below 80% of max (${MAX_CONN})" "fail" \
    "Connection count is still high: ${TOTAL_CONN}/${MAX_CONN}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 4: max_connections is restored to a sane value
# -----------------------------------------------------------------------
log_step "Check 4: max_connections is restored to a reasonable value"

MAX_CONN_CURRENT=$(run_sql "SHOW max_connections;" | tr -d ' ')

if [[ ${MAX_CONN_CURRENT} -gt 50 ]]; then
  validate_check "max_connections restored to reasonable value: ${MAX_CONN_CURRENT}" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "max_connections is still at the injected value: ${MAX_CONN_CURRENT}" "fail" \
    "max_connections should be > 50. Original value was ${ORIGINAL_MAX_CONN:-unknown}"
  echo "  Fix: Modify the parameter group and reboot the instance to apply the change."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 5: idle_in_transaction_session_timeout is configured
# -----------------------------------------------------------------------
log_step "Check 5: idle_in_transaction_session_timeout is configured"

IDLE_TIMEOUT=$(run_sql "SHOW idle_in_transaction_session_timeout;" | tr -d ' ')

if [[ "${IDLE_TIMEOUT}" != "0" ]]; then
  validate_check "idle_in_transaction_session_timeout is set: ${IDLE_TIMEOUT}" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "idle_in_transaction_session_timeout is not configured" "fail" \
    "Current value: 0 (disabled)"
  echo "  This setting prevents future connection storms caused by stuck transactions."
  echo "  Set it to 300000 (5 minutes) in your parameter group."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Cleanup background processes from inject
# -----------------------------------------------------------------------
if [[ -n "${CONN_PIDS[*]:-}" ]]; then
  log_info "Terminating inject background processes..."
  for pid in "${CONN_PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
fi

if [[ ${FAIL_COUNT} -eq 0 ]]; then
  rm -f "${SCRIPT_DIR}/.inject-state"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "==========================================="
echo "VALIDATION SUMMARY"
echo "==========================================="
echo "Checks passed:  ${PASS_COUNT}"
echo "Checks failed:  ${FAIL_COUNT}"
echo ""

if [[ ${FAIL_COUNT} -eq 0 ]]; then
  log_success "Scenario 03 RESOLVED: All checks pass."
  echo ""
  echo "What you demonstrated:"
  echo "  - Diagnosed connection exhaustion using pg_stat_activity"
  echo "  - Terminated stale idle-in-transaction connections"
  echo "  - Restored max_connections to a valid value"
  echo "  - Configured idle_in_transaction_session_timeout as a safeguard"
else
  log_fail "Scenario 03 NOT FULLY RESOLVED: ${FAIL_COUNT} check(s) still failing."
fi
echo ""
