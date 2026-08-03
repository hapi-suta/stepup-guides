#!/usr/bin/env bash
# SURVIVE 03 - validate.sh
# Verifies the upgrade rollback was successful.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 03 - Validating Upgrade Rollback"

resolve_cluster_host

PASS=0
FAIL=0

# --- Check 1: app_users table has expected rows ---
EXPECTED_USERS=$(cat "$SURVIVE_TMP/03_user_rowcount.txt" 2>/dev/null || echo "100")
ACTUAL_USERS=$(run_sql "SELECT COUNT(*) FROM app_users;" 2>/dev/null || echo "0")
if check_pass "app_users row count" "$EXPECTED_USERS" "$ACTUAL_USERS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# --- Check 2: app_config table has expected rows ---
EXPECTED_CONFIG=$(cat "$SURVIVE_TMP/03_config_count.txt" 2>/dev/null || echo "4")
ACTUAL_CONFIG=$(run_sql "SELECT COUNT(*) FROM app_config;" 2>/dev/null || echo "0")
if check_pass "app_config row count" "$EXPECTED_CONFIG" "$ACTUAL_CONFIG"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# --- Check 3: Cluster is available ---
PRIMARY_STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION" \
    --query 'DBClusters[0].Status' \
    --output text 2>/dev/null)
if check_pass "Primary cluster status" "available" "$PRIMARY_STATUS"; then
    (( PASS++ ))
else
    (( FAIL++ ))
fi

# --- Check 4: Backup retention is enabled ---
RETENTION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION" \
    --query 'DBClusters[0].BackupRetentionPeriod' \
    --output text)
if [[ "$RETENTION" -gt 1 ]]; then
    log_ok "Backup retention is configured: $RETENTION days"
    (( PASS++ ))
else
    log_fail "Backup retention is only $RETENTION day(s) - should be increased after rollback"
    (( FAIL++ ))
fi

# --- Check 5: No orphaned clusters ---
ORPHANS=$(aws rds describe-db-clusters \
    --region "$AWS_REGION" \
    --query "DBClusters[?contains(DBClusterIdentifier,'survive03') && Status=='available'].DBClusterIdentifier" \
    --output text 2>/dev/null || echo "")
if [[ -z "$ORPHANS" ]]; then
    log_ok "No orphaned survive03 clusters running"
    (( PASS++ ))
else
    log_warn "Orphaned clusters still running: $ORPHANS (delete when confirmed stable)"
fi

# --- Final Score ---
echo ""
log_section "RESULTS"
log_info "Checks passed: $PASS"
log_info "Checks failed: $FAIL"

if (( FAIL == 0 )); then
    log_ok "SURVIVE 03 COMPLETE - All checks passed."
else
    log_fail "SURVIVE 03 INCOMPLETE - $FAIL check(s) failed."
    exit 1
fi
