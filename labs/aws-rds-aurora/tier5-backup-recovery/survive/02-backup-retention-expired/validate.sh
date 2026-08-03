#!/usr/bin/env bash
# SURVIVE 02 - validate.sh
# Verifies billing_records is restored and backups are re-enabled.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 02 - Validating Recovery"

resolve_db_host

PASS=0
FAIL=0

# ─── Check 1: Table exists and has rows ───────────────────────────────────────
ACTUAL_ROWS=$(run_sql "SELECT COUNT(*) FROM billing_records;" 2>/dev/null || echo "0")
EXPECTED_ROWS=$(cat "$SURVIVE_TMP/02_rowcount.txt" 2>/dev/null || echo "500")
if check_pass "billing_records row count" "$EXPECTED_ROWS" "$ACTUAL_ROWS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# ─── Check 2: Checksum ───────────────────────────────────────────────────────
EXPECTED_CHECKSUM=$(cat "$SURVIVE_TMP/02_checksum.txt" 2>/dev/null || echo "")
if [[ -n "$EXPECTED_CHECKSUM" ]]; then
    ACTUAL_CHECKSUM=$(run_sql "SELECT SUM(amount)::NUMERIC(12,2) FROM billing_records;")
    if check_pass "billing_records total amount checksum" "$EXPECTED_CHECKSUM" "$ACTUAL_CHECKSUM"; then
        (( PASS++ ))
    else
        (( FAIL++ ))
    fi
fi

# ─── Check 3: Backup retention is re-enabled ──────────────────────────────────
RETENTION=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].BackupRetentionPeriod' \
    --output text)
if [[ "$RETENTION" -gt 0 ]]; then
    log_ok "Backup retention is enabled: $RETENTION days"
    (( PASS++ ))
else
    log_fail "Backup retention is still 0 - backups are disabled. This must be fixed."
    (( FAIL++ ))
fi

# ─── Check 4: No orphaned restore instances ──────────────────────────────────
RESTORED_RUNNING=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier,'survive02')].DBInstanceIdentifier" \
    --output text 2>/dev/null || echo "")
if [[ -z "$RESTORED_RUNNING" ]]; then
    log_ok "Cleanup: no survive02 restore instances still running"
    (( PASS++ ))
else
    log_warn "Cleanup: restored instance still running: $RESTORED_RUNNING"
    (( FAIL++ ))
fi

# ─── Check 5: Primary instance status ────────────────────────────────────────
PRIMARY_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE" \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)
if check_pass "Primary instance status" "available" "$PRIMARY_STATUS"; then
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
    log_ok "SURVIVE 02 COMPLETE - All checks passed."
else
    log_fail "SURVIVE 02 INCOMPLETE - $FAIL check(s) failed."
    exit 1
fi
