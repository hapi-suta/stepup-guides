#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 05: Primary Region Degraded - DR Failover Needed
#
# What this script does:
#   Simulates the decision-making and execution environment of a cross-region
#   DR failover scenario. Because we cannot actually degrade an AWS region,
#   this script:
#
#   1. Simulates the alert stream and status messages you would receive
#   2. Verifies your Aurora Global Database or backup restore is configured
#   3. Walks you through the decision gate: is this a real outage? What is the RTO?
#   4. Presents the technical steps to execute
#
# This is a tabletop-style SURVIVE scenario for operations that cannot be
# safely injected in a lab environment without significant cost and risk.
# The "injection" here is the scenario framing and decision pressure.
#
# infra_required: Aurora Global Database (for full drill) OR
#                 Cross-region snapshot configured (for restore path)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 05: Primary Region Outage - DR Failover"

t8_validate_config || exit 1
check_prerequisites || exit 1
check_aws_auth || exit 1

record_start

echo ""
echo "This scenario is a decision-gate exercise."
echo "You cannot inject a real AWS region failure in a lab environment."
echo "Instead, this script verifies your DR readiness and presents the"
echo "decision scenario you would face in a real outage."
echo ""
read -rp "Type CONFIRM to begin the scenario: " confirmation
if [[ "${confirmation}" != "CONFIRM" ]]; then
  echo "Aborted."
  exit 0
fi

# -----------------------------------------------------------------------
# Step 1: Verify DR infrastructure readiness
# -----------------------------------------------------------------------
log_step "Step 1: Checking DR infrastructure readiness..."

echo ""

# Check for Global Database
GLOBAL_DB=$(aws rds describe-global-clusters \
  --region "${T8_REGION}" \
  --query 'GlobalClusters[*].[GlobalClusterIdentifier,Status]' \
  --output text 2>/dev/null || echo "")

if [[ -n "${GLOBAL_DB}" ]]; then
  log_success "Aurora Global Database found:"
  echo "${GLOBAL_DB}"
  DR_METHOD="global_database"
else
  log_warn "No Aurora Global Database found in region ${T8_REGION}."
  DR_METHOD="snapshot"
fi

# Check for cross-region snapshots
SECONDARY_REGION="us-west-2"  # Default secondary
if [[ "${T8_REGION}" == "us-west-2" ]]; then
  SECONDARY_REGION="us-east-1"
fi

echo ""
log_info "Checking for cross-region snapshots in ${SECONDARY_REGION}..."

