#!/usr/bin/env bash
# survive/03-slow-query-cascade/validate.sh

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "VALIDATE: Slow Query Cascade Recovery"

PASS_COUNT=0
FAIL_COUNT=0

# Check 1: No long-running active queries (> 30 seconds)
info "Check 1: No long-running queries"
LONG_QUERIES=$(psql_exec "
SELECT count(*) FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '30 seconds'
  AND query NOT LIKE '%pg_stat_activity%'
  AND query NOT LIKE '%pg_sleep%'
  AND pid != pg_backend_pid()")

if [[ "$LONG_QUERIES" -eq 0 ]]; then
    pass "No long-running queries (> 30 seconds)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "$LONG_QUERIES queries running longer than 30 seconds"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 2: CPU is recoverable - simple query executes quickly
info "Check 2: Simple queries execute within 2 seconds"
START=$(date +%s%N)
psql_exec "SELECT count(*) FROM pg_stat_activity" > /dev/null
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))

if [[ "$ELAPSED_MS" -lt 2000 ]]; then
    pass "Simple query completed in ${ELAPSED_MS}ms"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Simple query took ${ELAPSED_MS}ms - database may still be under load"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 3: An index exists on cascade_orders(user_id)
info "Check 3: Index exists on cascade_orders(user_id)"
IDX_EXISTS=$(psql_exec "
SELECT count(*) FROM pg_indexes
WHERE tablename = 'cascade_orders'
  AND indexdef LIKE '%user_id%'" 2>/dev/null || echo "0")

if [[ "$IDX_EXISTS" -gt 0 ]]; then
    pass "Index on cascade_orders(user_id) found"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "No index on cascade_orders(user_id) - root cause not fixed"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 4: statement_timeout configured
info "Check 4 (bonus): statement_timeout configured"
STMT_TIMEOUT=$(psql_exec "SHOW statement_timeout" | tr -d ' ')
if [[ "$STMT_TIMEOUT" != "0" && "$STMT_TIMEOUT" != "0ms" ]]; then
    pass "statement_timeout = $STMT_TIMEOUT"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    warn "statement_timeout not configured - runaway queries can still saturate CPU"
fi

section "VALIDATION SUMMARY"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    pass "SCENARIO RESOLVED - CPU cascade cleared and root cause fixed"
    exit 0
else
    fail "SCENARIO NOT FULLY RESOLVED - $FAIL_COUNT checks still failing"
    exit 1
fi
