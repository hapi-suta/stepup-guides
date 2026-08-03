#!/usr/bin/env bash
# SURVIVE 01 - inject.sh
# Triggers an unexpected Multi-AZ failover on an RDS instance
# Run this script while a student's app is connected to simulate a real incident

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 01 - Multi-AZ Failover Injection"

# -------------------------------------------------------
# Pre-injection: confirm the instance is Multi-AZ
# -------------------------------------------------------
log_info "Checking instance $RDS_INSTANCE_ID before injection..."

IS_MULTI_AZ=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].MultiAZ' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

if [ "$IS_MULTI_AZ" != "True" ]; then
    log_error "Instance $RDS_INSTANCE_ID is not Multi-AZ. Cannot inject failover."
    log_error "Enable Multi-AZ first using BUILD 01."
    exit 1
fi

CURRENT_AZ=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].AvailabilityZone' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

log_info "Instance is Multi-AZ: YES"
log_info "Current primary AZ: $CURRENT_AZ"

# Record pre-failover state
record_result "01-multi-az-failover" "pre_failover_az" "$CURRENT_AZ"
record_result "01-multi-az-failover" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Injection: trigger the failover
# -------------------------------------------------------
log_warn "INJECTING FAULT: Triggering RDS Multi-AZ failover..."
log_warn "This will cause 60-120 seconds of database downtime."
log_warn "The student's application will lose connections."

aws rds reboot-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --force-failover \
    --region "$AWS_PRIMARY_REGION"

log_info "Failover triggered. Instance is now rebooting."
log_info "---"
log_info "What the student will see:"
log_info "  - Connection errors from their application"
log_info "  - 'could not connect to server' or SSL connection errors"
log_info "  - Approximately 60-120 seconds of downtime"
log_info "---"
log_info "The student must:"
log_info "  1. Detect the outage using CloudWatch or application logs"
log_info "  2. Confirm it is a failover (not a hardware failure)"
log_info "  3. Verify reconnection after DNS updates"
log_info "  4. Confirm the AZ has changed"
log_info "---"
log_info "Run validate.sh after the failover completes."
