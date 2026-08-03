#!/usr/bin/env bash
# survive/02-autovacuum-blocked/validate.sh

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "VALIDATE: Autovacuum Blocked Recovery"

PASS_COUNT=0
FAIL_COUNT=0

# Check 1: Table dead tuples below 10%
info "Check 1: Dead tuples below 10%"
RESULT=$(psql_exec "
SELECT round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1)
FROM pg_stat_user_tables WHERE relname = 'bloat_target'")

if [[ -z "$RESULT" ]]; then
    warn "Table bloat_target not found - may have been dropped"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
elif (( $(echo "$RESULT < 10" | bc -l) )); then
    pass "Dead tuple percentage: ${RESULT}% (below 10% threshold)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Dead tuple percentage still high: ${RESULT}%"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 2: No long-running idle-in-transaction sessions (> 5 min)
info "Check 2: No stale idle-in-transaction sessions"
STUCK=$(psql_exec "SELECT count(*) FROM pg_stat_activity
    WHERE state = 'idle in transaction'
      AND now() - xact_start > interval '5 minutes'")

if [[ "$STUCK" -eq 0 ]]; then
    pass "No stale idle-in-transaction sessions"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "$STUCK sessions idle-in-transaction for > 5 minutes"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 3: Autovacuum has run recently on the table
info "Check 3: Autovacuum has run recently"
LAST_AV=$(psql_exec "SELECT last_autovacuum FROM pg_stat_user_tables WHERE relname = 'bloat_target'" 2>/dev/null || echo "")
if [[ -n "$LAST_AV" && "$LAST_AV" != "" ]]; then
    pass "Last autovacuum: $LAST_AV"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    # Manual vacuum also counts
    LAST_V=$(psql_exec "SELECT last_vacuum FROM pg_stat_user_tables WHERE relname = 'bloat_target'" 2>/dev/null || echo "")
    if [[ -n "$LAST_V" && "$LAST_V" != "" ]]; then
        pass "Last manual vacuum: $LAST_V"
        PASS_COUNT=$(( PASS_COUNT + 1 ))
    else
        warn "No vacuum recorded yet for bloat_target (may still be running)"
    fi
fi

# Check 4: idle_in_transaction_session_timeout configured
info "Check 4 (bonus): idle_in_transaction_session_timeout configured"
TIMEOUT=$(psql_exec "SHOW idle_in_transaction_session_timeout" | tr -d ' ')
if [[ "$TIMEOUT" != "0" && "$TIMEOUT" != "0ms" ]]; then
    pass "idle_in_transaction_session_timeout = $TIMEOUT"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    warn "idle_in_transaction_session_timeout not configured - consider setting to 60000ms"
fi

section "VALIDATION SUMMARY"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    pass "SCENARIO RESOLVED - Autovacuum is no longer blocked"
    exit 0
else
    fail "SCENARIO NOT FULLY RESOLVED - $FAIL_COUNT checks still failing"
    exit 1
fi
