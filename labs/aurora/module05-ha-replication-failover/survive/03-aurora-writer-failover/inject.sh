#!/usr/bin/env bash
# SURVIVE 03 - inject.sh
# Triggers an Aurora writer failover to a specific target reader
# Tests that the student can identify the new writer and verify recovery

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 03 - Aurora Writer Failover Injection"

# -------------------------------------------------------
# Pre-injection: record current writer
# -------------------------------------------------------
log_info "Recording current Aurora cluster state..."

CURRENT_WRITER=$(get_cluster_writer "$AURORA_CLUSTER_ID" "$AWS_PRIMARY_REGION")
if [ -z "$CURRENT_WRITER" ]; then
    log_error "Could not determine current writer. Aborting."
    exit 1
fi

WRITER_IP_BEFORE=$(dig +short "$AURORA_WRITER_ENDPOINT" 2>/dev/null | head -1)

log_info "Current writer: $CURRENT_WRITER"
log_info "Writer endpoint IP: $WRITER_IP_BEFORE"

record_result "03-aurora-writer-failover" "pre_failover_writer" "$CURRENT_WRITER"
record_result "03-aurora-writer-failover" "pre_failover_ip" "$WRITER_IP_BEFORE"
record_result "03-aurora-writer-failover" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Injection: trigger failover to specific target
# -------------------------------------------------------
log_warn "INJECTING FAULT: Triggering Aurora writer failover..."
log_warn "Target: highest-priority reader (Aurora selects automatically)"
log_warn "Expected downtime: 20-35 seconds."

aws rds failover-db-cluster \
    --db-cluster-identifier "$AURORA_CLUSTER_ID" \
    --region "$AWS_PRIMARY_REGION"

log_info "Failover command sent."
log_info "---"
log_info "What the student will see:"
log_info "  - Writer endpoint unreachable for 20-35 seconds"
log_info "  - Application connection errors"
log_info "  - Aurora Events: 'A failover for the DB cluster has started'"
log_info "  - A different instance becomes the writer"
log_info "---"
log_info "The student must:"
log_info "  1. Detect the outage"
log_info "  2. Check Aurora Events to confirm failover"
log_info "  3. Verify writer endpoint resolves to new IP"
log_info "  4. Confirm different instance is now writer"
log_info "  5. Verify reads and writes work"
log_info "---"
log_info "Run validate.sh after recovery (~40 seconds)."
