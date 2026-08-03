#!/usr/bin/env bash
# survive/04-memory-pressure/validate.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

PASS=0
FAIL=0

echo "============================================"
echo "VALIDATE: Memory Pressure Recovery"
echo "============================================"
echo ""

# Check 1: No memory_hog sessions
echo -n "Check 1: No memory hog sessions... "
HOGS=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'memory_hog%';" | tr -d ' ')
if [[ "$HOGS" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($HOGS still running)"; FAIL=$((FAIL+1)); fi

# Check 2: Database is responsive
echo -n "Check 2: Database responsive... "
START=$(date +%s)
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT 1;" &>/dev/null
END=$(date +%s)
if [[ $((END - START)) -lt 2 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL (slow)"; FAIL=$((FAIL+1)); fi

# Check 3: No active queries older than 5 minutes
echo -n "Check 3: No long-running queries... "
LONG=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '5 minutes' AND pid != pg_backend_pid();" | tr -d ' ')
if [[ "$LONG" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($LONG queries)"; FAIL=$((FAIL+1)); fi

# Check 4: work_mem is at a safe level (not globally set to 256MB+)
echo -n "Check 4: work_mem at safe level... "
WM=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SHOW work_mem;" | tr -d ' ')
WM_KB=$(echo "$WM" | sed 's/MB/*1024/;s/GB/*1048576/;s/kB//' | bc 2>/dev/null || echo "0")
if [[ "$WM_KB" -le 131072 ]]; then echo "PASS (work_mem=$WM)"; PASS=$((PASS+1))
else echo "FAIL (work_mem=$WM - too high globally)"; FAIL=$((FAIL+1)); fi

echo ""
echo "============================================"
echo "VALIDATION SUMMARY"
echo "============================================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then echo "RESULT: PASS - Memory pressure resolved"; exit 0
else echo "RESULT: FAIL - $FAIL checks still failing"; exit 1; fi
