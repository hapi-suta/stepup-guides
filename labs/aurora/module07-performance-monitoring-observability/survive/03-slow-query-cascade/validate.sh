#!/usr/bin/env bash
# survive/03-slow-query-cascade/validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

PASS=0
FAIL=0

echo "============================================"
echo "VALIDATE: Slow Query Cascade Recovery"
echo "============================================"
echo ""

# Check 1: No slow_cascade queries running
echo -n "Check 1: No cascade queries running... "
CASCADE=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'slow_cascade%';" | tr -d ' ')
if [[ "$CASCADE" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($CASCADE still running)"; FAIL=$((FAIL+1)); fi

# Check 2: No long-running active queries (> 2 minutes)
echo -n "Check 2: No long-running queries... "
LONG=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '2 minutes' AND pid != pg_backend_pid();" | tr -d ' ')
if [[ "$LONG" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($LONG queries > 2 min)"; FAIL=$((FAIL+1)); fi

# Check 3: Simple query executes quickly
echo -n "Check 3: Simple query performance... "
START=$(date +%s)
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT 1;" &>/dev/null
END=$(date +%s)
ELAPSED=$((END - START))
if [[ "$ELAPSED" -lt 2 ]]; then echo "PASS (${ELAPSED}s)"; PASS=$((PASS+1)); else echo "FAIL (${ELAPSED}s)"; FAIL=$((FAIL+1)); fi

# Check 4: Active session count is reasonable (< 20)
echo -n "Check 4: Active sessions reasonable... "
ACTIVE=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND pid != pg_backend_pid();" | tr -d ' ')
if [[ "$ACTIVE" -lt 20 ]]; then echo "PASS ($ACTIVE active)"; PASS=$((PASS+1)); else echo "FAIL ($ACTIVE active)"; FAIL=$((FAIL+1)); fi

echo ""
echo "============================================"
echo "VALIDATION SUMMARY"
echo "============================================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then echo "RESULT: PASS - Slow query cascade resolved"; exit 0
else echo "RESULT: FAIL - $FAIL checks still failing"; exit 1; fi
