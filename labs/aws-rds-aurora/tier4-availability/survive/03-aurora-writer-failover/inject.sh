#!/usr/bin/env bash
# SURVIVE 03 - inject.sh
# Triggers an Aurora writer failover to simulate the writer instance failing
# Students must observe the automatic promotion and verify recovery

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
    log_error "Could not determine current writer for cluster $AURORA_CLUSTER_ID"
    exit 1
fi

log_info "Current writer: $CURRENT_WRITER"
record_result "03-aurora-writer-failover" "pre_failover_writer" "$CURRENT_WRITER"
record_result "03-aurora-writer-failover" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Get the cluster writer endpoint before failover
WRITER_IP_BEFORE=$(dig +short "$AURORA_WRITER_ENDPOINT" 2>/dev/null | head -1)
log_info "Writer endpoint resolves to: $WRITER_IP_BEFORE"
record_result "03-aurora-writer-failover" "pre_failover_ip" "$WRITER_IP_BEFORE"

# -------------------------------------------------------
# Injection: trigger the failover
# No specific target - Aurora will pick the highest priority reader
# -------------------------------------------------------
log_warn "INJECTING FAULT: Triggering Aurora writer failover..."
log_warn "Aurora will automatically promote the highest-priority reader."
log_warn "Expected downtime: 20-35 seconds."

aws rds failover-db-cluster \
    --db-cluster-identifier "$AURORA_CLUSTER_ID" \
    --region "$AWS_PRIMARY_REGION"

log_info "Failover command sent to Aurora."
log_info "---"
log_info "What the student will see:"
log_info "  - Writer endpoint becomes unreachable for 20-35 seconds"
log_info "  - Application throws 'could not connect to server' errors"
log_info "  - Aurora Events show 'A failover for the DB cluster has started'"
log_info "  - A different instance becomes the writer"
log_info "---"
log_info "The student must:"
log_info "  1. Detect the outage via application errors or CloudWatch"
log_info "  2. Check Aurora events to confirm it is a failover (not a crash)"
log_info "  3. Verify the writer endpoint resolves to a new IP after recovery"
log_info "  4. Confirm a different instance is now the writer"
log_info "  5. Verify all reads and writes work after recovery"
log_info "---"
log_info "Run validate.sh after recovery (approximately 30-40 seconds from now)."
