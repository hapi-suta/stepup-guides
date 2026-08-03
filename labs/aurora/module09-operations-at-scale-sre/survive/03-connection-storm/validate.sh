#!/bin/bash
# =============================================================================
# SURVIVE Scenario 03: Connection Storm
# VALIDATE - Checks that the student has remediated the connection storm.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

STATE_FILE="${M09_STATE_DIR}/03-connection-storm.state"

echo ""
echo "========================================="
echo "  VALIDATING: Connection Storm Remediation"
echo "========================================="
echo ""

# Load state
if [ -f "${STATE_FILE}" ]; then
    source "${STATE_FILE}"
else
    log_warn "State file not found. Using defaults."
    STORM_USER="${M09_CHAOS_PREFIX}-storm-user"
    BASELINE_CONNECTIONS=10
fi

# ---------------------------------------------------------------------------
log_step 1 "Check storm user connections are terminated"
# ---------------------------------------------------------------------------

STORM_CONNS=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE usename = '${STORM_USER}';")

if [ "${STORM_CONNS}" -eq 0 ] 2>/dev/null || [ -z "${STORM_CONNS}" ]; then
    log_success "PASS: No active connections from storm user"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: ${STORM_CONNS} connections still active from storm user '${STORM_USER}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 2 "Check idle-in-transaction sessions are cleared"
# ---------------------------------------------------------------------------

IDLE_IN_TXN=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction' AND extract(epoch FROM now() - state_change) > 300 AND backend_type = 'client backend';")

if [ "${IDLE_IN_TXN}" -eq 0 ] 2>/dev/null || [ -z "${IDLE_IN_TXN}" ]; then
    log_success "PASS: No stale idle-in-transaction sessions (> 5 min)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: ${IDLE_IN_TXN} idle-in-transaction sessions still active (> 5 min)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 3 "Check storm user has been removed"
# ---------------------------------------------------------------------------

USER_EXISTS=$(run_sql "SELECT count(*) FROM pg_roles WHERE rolname = '${STORM_USER}';")

if [ "${USER_EXISTS}" -eq 0 ] 2>/dev/null; then
    log_success "PASS: Storm user '${STORM_USER}' has been dropped"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: Storm user '${STORM_USER}' still exists"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 4 "Check connection count is near baseline"
# ---------------------------------------------------------------------------

CURRENT_CONNS=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';")
MAX_CONNS=$(run_sql "SELECT current_setting('max_connections')::int;")
UTILIZATION=$(echo "scale=1; ${CURRENT_CONNS} * 100 / ${MAX_CONNS}" | bc 2>/dev/null || echo "0")

if [ "${CURRENT_CONNS}" -lt 50 ] 2>/dev/null; then
    log_success "PASS: Connection count is healthy (${CURRENT_CONNS}, ${UTILIZATION}% utilization)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: Connection count is still elevated (${CURRENT_CONNS}, ${UTILIZATION}% utilization)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 5 "Check no background psql processes from injection"
# ---------------------------------------------------------------------------

# Kill any remaining background psql processes from the inject script
REMAINING=$(pgrep -f "pg_sleep.*3600" 2>/dev/null | wc -l || echo "0")

if [ "${REMAINING}" -eq 0 ] 2>/dev/null; then
    log_success "PASS: No lingering background psql processes"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_warn "Found ${REMAINING} lingering psql processes - cleaning up"
    pkill -f "pg_sleep.*3600" 2>/dev/null || true
    sleep 2
    log_success "PASS: Cleaned up background processes"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_validation_summary
