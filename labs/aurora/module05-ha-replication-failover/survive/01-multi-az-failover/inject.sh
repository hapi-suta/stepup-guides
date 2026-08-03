#!/usr/bin/env bash
# SURVIVE 01 - inject.sh
# Triggers an Aurora cluster failover to simulate the writer instance failing
# Run this while a student's app is connected to simulate a real incident

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 01 - Multi-AZ Failover Injection"

# -------------------------------------------------------
# Pre-injection: confirm the cluster is healthy
# -------------------------------------------------------
log_info "Checking cluster $AURORA_CLUSTER_ID before injection..."

CLUSTER_STATUS=$(get_cluster_status "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ "$CLUSTER_STATUS" != "available" ]; then
    log_error "Cluster is not in 'available' state (got: $CLUSTER_STATUS). Aborting."
    exit 1
fi

CURRENT_WRITER=$(get_cluster_writer "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ -z "$CURRENT_WRITER" ]; then
    log_error "Could not determine current writer. Aborting."
    exit 1
fi

CURRENT_IP=$(dig +short "$AURORA_WRITER_ENDPOINT" 2>/dev/null | head -1)

log_info "Cluster status: $CLUSTER_STATUS"
log_info "Current writer: $CURRENT_WRITER"
log_info "Writer endpoint IP: $CURRENT_IP"

record_result "01-multi-az-failover" "pre_failover_writer" "$CURRENT_WRITER"
record_result "01-multi-az-failover" "pre_failover_ip" "$CURRENT_IP"
record_result "01-multi-az-failover" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Injection: trigger the failover
# -------------------------------------------------------
log_warn "INJECTING FAULT: Triggering Aurora cluster failover..."
log_warn "This will cause 20-35 seconds of database downtime."
log_warn "The student's application will lose connections."

aws rds failover-db-cluster \
    --db-cluster-identifier "$AURORA_CLUSTER_ID" \
    --region "$AWS_PRIMARY_REGION"

log_info "Failover triggered. Cluster status: failing-over."
log_info "---"
log_info "What the student will see:"
log_info "  - Connection errors from their application"
log_info "  - 'could not connect to server' or SSL errors"
log_info "  - Approximately 20-35 seconds of downtime"
log_info "---"
log_info "The student must:"
log_info "  1. Detect the outage using CloudWatch or application logs"
log_info "  2. Confirm it is a failover (check Events)"
log_info "  3. Verify reconnection after DNS updates"
log_info "  4. Confirm a different instance is now the writer"
log_info "---"
log_info "Run validate.sh after the failover completes (~40 seconds)."
