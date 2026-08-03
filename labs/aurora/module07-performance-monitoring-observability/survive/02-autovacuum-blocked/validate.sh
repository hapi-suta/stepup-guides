#!/usr/bin/env bash
# survive/02-autovacuum-blocked/validate.sh
# Validates that autovacuum blocked scenario has been resolved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then
    source "${SCRIPT_DIR}/../config.sh"
fi

: "${DB_ENDPOINT:?Set DB_ENDPOINT}"
: "${DB_PORT:=5432}"
: "${DB_USER:?Set DB_USER}"
: "${DB_NAME:?Set DB_NAME}"

PASS=0
FAIL=0

echo "============================================"
echo "VALIDATE: Autovacuum Blocked Recovery"
echo "============================================"
echo ""

# Check 1: Blocker transaction is gone
echo -n "Check 1: No blocking transaction... "
BLOCKERS=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE '%blocker%';" | tr -d ' ')

if [[ "$BLOCKERS" -eq 0 ]]; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL ($BLOCKERS blockers still active)"
    FAIL=$((FAIL + 1))
fi

# Check 2: Dead tuples below 10%
echo -n "Check 2: Dead tuples below 10%... "
DEAD_PCT=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) FROM pg_stat_user_tables WHERE relname = 'bloat_target';" 2>/dev/null | tr -d ' ')

if [[ -z "$DEAD_PCT" || "$DEAD_PCT" == "" ]]; then
    echo "PASS (table may have been dropped)"
    PASS=$((PASS + 1))
elif (( $(echo "$DEAD_PCT < 10" | bc -l) )); then
    echo "PASS (${DEAD_PCT}% dead)"
    PASS=$((PASS + 1))
else
    echo "FAIL (${DEAD_PCT}% dead - still bloated)"
    FAIL=$((FAIL + 1))
fi

# Check 3: No idle-in-transaction sessions older than 5 minutes
echo -n "Check 3: No old idle-in-transaction... "
STUCK=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction' AND now() - xact_start > interval '5 minutes';" | tr -d ' ')

if [[ "$STUCK" -eq 0 ]]; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL ($STUCK sessions stuck)"
    FAIL=$((FAIL + 1))
fi

# Check 4: Vacuum has run recently on bloat_target
echo -n "Check 4: Recent vacuum on bloat_target... "
LAST_VAC=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT CASE WHEN last_vacuum > now() - interval '30 minutes' OR last_autovacuum > now() - interval '30 minutes' THEN 'recent' ELSE 'stale' END FROM pg_stat_user_tables WHERE relname = 'bloat_target';" 2>/dev/null | tr -d ' ')

if [[ "$LAST_VAC" == "recent" || -z "$LAST_VAC" ]]; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (no recent vacuum)"
    FAIL=$((FAIL + 1))
fi

# Summary
echo ""
echo "============================================"
echo "VALIDATION SUMMARY"
echo "============================================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "RESULT: PASS - Autovacuum blocked scenario resolved"
    exit 0
else
    echo "RESULT: FAIL - $FAIL checks still failing"
    exit 1
fi
