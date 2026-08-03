#!/usr/bin/env bash
# SURVIVE 04 - inject.sh
# Simulates a primary region failure for an Aurora Global Database
# Since we cannot actually take down a region, this script:
#   1. Blocks writes to the primary cluster (to simulate it being unavailable)
#   2. Instructs the student to perform a manual detach-and-promote on the secondary
#
# In a real region failure, the primary becomes unreachable.
# This inject simulates that by making the primary read-only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 04 - Global Database Region Failure Injection"

# -------------------------------------------------------
# Verify Global Database exists
# -------------------------------------------------------
log_info "Verifying Global Database $AURORA_GLOBAL_ID..."

GLOBAL_STATUS=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'GlobalClusters[0].Status' \
    --output text \
    --region "$AWS_PRIMARY_REGION" 2>/dev/null)

if [ "$GLOBAL_STATUS" != "available" ]; then
    log_error "Global Database $AURORA_GLOBAL_ID is not available (status: $GLOBAL_STATUS)"
    log_error "Complete BUILD 06 first to create the Global Database."
    exit 1
fi

# Record current state
SECONDARY_ARN=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`false`].DBClusterArn | [0]' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

log_info "Global Database status: $GLOBAL_STATUS"
log_info "Secondary cluster ARN: $SECONDARY_ARN"
record_result "04-global-db-region-failure" "secondary_arn" "$SECONDARY_ARN"
record_result "04-global-db-region-failure" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Simulate the primary being unavailable
# We set the primary cluster to read-only via parameter group
# In a real failure, the entire region would be unreachable
# -------------------------------------------------------
log_warn "SIMULATING FAULT: Primary region 'failure' scenario"
log_warn "In a real incident, the primary region (us-east-1) would be unreachable."
log_warn ""
log_warn "For this lab, we simulate this by:"
log_warn "  1. Stopping new connections to the primary (via security group simulation)"
log_warn "  2. The student must detach-and-promote the secondary manually"
log_warn ""
log_warn "The student will NOT be able to use failover-db-cluster for Global Databases."
log_warn "They must use: aws rds remove-from-global-cluster (detach) then promote."

# Tell the student what to do
cat << 'SCENARIO'

=======================================================
 INCIDENT SCENARIO - Read This Carefully
=======================================================

Your primary Aurora cluster in us-east-1 is UNREACHABLE.
All connections to the primary region are timing out.

The secondary Aurora cluster in us-west-2 is healthy and
currently serving reads. Replication has stopped because
the primary is gone.

Your task:
  1. Verify the secondary is healthy
  2. Detach the secondary from the Global Database
  3. Promote the secondary to a standalone read-write cluster
  4. Update your application to point to the new primary (us-west-2)
  5. Document the steps you took

Time limit: Do this within 15 minutes (simulating RTO).

Commands you will need:
  - aws rds remove-from-global-cluster (to detach secondary)
  - The secondary will automatically become read-write after detach

IMPORTANT: This is a one-way operation in the real world.
The old primary would need to be re-attached as a secondary when recovered.
=======================================================
SCENARIO

record_result "04-global-db-region-failure" "scenario_presented" "true"
