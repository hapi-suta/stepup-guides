#!/usr/bin/env bash
# SURVIVE 01 - validate.sh
# Verifies that the Multi-AZ failover completed successfully
# Run this AFTER the failover has completed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

log_section "SURVIVE 01 - Multi-AZ Failover Validation"

# -------------------------------------------------------
# Check 1: Instance status is available
# -------------------------------------------------------
log_info "Check 1: Instance status is 'available'"
STATUS=$(get_instance_status "$RDS_INSTANCE_ID" "$AWS_PRIMARY_REGION")
if [ "$STATUS" = "available" ]; then
    log_success "PASS: Instance status is 'available'"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Instance status is '$STATUS' (expected 'available')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: Instance is still Multi-AZ
# -------------------------------------------------------
log_info "Check 2: Instance is still Multi-AZ"
IS_MULTI_AZ=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].MultiAZ' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

if [ "$IS_MULTI_AZ" = "True" ]; then
    log_success "PASS: Instance is still Multi-AZ"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Instance is no longer Multi-AZ (got: $IS_MULTI_AZ)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: AZ has changed (failover actually happened)
# -------------------------------------------------------
log_info "Check 3: AZ has changed after failover"
PRE_AZ=$(grep "01-multi-az-failover,pre_failover_az" "$SURVIVE_RESULTS_DIR/results.csv" 2>/dev/null | tail -1 | cut -d',' -f4)
CURRENT_AZ=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].AvailabilityZone' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

if [ -n "$PRE_AZ" ] && [ "$PRE_AZ" != "$CURRENT_AZ" ]; then
    log_success "PASS: AZ changed from $PRE_AZ to $CURRENT_AZ"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [ -z "$PRE_AZ" ]; then
    log_warn "SKIP: No pre-failover AZ recorded (inject.sh was not run first)"
else
    log_error "FAIL: AZ did not change (still $CURRENT_AZ, was $PRE_AZ)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

record_result "01-multi-az-failover" "post_failover_az" "$CURRENT_AZ"

# -------------------------------------------------------
# Check 4: Database endpoint is reachable
# -------------------------------------------------------
log_info "Check 4: Database endpoint is reachable"
if test_db_connection "$RDS_ENDPOINT"; then
    log_success "PASS: Database endpoint is reachable"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to $RDS_ENDPOINT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: Database is in read-write mode (not recovery)
# -------------------------------------------------------
log_info "Check 5: Database is in read-write mode"
IS_RECOVERY=$(run_query "$RDS_ENDPOINT" "SELECT pg_is_in_recovery();")
if [ "$IS_RECOVERY" = "f" ]; then
    log_success "PASS: Database is in read-write mode (pg_is_in_recovery = f)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Database appears to be in recovery mode (pg_is_in_recovery = $IS_RECOVERY)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: Failover event recorded in RDS Events
# -------------------------------------------------------
log_info "Check 6: Failover event recorded in RDS Events"
EVENT_COUNT=$(aws rds describe-events \
    --source-identifier "$RDS_INSTANCE_ID" \
    --source-type db-instance \
    --duration 60 \
    --region "$AWS_PRIMARY_REGION" \
    --query 'length(Events[?contains(Message, `failover`)])' \
    --output text 2>/dev/null)

if [ "$EVENT_COUNT" -gt 0 ] 2>/dev/null; then
    log_success "PASS: Failover events found in RDS Events ($EVENT_COUNT events)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_warn "WARN: No failover events found in last 60 minutes. Check RDS -> Events tab manually."
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
record_result "01-multi-az-failover" "validation_pass" "$PASS_COUNT"
record_result "01-multi-az-failover" "validation_fail" "$FAIL_COUNT"

echo ""
echo "=================================================="
echo " SURVIVE 01 Validation Complete"
echo "=================================================="
echo " PASS: $PASS_COUNT"
echo " FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_success "All checks passed. Failover is confirmed successful."
    exit 0
else
    log_error "$FAIL_COUNT check(s) failed. Review the runbook and retry."
    exit 1
fi
