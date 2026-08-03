#!/bin/bash
set -euo pipefail

# =============================================================================
# SURVIVE 03: Pipeline Deploys to Production - Validation Script
#
# Checks that the student successfully remediated the wrong-environment deploy.
# Each check prints PASS or FAIL.
# =============================================================================

AURORA_ENDPOINT="${AURORA_ENDPOINT:-localhost}"
DB_USER="${DB_USER:-postgres}"
DB_PROD="survive_production"

PASS=0
FAIL=0

check() {
    local description="$1"
    local query="$2"
    local expected="$3"

    result=$(psql -h "${AURORA_ENDPOINT}" -U "${DB_USER}" -d "${DB_PROD}" -tAc "${query}" 2>/dev/null || echo "ERROR")

    if [ "${result}" = "${expected}" ]; then
        echo "PASS: ${description}"
        PASS=$((PASS + 1))
    else
        echo "FAIL: ${description} (expected: ${expected}, got: ${result})"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== SURVIVE 03: Pipeline Deploys to Production - Validation ==="
echo ""

# Check 1: Production database exists
check "Production database exists" \
    "SELECT 1;" \
    "1"

# Check 2: Test table has been removed
check "test_load_data table does not exist" \
    "SELECT count(*) FROM information_schema.tables WHERE table_name = 'test_load_data' AND table_schema = 'public';" \
    "0"

# Check 3: Phone column has been re-added
check "Phone column exists on customers table" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name = 'customers' AND column_name = 'phone';" \
    "1"

# Check 4: Customer tiers are not all 'free'
check "Not all customers have tier='free' (tiers restored)" \
    "SELECT CASE WHEN count(DISTINCT tier) > 1 THEN 'true' ELSE 'false' END FROM customers;" \
    "true"

# Check 5: All 50,000 customers still exist
check "All 50,000 customers still exist" \
    "SELECT CASE WHEN count(*) >= 50000 THEN 'true' ELSE 'false' END FROM customers;" \
    "true"

# Check 6: All 200,000 orders still exist (no collateral damage)
check "All 200,000 orders still exist" \
    "SELECT CASE WHEN count(*) >= 200000 THEN 'true' ELSE 'false' END FROM orders;" \
    "true"

# Check 7: Schema matches staging (minus phone data)
check "Customers table has same column count as staging" \
    "SELECT count(*) FROM information_schema.columns WHERE table_name = 'customers';" \
    "6"

echo ""
echo "=== Results: ${PASS} PASS, ${FAIL} FAIL ==="

if [ "${FAIL}" -gt 0 ]; then
    echo "Some checks failed. Review the runbook and try again."
    exit 1
else
    echo "All checks passed. Scenario remediated successfully."
    exit 0
fi
