#!/bin/bash
set -euo pipefail

# =============================================================================
# SURVIVE 01: Migration Lock Timeout - Validation Script
#
# Checks that the student successfully resolved the lock timeout scenario.
# Each check prints PASS or FAIL.
# =============================================================================

AURORA_ENDPOINT="${AURORA_ENDPOINT:-localhost}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="survive_lock_timeout"

PASS=0
FAIL=0

check() {
    local description="$1"
    local query="$2"
    local expected="$3"

    result=$(psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc "${query}" 2>/dev/null || echo "ERROR")

    if [ "${result}" = "${expected}" ]; then
        echo "PASS: ${description}"
        PASS=$((PASS + 1))
    else
        echo "FAIL: ${description} (expected: ${expected}, got: ${result})"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== SURVIVE 01: Migration Lock Timeout - Validation ==="
echo ""

# Check 1: Database exists
check "Database survive_lock_timeout exists" \
    "SELECT 1;" \
    "1"

# Check 2: No blocked sessions
check "No sessions waiting on locks" \
    "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = '${DB_NAME}';" \
    "0"

# Check 3: Status column exists on transactions table
check "Column 'status' exists on transactions table" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name = 'transactions' AND column_name = 'status';" \
    "1"

# Check 4: Status column has correct default
check "Column 'status' has default value 'pending'" \
    "SELECT column_default FROM information_schema.columns WHERE table_name = 'transactions' AND column_name = 'status';" \
    "'pending'::character varying"

# Check 5: No long-running queries on the database
check "No queries running longer than 60 seconds" \
    "SELECT count(*) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND state = 'active' AND now() - query_start > interval '60 seconds' AND pid != pg_backend_pid();" \
    "0"

# Check 6: All 500,000 rows still exist (no data loss)
check "All 500,000 rows still exist in transactions table" \
    "SELECT CASE WHEN count(*) >= 500000 THEN 'true' ELSE 'false' END FROM transactions;" \
    "true"

echo ""
echo "=== Results: ${PASS} PASS, ${FAIL} FAIL ==="

if [ "${FAIL}" -gt 0 ]; then
    echo "Some checks failed. Review the runbook and try again."
    exit 1
else
    echo "All checks passed. Scenario resolved successfully."
    exit 0
fi
