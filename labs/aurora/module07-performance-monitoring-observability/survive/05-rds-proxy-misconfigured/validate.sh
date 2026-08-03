#!/usr/bin/env bash
# survive/05-rds-proxy-misconfigured/validate.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../config.sh" ]]; then source "${SCRIPT_DIR}/../config.sh"; fi
: "${DB_ENDPOINT:?Set DB_ENDPOINT}" "${DB_PORT:=5432}" "${DB_USER:?Set DB_USER}" "${DB_NAME:?Set DB_NAME}"

PASS=0
FAIL=0

echo "============================================"
echo "VALIDATE: RDS Proxy Misconfigured Recovery"
echo "============================================"
echo ""

# Check 1: No pinned sessions remaining
echo -n "Check 1: No pinned sessions... "
PINNED=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'pinned_session%';" | tr -d ' ')
if [[ "$PINNED" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($PINNED pinned sessions)"; FAIL=$((FAIL+1)); fi

# Check 2: No stale advisory locks
echo -n "Check 2: No advisory locks... "
LOCKS=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory';" | tr -d ' ')
if [[ "$LOCKS" -eq 0 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($LOCKS advisory locks)"; FAIL=$((FAIL+1)); fi

# Check 3: Connection count is reasonable
echo -n "Check 3: Connection count reasonable... "
CONNS=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';" | tr -d ' ')
if [[ "$CONNS" -lt 50 ]]; then echo "PASS ($CONNS connections)"; PASS=$((PASS+1))
else echo "FAIL ($CONNS connections - still high)"; FAIL=$((FAIL+1)); fi

# Check 4: Database responsive
echo -n "Check 4: Database responsive... "
START=$(date +%s)
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT 1;" &>/dev/null
END=$(date +%s)
if [[ $((END - START)) -lt 2 ]]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; FAIL=$((FAIL+1)); fi

echo ""
echo "============================================"
echo "VALIDATION SUMMARY"
echo "============================================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then echo "RESULT: PASS - Proxy pinning resolved"; exit 0
else echo "RESULT: FAIL - $FAIL checks still failing"; exit 1; fi
