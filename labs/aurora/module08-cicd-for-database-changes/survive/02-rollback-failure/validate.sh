#!/bin/bash
set -euo pipefail

# =============================================================================
# SURVIVE 02: Rollback Failure - Validation Script
#
# Checks that the student successfully resolved the partial migration.
# Each check prints PASS or FAIL.
# =============================================================================

AURORA_ENDPOINT="${AURORA_ENDPOINT:-localhost}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="survive_rollback_failure"

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

echo "=== SURVIVE 02: Rollback Failure - Validation ==="
echo ""

# Check 1: Database exists
check "Database survive_rollback_failure exists" \
    "SELECT 1;" \
    "1"

# Check 2: All 1,000,000 rows still exist
check "All 1,000,000 rows exist in customers table" \
    "SELECT CASE WHEN count(*) >= 1000000 THEN 'true' ELSE 'false' END FROM customers;" \
    "true"

# Check 3: No NULL loyalty_tier values
check "No rows have NULL loyalty_tier" \
    "SELECT count(*) FROM customers WHERE loyalty_tier IS NULL;" \
    "0"

# Check 4: All loyalty_tier values are valid
check "All loyalty_tier values are bronze, silver, or gold" \
    "SELECT count(*) FROM customers WHERE loyalty_tier NOT IN ('bronze', 'silver', 'gold');" \
    "0"

# Check 5: NOT NULL constraint (or CHECK equivalent) exists and is validated
check "CHECK constraint on loyalty_tier is validated" \
    "SELECT count(*) FROM pg_constraint WHERE conrelid = 'customers'::regclass AND conname = 'chk_loyalty_tier_nn' AND convalidated = true;" \
    "1"

# Check 6: No failed entries in flyway_schema_history
check "No failed entries in flyway_schema_history" \
    "SELECT count(*) FROM flyway_schema_history WHERE success = false;" \
    "0"

# Check 7: V2 is recorded as successful
check "V2 migration recorded as successful" \
    "SELECT count(*) FROM flyway_schema_history WHERE version = '2' AND success = true;" \
    "1"

echo ""
echo "=== Results: ${PASS} PASS, ${FAIL} FAIL ==="

if [ "${FAIL}" -gt 0 ]; then
    echo "Some checks failed. Review the runbook and try again."
    exit 1
else
    echo "All checks passed. Scenario resolved successfully."
    exit 0
fi
