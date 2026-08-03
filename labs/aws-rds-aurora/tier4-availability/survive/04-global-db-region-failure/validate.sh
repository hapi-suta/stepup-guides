#!/usr/bin/env bash
# SURVIVE 04 - validate.sh
# Verifies the student successfully promoted the secondary Global Database cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

log_section "SURVIVE 04 - Global Database Region Failure Validation"

# -------------------------------------------------------
# Check 1: Secondary cluster is in available status
# -------------------------------------------------------
log_info "Check 1: Secondary cluster ($AURORA_CLUSTER_ID in $AWS_SECONDARY_REGION) is available"
STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier my-global-secondary \
    --query 'DBClusters[0].Status' \
    --output text \
    --region "$AWS_SECONDARY_REGION" 2>/dev/null)

if [ "$STATUS" = "available" ]; then
    log_success "PASS: Secondary cluster status is 'available'"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Secondary cluster status is '$STATUS' (expected 'available')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Secondary is no longer in recovery mode (it is now read-write)
# -------------------------------------------------------
log_info "Check 2: Secondary cluster is now in read-write mode"
IS_RECOVERY=$(run_query "$AURORA_SECONDARY_ENDPOINT" "SELECT pg_is_in_recovery();" "$DB_USER" "$DB_NAME")

if [ "$IS_RECOVERY" = "f" ]; then
    log_success "PASS: Secondary cluster is now read-write (pg_is_in_recovery = f)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Secondary cluster is still in recovery mode (pg_is_in_recovery = $IS_RECOVERY)"
    log_error "      The detach-and-promote may not have completed."
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: Can write to the secondary cluster
# -------------------------------------------------------
log_info "Check 3: Write operation succeeds on secondary cluster"
WRITE_RESULT=$(psql -h "$AURORA_SECONDARY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    --connect-timeout=5 \
    -t -c "INSERT INTO global_test (region, message) VALUES ('us-west-2', 'survive-04-validation') RETURNING id;" \
    2>&1 | tr -d ' \n')

if echo "$WRITE_RESULT" | grep -qE '^[0-9]+$'; then
    log_success "PASS: Write succeeded on secondary (id: $WRITE_RESULT)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Write failed on secondary ($WRITE_RESULT)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: Secondary is detached from the Global Database
# -------------------------------------------------------
log_info "Check 4: Secondary is no longer part of the Global Database"
MEMBER_COUNT=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'length(GlobalClusters[0].GlobalClusterMembers)' \
    --output text \
    --region "$AWS_PRIMARY_REGION" 2>/dev/null)

if [ "$MEMBER_COUNT" = "1" ] || [ "$MEMBER_COUNT" = "0" ]; then
    log_success "PASS: Global Database now has $MEMBER_COUNT member(s) - secondary was detached"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [ -z "$MEMBER_COUNT" ]; then
    log_warn "WARN: Could not check Global Database members (primary region may be unavailable)"
else
    log_error "FAIL: Global Database still has $MEMBER_COUNT members - secondary may not be detached"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: Secondary endpoint resolves and accepts connections
# -------------------------------------------------------
log_info "Check 5: Secondary endpoint is fully operational"
if test_db_connection "$AURORA_SECONDARY_ENDPOINT"; then
    log_success "PASS: Secondary endpoint is accepting connections"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to $AURORA_SECONDARY_ENDPOINT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
record_result "04-global-db-region-failure" "validation_pass" "$PASS_COUNT"
record_result "04-global-db-region-failure" "validation_fail" "$FAIL_COUNT"
record_result "04-global-db-region-failure" "validate_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ""
echo "=================================================="
echo " SURVIVE 04 Validation Complete"
echo "=================================================="
echo " New primary region: $AWS_SECONDARY_REGION"
echo " PASS: $PASS_COUNT"
echo " FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_success "All checks passed. Cross-region failover validated."
    log_info "The secondary cluster is now the primary and accepting writes."
    exit 0
else
    log_error "$FAIL_COUNT check(s) failed. Review the runbook."
    exit 1
fi
