#!/usr/bin/env bash
# SURVIVE 05 - validate.sh
# Verifies the student successfully resolved the Serverless v2 ACU ceiling issue

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

log_section "SURVIVE 05 - Serverless v2 Scaling Stuck Validation"

# -------------------------------------------------------
# Check 1: Cluster status is available
# -------------------------------------------------------
log_info "Check 1: Cluster status is 'available'"
STATUS=$(get_cluster_status "$SERVERLESS_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$STATUS" = "available" ]; then
    log_success "PASS: Cluster status is 'available'"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cluster status is '$STATUS'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: MaxCapacity has been increased above 2
# -------------------------------------------------------
log_info "Check 2: MaxCapacity has been increased beyond 2 ACU"
MAX_CAPACITY=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$SERVERLESS_CLUSTER_ID" \
    --query 'DBClusters[0].ServerlessV2ScalingConfiguration.MaxCapacity' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

record_result "05-serverless-scaling-stuck" "post_fix_max_acu" "$MAX_CAPACITY"

if (( $(echo "$MAX_CAPACITY > 2" | bc -l) )); then
    log_success "PASS: MaxCapacity is now $MAX_CAPACITY ACU (above the 2 ACU ceiling)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: MaxCapacity is still $MAX_CAPACITY ACU (must be increased above 2)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: Cluster endpoint is accepting connections
# -------------------------------------------------------
log_info "Check 3: Cluster endpoint is accepting connections"
if test_db_connection "$SERVERLESS_ENDPOINT"; then
    log_success "PASS: Cluster endpoint is accepting connections"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_error "FAIL: Cannot connect to $SERVERLESS_ENDPOINT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: Current ACU has moved above the old ceiling (3+ ACU)
# This confirms the cluster actually scaled up
# -------------------------------------------------------
log_info "Check 4: Cluster has scaled above the old 2 ACU ceiling"
sleep 30  # brief wait for CloudWatch metrics to update
CURRENT_ACU=$(get_serverless_capacity "$SERVERLESS_CLUSTER_ID" "$AWS_PRIMARY_REGION")

record_result "05-serverless-scaling-stuck" "current_acu_post_fix" "${CURRENT_ACU:-unknown}"

if [ -z "$CURRENT_ACU" ] || [ "$CURRENT_ACU" = "None" ]; then
    log_warn "WARN: Could not get current ACU from CloudWatch (may not have data yet)"
elif (( $(echo "${CURRENT_ACU:-0} > 2" | bc -l) )); then
    log_success "PASS: Current ACU is $CURRENT_ACU (scaled above the old 2 ACU ceiling)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_warn "WARN: Current ACU is $CURRENT_ACU - may still be scaling up. Check CloudWatch in 2 minutes."
fi

# -------------------------------------------------------
# Check 5: A write operation completes in under 5 seconds
# This tests that queries are no longer queuing
# -------------------------------------------------------
log_info "Check 5: Write operation completes within 5 seconds"
WRITE_START=$(date +%s)
WRITE_RESULT=$(psql -h "$SERVERLESS_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    --connect-timeout=10 \
    -t -c "INSERT INTO survive_lag_test (payload, batch_id) VALUES (md5(random()::text), 999) RETURNING id;" \
    2>&1 | tr -d ' \n')
WRITE_END=$(date +%s)
WRITE_DURATION=$((WRITE_END - WRITE_START))

if echo "$WRITE_RESULT" | grep -qE '^[0-9]+$'; then
    if [ "$WRITE_DURATION" -le 5 ]; then
        log_success "PASS: Write completed in ${WRITE_DURATION}s (under 5 second threshold)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_warn "WARN: Write completed in ${WRITE_DURATION}s - cluster may still be recovering"
    fi
else
    log_error "FAIL: Write operation failed ($WRITE_RESULT)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: CloudWatch alarm exists for capacity
# -------------------------------------------------------
log_info "Check 6: CloudWatch alarm exists for Serverless capacity"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-names serverless-capacity-high \
    --query 'length(MetricAlarms)' \
    --output text \
    --region "$AWS_PRIMARY_REGION" 2>/dev/null)

if [ "${ALARM_COUNT:-0}" -gt 0 ]; then
    log_success "PASS: CloudWatch alarm 'serverless-capacity-high' exists"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_warn "WARN: CloudWatch alarm 'serverless-capacity-high' not found."
    log_warn "      Create it using the runbook to prevent future incidents."
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
record_result "05-serverless-scaling-stuck" "validation_pass" "$PASS_COUNT"
record_result "05-serverless-scaling-stuck" "validation_fail" "$FAIL_COUNT"

echo ""
echo "=================================================="
echo " SURVIVE 05 Validation Complete"
echo "=================================================="
echo " Old MaxCapacity: 2 ACU"
echo " New MaxCapacity: ${MAX_CAPACITY:-unknown} ACU"
echo " Current ACU:     ${CURRENT_ACU:-checking...}"
echo " PASS: $PASS_COUNT"
echo " FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    log_success "All checks passed. Serverless v2 scaling ceiling resolved."
    exit 0
else
    log_error "$FAIL_COUNT check(s) failed. Review the runbook."
    exit 1
fi
