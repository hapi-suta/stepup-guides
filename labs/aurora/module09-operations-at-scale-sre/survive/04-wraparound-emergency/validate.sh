#!/bin/bash
# =============================================================================
# SURVIVE Scenario 04: Wraparound Emergency
# VALIDATE - Checks that the student has fixed the wraparound risk.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

echo ""
echo "========================================="
echo "  VALIDATING: Wraparound Emergency Fix"
echo "========================================="
echo ""

# ---------------------------------------------------------------------------
log_step 1 "Check no tables have autovacuum disabled"
# ---------------------------------------------------------------------------

DISABLED_COUNT=$(run_sql "
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND c.reloptions::text LIKE '%autovacuum_enabled=false%';
")

if [ "${DISABLED_COUNT}" -eq 0 ] 2>/dev/null; then
    log_success "PASS: No tables have autovacuum disabled"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: ${DISABLED_COUNT} table(s) still have autovacuum disabled"
    # Show which tables
    run_sql "
    SELECT n.nspname || '.' || c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND c.reloptions::text LIKE '%autovacuum_enabled=false%';
    "
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 2 "Check VACUUM has been run on test tables (if they still exist)"
# ---------------------------------------------------------------------------

TABLE_EXISTS=$(run_sql "SELECT count(*) FROM pg_tables WHERE tablename = 'm09_wraparound_test1';")

if [ "${TABLE_EXISTS}" -eq 0 ] 2>/dev/null; then
    log_success "PASS: Test tables have been dropped (cleanup complete)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    # Tables still exist - check if VACUUM was run
    DEAD_TUPLES=$(run_sql "
    SELECT COALESCE(sum(n_dead_tup), 0)
    FROM pg_stat_user_tables
    WHERE relname LIKE 'm09_wraparound%';
    ")

    if [ "${DEAD_TUPLES}" -lt 100 ] 2>/dev/null; then
        log_success "PASS: VACUUM completed - dead tuples cleaned (${DEAD_TUPLES} remaining)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_fail "FAIL: ${DEAD_TUPLES} dead tuples remaining - VACUUM not run or incomplete"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# ---------------------------------------------------------------------------
log_step 3 "Check database transaction age is healthy"
# ---------------------------------------------------------------------------

DB_AGE=$(run_sql "
SELECT age(datfrozenxid)
FROM pg_database
WHERE datname = '${M09_DB_NAME}';
")

if [ "${DB_AGE}" -lt 1000000000 ] 2>/dev/null; then
    log_success "PASS: Database age is healthy (${DB_AGE} - below 1 billion)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: Database age is ${DB_AGE} (above 1 billion threshold)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 4 "Check autovacuum is running system-wide"
# ---------------------------------------------------------------------------

AUTOVAC_SETTING=$(run_sql "SHOW autovacuum;")

if [ "${AUTOVAC_SETTING}" = "on" ]; then
    log_success "PASS: System-wide autovacuum is enabled"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: System-wide autovacuum is ${AUTOVAC_SETTING} (should be 'on')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 5 "Check test tables have autovacuum re-enabled (if they exist)"
# ---------------------------------------------------------------------------

if [ "${TABLE_EXISTS}" -gt 0 ] 2>/dev/null; then
    STILL_DISABLED=$(run_sql "
    SELECT count(*)
    FROM pg_class c
    WHERE c.relname LIKE 'm09_wraparound%'
      AND c.relkind = 'r'
      AND c.reloptions::text LIKE '%autovacuum_enabled=false%';
    ")

    if [ "${STILL_DISABLED}" -eq 0 ] 2>/dev/null; then
        log_success "PASS: All m09_wraparound tables have autovacuum re-enabled"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_fail "FAIL: ${STILL_DISABLED} test table(s) still have autovacuum disabled"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    log_success "PASS: Test tables cleaned up (dropped)"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_validation_summary
