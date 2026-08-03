#!/usr/bin/env bash
# survive/04-memory-pressure/validate.sh

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "VALIDATE: Memory Pressure Recovery"

PASS_COUNT=0
FAIL_COUNT=0

# Check 1: No per-role work_mem override
info "Check 1: No per-role work_mem override"
ROLE_WM=$(psql_exec "
SELECT count(*) FROM pg_roles
WHERE rolconfig IS NOT NULL
  AND array_to_string(rolconfig, ',') LIKE '%work_mem%'")

if [[ "$ROLE_WM" -eq 0 ]]; then
    pass "No per-role work_mem overrides found"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "$ROLE_WM role(s) have work_mem set via ALTER ROLE"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 2: Global work_mem is 256MB or less
info "Check 2: Global work_mem is safe (256MB or less)"
WM_KB=$(psql_exec "SELECT setting FROM pg_settings WHERE name = 'work_mem'")
WM_MB=$(( WM_KB / 1024 ))

if [[ "$WM_MB" -le 256 ]]; then
    pass "Global work_mem = ${WM_MB}MB (safe)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Global work_mem = ${WM_MB}MB (too high - exceeds 256MB safety limit)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 3: FreeableMemory above 10% (check CloudWatch)
info "Check 3: FreeableMemory above 1GB"
FREE_MEM=$(get_cloudwatch_metric "FreeableMemory" "AWS/RDS" "Minimum" "300" 2>/dev/null || echo "")

if [[ -n "$FREE_MEM" && "$FREE_MEM" != "None" ]]; then
    FREE_MB=$(echo "$FREE_MEM / 1048576" | bc 2>/dev/null || echo "0")
    if (( FREE_MB > 1024 )); then
        pass "FreeableMemory: ${FREE_MB}MB (healthy)"
        PASS_COUNT=$(( PASS_COUNT + 1 ))
    else
        fail "FreeableMemory: ${FREE_MB}MB (still low - memory not recovered)"
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    fi
else
    warn "Could not read FreeableMemory from CloudWatch - check manually in console"
fi

# Check 4: No OOM-related queries still running
info "Check 4: No memory-intensive queries running"
MEM_QUERIES=$(psql_exec "
SELECT count(*) FROM pg_stat_activity
WHERE state = 'active'
  AND query LIKE '%generate_series%'
  AND pid != pg_backend_pid()")

if [[ "$MEM_QUERIES" -eq 0 ]]; then
    pass "No memory-intensive injected queries running"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "$MEM_QUERIES memory-intensive queries still running"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

section "VALIDATION SUMMARY"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    pass "SCENARIO RESOLVED - Memory pressure cleared and work_mem corrected"
    exit 0
else
    fail "SCENARIO NOT FULLY RESOLVED - $FAIL_COUNT checks still failing"
    exit 1
fi
