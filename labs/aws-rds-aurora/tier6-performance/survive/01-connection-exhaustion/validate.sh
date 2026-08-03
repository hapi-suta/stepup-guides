#!/usr/bin/env bash
# survive/01-connection-exhaustion/validate.sh
# Validates that the connection exhaustion scenario has been resolved.

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "VALIDATE: Connection Exhaustion Recovery"

PASS_COUNT=0
FAIL_COUNT=0

# ---------------------------------------------------------------
# Check 1: Can we connect?
# ---------------------------------------------------------------
info "Check 1: Database connectivity"
if check_connectivity; then
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    fail "Cannot connect to database at all"
fi

# ---------------------------------------------------------------
# Check 2: Connection count is below 80% of max
# ---------------------------------------------------------------
info "Check 2: Connection count below 80% of max_connections"
MAX_CONN=$(psql_exec "SHOW max_connections" | tr -d ' ')
CURRENT_CONN=$(psql_exec "SELECT count(*) FROM pg_stat_activity")
THRESHOLD=$(( MAX_CONN * 80 / 100 ))

if [[ "$CURRENT_CONN" -lt "$THRESHOLD" ]]; then
    pass "Connection count: $CURRENT_CONN / $MAX_CONN (threshold: $THRESHOLD)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Connection count still high: $CURRENT_CONN / $MAX_CONN (threshold: $THRESHOLD)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# ---------------------------------------------------------------
# Check 3: No idle-in-transaction sessions older than 5 minutes
# ---------------------------------------------------------------
info "Check 3: No stale idle-in-transaction sessions"
STUCK_SESSIONS=$(psql_exec "SELECT count(*) FROM pg_stat_activity
    WHERE state = 'idle in transaction'
      AND now() - xact_start > interval '5 minutes'")

if [[ "$STUCK_SESSIONS" -eq 0 ]]; then
    pass "No stale idle-in-transaction sessions"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "$STUCK_SESSIONS idle-in-transaction sessions older than 5 minutes"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# ---------------------------------------------------------------
# Check 4: Normal queries execute within 1 second
# ---------------------------------------------------------------
info "Check 4: Query performance is normal"
START=$(date +%s%N)
psql_exec "SELECT count(*) FROM pg_stat_activity" > /dev/null
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))

if [[ "$ELAPSED_MS" -lt 1000 ]]; then
    pass "Simple query completed in ${ELAPSED_MS}ms"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Simple query took ${ELAPSED_MS}ms (expected < 1000ms)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# ---------------------------------------------------------------
# Check 5: Bonus - idle_session_timeout configured
# ---------------------------------------------------------------
info "Check 5 (bonus): idle_session_timeout configured"
IDLE_TIMEOUT=$(psql_exec "SHOW idle_session_timeout" | tr -d ' ')
if [[ "$IDLE_TIMEOUT" != "0" && "$IDLE_TIMEOUT" != "0ms" ]]; then
    pass "idle_session_timeout is set: $IDLE_TIMEOUT"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    warn "idle_session_timeout = 0 (not configured) - consider setting to 300000ms"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
section "VALIDATION SUMMARY"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    pass "SCENARIO RESOLVED - Connection exhaustion has been cleared"
    exit 0
else
    fail "SCENARIO NOT FULLY RESOLVED - $FAIL_COUNT checks still failing"
    exit 1
fi
