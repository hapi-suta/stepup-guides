#!/usr/bin/env bash
# survive/06-txid-wraparound/validate.sh

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "VALIDATE: TXID Wraparound Recovery"

PASS_COUNT=0
FAIL_COUNT=0

# Check 1: wraparound_risk table XID age below 10M
info "Check 1: Table XID age below 10 million"
XID_AGE=$(psql_exec "
SELECT age(relfrozenxid) FROM pg_class WHERE relname = 'wraparound_risk'" 2>/dev/null || echo "TABLE_NOT_FOUND")

if [[ "$XID_AGE" == "TABLE_NOT_FOUND" ]]; then
    pass "Table wraparound_risk does not exist (may have been cleaned up)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
elif [[ "$XID_AGE" -lt 10000000 ]]; then
    pass "Table XID age: $XID_AGE (below 10M threshold)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Table XID age: $XID_AGE (VACUUM FREEZE has not been run)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 2: Database-level max XID age below 500M
info "Check 2: Database max XID age below 500 million"
DB_XID_AGE=$(psql_exec "SELECT max(age(datfrozenxid)) FROM pg_database")

if [[ "$DB_XID_AGE" -lt 500000000 ]]; then
    pass "Database max XID age: $DB_XID_AGE (safe)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Database max XID age: $DB_XID_AGE (still elevated)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 3: No blocking long-running transactions
info "Check 3: No blocking transactions older than 5 minutes"
OLD_TXN=$(psql_exec "
SELECT count(*) FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
  AND state IN ('idle in transaction', 'active')
  AND query LIKE '%pg_sleep%'")

if [[ "$OLD_TXN" -eq 0 ]]; then
    pass "No blocking transactions found"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "$OLD_TXN long-running transactions still present (may block future freezes)"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Check 4: CloudWatch alarm configured for TXID wraparound
info "Check 4: TXID wraparound alarm configured"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "RDS-TXID" \
    --query "length(MetricAlarms)" \
    --output text --region "$REGION" 2>/dev/null || echo "0")

if [[ "$ALARM_COUNT" -gt 0 ]]; then
    pass "TXID wraparound alarm configured"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    warn "No TXID wraparound alarm found - set one up (see Build 01)"
fi

# Check 5: Database is not in restricted mode
info "Check 5: Database is not in restricted mode"
READ_ONLY=$(psql_exec "SELECT current_setting('transaction_read_only')")

if [[ "$READ_ONLY" == "off" || "$READ_ONLY" == "false" ]]; then
    pass "Database is writable (not in restricted mode)"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
else
    fail "Database is in read-only mode - wraparound protection may still be active"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

section "VALIDATION SUMMARY"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    pass "SCENARIO RESOLVED - TXID wraparound risk has been eliminated"
    exit 0
else
    fail "SCENARIO NOT FULLY RESOLVED - $FAIL_COUNT checks still failing"
    exit 1
fi