SNAPSHOTS=$(aws rds describe-db-snapshots \
  --region "${SECONDARY_REGION}" \
  --query 'DBSnapshots[?Status==`available`].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output text 2>/dev/null | head -5)

if [[ -n "${SNAPSHOTS}" ]]; then
  log_success "Cross-region snapshots found in ${SECONDARY_REGION}:"
  echo "${SNAPSHOTS}"
else
  log_warn "No snapshots found in ${SECONDARY_REGION}. DR restore path may be unavailable."
fi

# -----------------------------------------------------------------------
# Step 2: Present the scenario
# -----------------------------------------------------------------------
echo ""
echo "==========================================="
echo "INCIDENT ALERT STREAM"
echo "Time: $(date '+%H:%M:%S UTC')"
echo "==========================================="
echo ""
echo "  04:23 AWS Health Dashboard:"
echo "    'We are investigating increased error rates in the [${T8_REGION}] region.'"
echo "    'RDS, EC2, and ALB services are experiencing connectivity issues.'"
echo ""
echo "  04:24 Application monitoring (Datadog):"
echo "    'CRITICAL: API error rate 94%. All services degraded.'"
echo "    'Database connectivity timeout errors across all instances.'"
echo ""
echo "  04:25 On-call engineer:"
echo "    'Cannot SSH into EC2 instances. RDS console showing connection errors.'"
echo "    'Not a configuration change - no deployments in the past 4 hours.'"
echo ""
echo "  04:26 PagerDuty:"
echo "    'CRITICAL: DatabaseConnections = 0 for prod-aurora-cluster'"
echo "    'RDS instances showing status: storage-full / incompatible-network'"
echo ""
echo "  04:27 Slack #incidents:"
echo "    'AWS is acknowledging region-wide issues. ETA unknown.'"
echo "    'Do we failover to DR region?'"
echo ""
echo "==========================================="
echo ""
echo "You are the on-call DBA. It is 4:27 AM."
echo "The business is losing approximately \$15,000/minute."
echo ""
echo "DR readiness status:"
if [[ "${DR_METHOD}" == "global_database" ]]; then
  echo "  - Aurora Global Database: AVAILABLE (RTO < 2 minutes)"
  echo "  - Secondary region cluster: READY"
else
  echo "  - Aurora Global Database: NOT CONFIGURED"
  echo "  - Cross-region snapshots: $([ -n "${SNAPSHOTS}" ] && echo "AVAILABLE (RTO ~1 hour)" || echo "NOT AVAILABLE")"
fi
echo ""
echo "==========================================="
echo "DECISION GATE"
echo "==========================================="
echo ""
echo "Before executing the failover, you must answer these questions:"
echo ""
echo "  1. Is this a real AWS region failure, or a monitoring/configuration issue?"
echo "     (You cannot actually test connectivity to ${T8_REGION} in a lab,"
echo "      but in a real scenario: what AWS resources do you check first?)"
echo ""
echo "  2. What is your authorizing threshold for cross-region failover?"
echo "     Who must approve this decision?"
echo ""
echo "  3. What are the risks of failing over?"
echo "     - RPO: How much data might you lose?"
echo "     - Application compatibility: Will the app work against the DR instance?"
echo "     - Failback plan: How do you get back to the primary region?"
echo ""

read -rp "Press ENTER when you have documented your answers to proceed..."

# -----------------------------------------------------------------------
# Step 3: Execute the failover procedure
# -----------------------------------------------------------------------
echo ""
log_step "Step 3: Failover execution procedure..."
echo ""

if [[ "${DR_METHOD}" == "global_database" ]]; then
  GLOBAL_CLUSTER_ID=$(aws rds describe-global-clusters \
    --region "${T8_REGION}" \
    --query 'GlobalClusters[0].GlobalClusterIdentifier' \
    --output text 2>/dev/null)

  SECONDARY_CLUSTER_ARN=$(aws rds describe-global-clusters \
    --region "${T8_REGION}" \
    --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`false`].DBClusterArn' \
    --output text 2>/dev/null | head -1)

  echo "Failover Command (Global Database - managed planned failover):"
  echo ""
  echo "  # Record T0"
  echo "  T0=\$(date +%H:%M:%S.%3N)"
  echo "  echo \"T0 (failover initiated): \$T0\""
  echo ""
  echo "  aws rds failover-global-cluster \\"
  echo "    --global-cluster-identifier ${GLOBAL_CLUSTER_ID} \\"
  echo "    --target-db-cluster-identifier ${SECONDARY_CLUSTER_ARN:-[SECONDARY-CLUSTER-ARN]} \\"
  echo "    --region ${T8_REGION}"
  echo ""
  echo "  # Monitor until secondary becomes writer"
  echo "  watch -n 5 'aws rds describe-global-clusters \\"
  echo "    --region ${SECONDARY_REGION} \\"
  echo "    --query \"GlobalClusters[*].GlobalClusterMembers[*].{Cluster:DBClusterArn,IsWriter:IsWriter}\" \\"
  echo "    --output table'"
  echo ""

  read -rp "Execute the failover now? (yes/no): " execute_failover
  if [[ "${execute_failover}" == "yes" ]]; then
    if [[ -n "${SECONDARY_CLUSTER_ARN}" ]]; then
      T0=$(date +%H:%M:%S.%3N)
      echo "T0: ${T0}"

      aws rds failover-global-cluster \
        --global-cluster-identifier "${GLOBAL_CLUSTER_ID}" \
        --target-db-cluster-identifier "${SECONDARY_CLUSTER_ARN}" \
        --region "${T8_REGION}"

      log_info "Failover initiated. Monitor the global cluster status."
    else
      log_warn "Could not determine secondary cluster ARN. Execute manually using the commands above."
    fi
  else
    log_info "Failover not executed. This is a tabletop exercise."
  fi

else
  echo "Failover Path: Restore from cross-region snapshot"
  echo ""
  echo "  Step 1: Identify the most recent snapshot in ${SECONDARY_REGION}:"
  echo "  aws rds describe-db-snapshots \\"
  echo "    --region ${SECONDARY_REGION} \\"
  echo "    --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].[DBSnapshotIdentifier,SnapshotCreateTime]' \\"
  echo "    --output table"
  echo ""
  echo "  Step 2: Restore to a new instance in ${SECONDARY_REGION}:"
  echo "  aws rds restore-db-instance-from-db-snapshot \\"
  echo "    --db-instance-identifier prod-db-dr-restore \\"
  echo "    --db-snapshot-identifier [LATEST-SNAPSHOT-ID] \\"
  echo "    --db-instance-class [INSTANCE-CLASS] \\"
  echo "    --no-publicly-accessible \\"
  echo "    --region ${SECONDARY_REGION}"
  echo ""
  echo "  Step 3: Update application connection string to DR instance endpoint."
  echo "  Estimated RTO: 30-90 minutes depending on snapshot size."
  echo ""
  echo "  NOTE: This path has meaningful RPO (time since last snapshot)."
fi

# -----------------------------------------------------------------------
# Step 4: Record scenario state for validate.sh
# -----------------------------------------------------------------------
echo ""

cat > "${SCRIPT_DIR}/.inject-state" << EOF
INJECT_TIME=$(date +%s)
DR_METHOD=${DR_METHOD}
SECONDARY_REGION=${SECONDARY_REGION}
EOF

log_info "Scenario state saved. Complete your DR execution, then run validate.sh."
echo ""
log_warn "========================================================"
log_warn "SCENARIO IN PROGRESS"
log_warn "========================================================"
echo ""
echo "Your tasks:"
echo "  1. Execute the failover (or document why you chose not to)"
echo "  2. Update the application connection string to the DR endpoint"
echo "  3. Verify end-to-end application health in the DR region"
echo "  4. Record your RTO and RPO measurements"
echo "  5. Plan the failback procedure"
echo ""
echo "Run validate.sh when your DR environment is healthy."
