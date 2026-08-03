#!/usr/bin/env bash
# SURVIVE 01 - validate.sh
# Verifies the student has successfully recovered critical_orders.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 01 - Validating Recovery"

resolve_db_host

PASS=0
FAIL=0

# ─── Check 1: Table exists ────────────────────────────────────────────────────
TABLE_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='critical_orders';")
if check_pass "Table critical_orders exists" "1" "$TABLE_EXISTS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
    log_fail "Recovery incomplete: table does not exist on production."
    echo ""
    echo "SCORE: $PASS checks passed, $FAIL failed."
    exit 1
fi

# ─── Check 2: Row count ───────────────────────────────────────────────────────
EXPECTED_ROWS=$(cat "$SURVIVE_TMP/01_rowcount.txt" 2>/dev/null || echo "1000")
ACTUAL_ROWS=$(run_sql "SELECT COUNT(*) FROM critical_orders;")
if check_pass "Row count matches (expected $EXPECTED_ROWS)" "$EXPECTED_ROWS" "$ACTUAL_ROWS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# ─── Check 3: Checksum ───────────────────────────────────────────────────────
EXPECTED_CHECKSUM=$(cat "$SURVIVE_TMP/01_checksum.txt" 2>/dev/null || echo "")
ACTUAL_CHECKSUM=$(run_sql "SELECT SUM(order_total)::NUMERIC(12,2) FROM critical_orders;")
if [[ -n "$EXPECTED_CHECKSUM" ]]; then
    if check_pass "Order total checksum matches" "$EXPECTED_CHECKSUM" "$ACTUAL_CHECKSUM"; then
        (( PASS++ ))
    else
        (( FAIL++ ))
    fi
else
    log_warn "Pre-inject checksum not found in $SURVIVE_TMP - skipping checksum check"
fi

# ─── Check 4: No orphaned restored instance ──────────────────────────────────
RESTORED_RUNNING=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier,'survive01')].DBInstanceIdentifier" \
    --output text 2>/dev/null || echo "")
if [[ -z "$RESTORED_RUNNING" ]]; then
    log_ok "Cleanup: no survive01 restore instances still running"
    (( PASS++ ))
else
    log_warn "Cleanup: restored instance still running: $RESTORED_RUNNING (remember to delete it)"
    (( FAIL++ ))
fi

# ─── Check 5: Primary instance still running ─────────────────────────────────
PRIMARY_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null)
if check_pass "Primary instance is available" "available" "$PRIMARY_STATUS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# ─── Final Score ──────────────────────────────────────────────────────────────
echo ""
log_section "RESULTS"
log_info "Checks passed: $PASS"
log_info "Checks failed: $FAIL"

if (( FAIL == 0 )); then
    log_ok "SURVIVE 01 COMPLETE - All checks passed."
else
    log_fail "SURVIVE 01 INCOMPLETE - $FAIL check(s) failed."
    exit 1
fi
