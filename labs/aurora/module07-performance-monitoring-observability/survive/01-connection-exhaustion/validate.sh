#!/usr/bin/env bash
# survive/01-connection-exhaustion/validate.sh
# Validates that connection exhaustion has been resolved.
# Idempotent: Yes - safe to run multiple times.

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
echo "VALIDATE: Connection Exhaustion Recovery"
echo "============================================"
echo ""

# Check 1: Can we connect?
echo -n "Check 1: Database connectivity... "
if psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL - Cannot connect to database"
    FAIL=$((FAIL + 1))
fi

# Check 2: Connection count below 80% of max
echo -n "Check 2: Connection count below 80%... "
MAX_CONN=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SHOW max_connections;" 2>/dev/null | tr -d ' ')
CURRENT=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
THRESHOLD=$((MAX_CONN * 80 / 100))

if [[ "$CURRENT" -lt "$THRESHOLD" ]]; then
    echo "PASS ($CURRENT / $MAX_CONN, threshold: $THRESHOLD)"
    PASS=$((PASS + 1))
else
    echo "FAIL ($CURRENT / $MAX_CONN, threshold: $THRESHOLD)"
    FAIL=$((FAIL + 1))
fi

# Check 3: No flood connections remaining
echo -n "Check 3: No flood connections... "
FLOOD=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'connection_flood%';" 2>/dev/null | tr -d ' ')

if [[ "$FLOOD" -eq 0 ]]; then
    echo "PASS (0 flood connections)"
    PASS=$((PASS + 1))
else
    echo "FAIL ($FLOOD flood connections remaining)"
    FAIL=$((FAIL + 1))
fi

# Check 4: No idle-in-transaction sessions older than 5 minutes
echo -n "Check 4: No stale idle-in-transaction... "
STUCK=$(psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction' AND now() - xact_start > interval '5 minutes';" 2>/dev/null | tr -d ' ')

if [[ "$STUCK" -eq 0 ]]; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL ($STUCK sessions stuck)"
    FAIL=$((FAIL + 1))
fi

# Check 5: Normal queries execute within 1 second
echo -n "Check 5: Query performance normal... "
START=$(date +%s)
psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t \
    -c "SELECT count(*) FROM pg_stat_activity;" &>/dev/null
END=$(date +%s)
ELAPSED=$((END - START))

if [[ "$ELAPSED" -lt 2 ]]; then
    echo "PASS (${ELAPSED}s)"
    PASS=$((PASS + 1))
else
    echo "FAIL (${ELAPSED}s - too slow)"
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
    echo "RESULT: PASS - Connection exhaustion resolved"
    exit 0
else
    echo "RESULT: FAIL - $FAIL checks still failing"
    exit 1
fi
