#!/usr/bin/env bash
# SURVIVE Scenario 01: Writer Instance Failure
# Injects: Forces a failover of the Aurora cluster, simulating a writer crash.
# Idempotent: Safe to run multiple times. Each run triggers a failover.
#
# Usage: bash inject.sh
# Requires: AWS CLI configured, CLUSTER_ID environment variable set

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================="
echo "  SURVIVE Scenario 01: Writer Instance Failure"
echo "============================================="
echo ""
echo "  Cluster: $CLUSTER_ID"
echo "  Region:  $REGION"
echo ""

# Record the current writer before failover
CURRENT_WRITER=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
  --output text \
  --region "$REGION")

echo "Current writer: $CURRENT_WRITER"
echo ""

# Check cluster is available before attempting failover
CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Status' \
  --output text \
  --region "$REGION")

if [[ "$CLUSTER_STATUS" != "available" ]]; then
  echo "ERROR: Cluster status is '$CLUSTER_STATUS', not 'available'."
  echo "Wait for the cluster to be available before injecting failure."
  exit 1
fi

# Record the injection time
INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Force failover
echo "Forcing failover..."
aws rds failover-db-cluster \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION"

echo ""
echo "Failover initiated."
echo "The writer ($CURRENT_WRITER) is being demoted."
echo ""
echo "YOUR MISSION:"
echo "  1. Monitor the failover using RDS events and CloudWatch"
echo "  2. Identify which instance became the new writer"
echo "  3. Verify the cluster endpoint resolves to the new writer"
echo "  4. Confirm all alarms return to OK state"
echo "  5. Document the failover duration"
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
