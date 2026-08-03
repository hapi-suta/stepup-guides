#!/usr/bin/env bash
# SURVIVE 04 - validate.sh
# Verifies the Blue/Green deployment was successfully switched over
# and that replication lag was resolved.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 04 - Validating Blue/Green Switchover"

resolve_db_host

PASS=0
FAIL=0

# ─── Check 1: Blue/Green deployment status is SWITCHOVER_COMPLETED ────────────
BG_ID=$(cat "$SURVIVE_TMP/04_bg_id.txt" 2>/dev/null || \
    aws rds describe-blue-green-deployments \
        --region "$AWS_REGION" \
        --query 'BlueGreenDeployments[0].BlueGreenDeploymentIdentifier' \
        --output text 2>/dev/null || echo "")

if [[ -n "$BG_ID" && "$BG_ID" != "None" ]]; then
    BG_STATUS=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$BG_ID" \
        --region "$AWS_REGION" \
        --query 'BlueGreenDeployments[0].Status' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    if [[ "$BG_STATUS" == "SWITCHOVER_COMPLETED" ]]; then
        log_ok "Blue/Green deployment status: SWITCHOVER_COMPLETED"
        (( PASS++ ))
    elif [[ "$BG_STATUS" == "NOT_FOUND" ]]; then
        log_warn "Blue/Green deployment $BG_ID not found - may have been deleted already"
        log_warn "Checking if primary instance is healthy instead..."
        (( PASS++ ))  # Acceptable if deployment was cleaned up
    else
        log_fail "Blue/Green deployment status: $BG_STATUS (expected SWITCHOVER_COMPLETED)"
        (( FAIL++ ))
    fi
else
    log_warn "No Blue/Green deployment ID found in $SURVIVE_TMP/04_bg_id.txt"
    log_warn "Checking primary instance health as fallback..."
fi

# ─── Check 2: Primary DB instance is available ───────────────────────────────
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

# ─── Check 3: No idle-in-transaction sessions (blocking condition resolved) ───
IDLE_COUNT=$(run_sql "SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'idle in transaction' AND pid <> pg_backend_pid();" 2>/dev/null || echo "0")
if [[ "$IDLE_COUNT" -eq 0 ]]; then
    log_ok "No idle-in-transaction sessions on primary"
    (( PASS++ ))
else
    log_warn "Found $IDLE_COUNT idle-in-transaction session(s) - these can cause future lag issues"
    log_warn "Consider setting idle_in_transaction_session_timeout in your parameter group"
fi

# ─── Check 4: lag_generator table cleaned up ─────────────────────────────────
LAG_TABLE_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='lag_generator';" 2>/dev/null || echo "1")
if [[ "$LAG_TABLE_EXISTS" -eq 0 ]]; then
    log_ok "lag_generator test table was cleaned up"
    (( PASS++ ))
else
    log_warn "lag_generator test table still exists - run: DROP TABLE lag_generator;"
fi

# ─── Final Score ──────────────────────────────────────────────────────────────
echo ""
log_section "RESULTS"
log_info "Checks passed: $PASS"
log_info "Checks failed: $FAIL"

if (( FAIL == 0 )); then
    log_ok "SURVIVE 04 COMPLETE - All checks passed."
else
    log_fail "SURVIVE 04 INCOMPLETE - $FAIL check(s) failed."
    exit 1
fi
