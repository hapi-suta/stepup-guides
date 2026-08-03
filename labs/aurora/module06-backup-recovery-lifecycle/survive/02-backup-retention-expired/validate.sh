#!/usr/bin/env bash
# SURVIVE 02 - validate.sh
# Verifies billing_records is restored and retention is increased.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 02 - Validating Recovery"

resolve_cluster_host

PASS=0
FAIL=0

# --- Check 1: Table exists and has rows ---
ACTUAL_ROWS=$(run_sql "SELECT COUNT(*) FROM billing_records;" 2>/dev/null || echo "0")
EXPECTED_ROWS=$(cat "$SURVIVE_TMP/02_rowcount.txt" 2>/dev/null || echo "500")
if check_pass "billing_records row count" "$EXPECTED_ROWS" "$ACTUAL_ROWS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# --- Check 2: Checksum ---
EXPECTED_CHECKSUM=$(cat "$SURVIVE_TMP/02_checksum.txt" 2>/dev/null || echo "")
if [[ -n "$EXPECTED_CHECKSUM" ]]; then
    ACTUAL_CHECKSUM=$(run_sql "SELECT SUM(amount)::NUMERIC(12,2) FROM billing_records;")
    if check_pass "billing_records total amount checksum" "$EXPECTED_CHECKSUM" "$ACTUAL_CHECKSUM"; then
        (( PASS++ ))
    else
        (( FAIL++ ))
    fi
fi

# --- Check 3: Backup retention is increased ---
RETENTION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION" \
    --query 'DBClusters[0].BackupRetentionPeriod' \
    --output text)
if [[ "$RETENTION" -gt 1 ]]; then
    log_ok "Backup retention is increased: $RETENTION days"
    (( PASS++ ))
else
    log_fail "Backup retention is still 1 day - this must be increased."
    (( FAIL++ ))
fi

# --- Check 4: No orphaned restore clusters ---
RESTORED_RUNNING=$(aws rds describe-db-clusters \
    --region "$AWS_REGION" \
    --query "DBClusters[?contains(DBClusterIdentifier,'survive02')].DBClusterIdentifier" \
    --output text 2>/dev/null || echo "")
if [[ -z "$RESTORED_RUNNING" ]]; then
    log_ok "Cleanup: no survive02 restore clusters still running"
    (( PASS++ ))
else
    log_warn "Cleanup: restored cluster still running: $RESTORED_RUNNING"
    (( FAIL++ ))
fi

# --- Check 5: Primary cluster status ---
PRIMARY_STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION" \
    --query 'DBClusters[0].Status' \
    --output text)
if check_pass "Primary cluster status" "available" "$PRIMARY_STATUS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# --- Final Score ---
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
