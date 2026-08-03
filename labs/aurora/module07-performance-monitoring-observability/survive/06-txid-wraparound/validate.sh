#!/usr/bin/env bash
# survive/06-txid-wraparound/validate.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

PASS=0
FAIL=0

echo "============================================"
echo "VALIDATE: TXID Wraparound Recovery"
echo "============================================"
echo ""

# Check 1: No txid_blocker sessions
echo -n "Check 1: No blocker sessions... "
BLOCKERS=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'txid_blocker%' OR application_name LIKE 'txid_burner%';" | tr -d ' ')
if [[ "$BLOCKERS" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($BLOCKERS still running)"; FAIL=$((FAIL+1)); fi

# Check 2: No long-running transactions (> 10 minutes)
echo -n "Check 2: No long-running transactions... "
LONG_TXN=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE xact_start IS NOT NULL AND now() - xact_start > interval '10 minutes' AND pid != pg_backend_pid();" | tr -d ' ')
if [[ "$LONG_TXN" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($LONG_TXN long transactions)"; FAIL=$((FAIL+1)); fi

# Check 3: XID age below 1.5 billion
echo -n "Check 3: XID age below 1.5B... "
XID_AGE=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT max(age(datfrozenxid)) FROM pg_database;" | tr -d ' ')
if [[ "$XID_AGE" -lt 1500000000 ]]; then echo "PASS (age: $XID_AGE)"; PASS=$((PASS+1))
else echo "FAIL (age: $XID_AGE - still too high)"; FAIL=$((FAIL+1)); fi

# Check 4: VACUUM has run on txid_test tables (if they exist)
echo -n "Check 4: Recent vacuum on test tables... "
VAC_COUNT=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_user_tables WHERE relname LIKE 'txid_test%' AND (last_vacuum > now() - interval '30 minutes' OR last_autovacuum > now() - interval '30 minutes');" 2>/dev/null | tr -d ' ')
TABLE_COUNT=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_user_tables WHERE relname LIKE 'txid_test%';" 2>/dev/null | tr -d ' ')
if [[ "$TABLE_COUNT" -eq 0 || "$VAC_COUNT" -gt 0 ]]; then echo "PASS"; PASS=$((PASS+1))
else echo "FAIL (vacuum not run on test tables)"; FAIL=$((FAIL+1)); fi

# Check 5: Database responsive
echo -n "Check 5: Database responsive... "
START=$(date +%s)
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT 1;" &>/dev/null
END=$(date +%s)
if [[ $((END - START)) -lt 2 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL (slow)"; FAIL=$((FAIL+1)); fi

echo ""
echo "============================================"
echo "VALIDATION SUMMARY"
echo "============================================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then echo "RESULT: PASS - TXID wraparound threat resolved"; exit 0
else echo "RESULT: FAIL - $FAIL checks still failing"; exit 1; fi
