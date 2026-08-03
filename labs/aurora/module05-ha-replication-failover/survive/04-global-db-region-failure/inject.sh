#!/usr/bin/env bash
# SURVIVE 04 - inject.sh
# Simulates a primary region failure for an Aurora Global Database
# Since we cannot actually take down a region, this script:
#   1. Records the current Global Database state
#   2. Presents the student with a region failure scenario
#   3. The student must detach-and-promote the secondary manually
#
# In a real region failure, the primary becomes unreachable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/common.sh"

log_section "SURVIVE 04 - Global Database Region Failure Injection"

# -------------------------------------------------------
# Pre-injection: verify Global Database exists
# -------------------------------------------------------
log_info "Verifying Global Database $AURORA_GLOBAL_ID..."

GLOBAL_STATUS=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'GlobalClusters[0].Status' \
    --output text \
    --region "$AWS_PRIMARY_REGION" 2>/dev/null)

if [ "$GLOBAL_STATUS" != "available" ]; then
    log_error "Global Database $AURORA_GLOBAL_ID is not available (status: $GLOBAL_STATUS)"
    log_error "Complete BUILD 05 (Global Database Setup) first."
    exit 1
fi

# -------------------------------------------------------
# Record current state
# -------------------------------------------------------
log_info "Recording current Global Database state..."

MEMBER_COUNT=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'length(GlobalClusters[0].GlobalClusterMembers)' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

PRIMARY_ARN=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn | [0]' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

SECONDARY_ARN=$(aws rds describe-global-clusters \
    --global-cluster-identifier "$AURORA_GLOBAL_ID" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`false`].DBClusterArn | [0]' \
    --output text \
    --region "$AWS_PRIMARY_REGION")

log_info "Global Database status: $GLOBAL_STATUS"
log_info "Member count: $MEMBER_COUNT"
log_info "Primary ARN: $PRIMARY_ARN"
log_info "Secondary ARN: $SECONDARY_ARN"

record_result "04-global-db-region-failure" "global_status" "$GLOBAL_STATUS"
record_result "04-global-db-region-failure" "primary_arn" "$PRIMARY_ARN"
record_result "04-global-db-region-failure" "secondary_arn" "$SECONDARY_ARN"
record_result "04-global-db-region-failure" "inject_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -------------------------------------------------------
# Present the scenario
# -------------------------------------------------------
log_warn "SIMULATING FAULT: Primary region failure scenario"
log_warn "In a real incident, the primary region ($AWS_PRIMARY_REGION) would be unreachable."
log_warn ""
log_warn "For this lab, we simulate this by presenting the scenario below."
log_warn "The student must perform a manual detach-and-promote on the secondary."
log_warn ""
log_warn "The student will NOT be able to use switchover-global-cluster."
log_warn "They must use: aws rds remove-from-global-cluster (detach) then the"
log_warn "secondary becomes a standalone read-write cluster automatically."

cat << 'SCENARIO'

=======================================================
 INCIDENT SCENARIO - Read This Carefully
=======================================================

Your primary Aurora cluster in us-east-1 is UNREACHABLE.
All connections to the primary region are timing out.
AWS Status page shows us-east-1 is experiencing a major outage.

The secondary Aurora cluster in us-west-2 is healthy and
currently serving reads. Replication has stopped because
the primary is gone.

Your task:
  1. Verify the secondary cluster is healthy (us-west-2)
  2. Check the last replication point (how much data might be lost)
  3. Detach the secondary from the Global Database
  4. Confirm the secondary is now read-write
  5. Test that writes work on the new primary
  6. Document the steps you took and estimate data loss

Time limit: Complete this within 15 minutes (simulating RTO).

Commands you will need:
  - aws rds describe-db-clusters (check secondary health)
  - aws rds remove-from-global-cluster (detach secondary)
  - psql (verify read-write mode and test writes)

IMPORTANT: This is a one-way operation in the real world.
The old primary would need to be rebuilt and re-attached
as a secondary when the region recovers.
=======================================================
SCENARIO

record_result "04-global-db-region-failure" "scenario_presented" "true"

log_info "---"
log_info "The student must:"
log_info "  1. Check secondary cluster health in $AWS_SECONDARY_REGION"
log_info "  2. Run: aws rds remove-from-global-cluster"
log_info "  3. Wait for secondary to become read-write"
log_info "  4. Verify writes work on the promoted cluster"
log_info "---"
log_info "Run validate.sh after completing the DR failover."
