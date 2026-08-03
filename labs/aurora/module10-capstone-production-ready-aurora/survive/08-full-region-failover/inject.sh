#!/usr/bin/env bash
# SURVIVE Scenario 08: Full Region Failover
# Injects: Simulates a region failure by verifying cross-region snapshots
#          exist and preparing a DR restore in us-west-2.
# Idempotent: Safe to run multiple times. Does not destroy primary cluster.
#
# NOTE: This scenario does NOT actually disable the primary region.
#       It simulates the scenario by requiring you to restore from a
#       cross-region snapshot in us-west-2 as if us-east-1 were unavailable.
#
# Usage: bash inject.sh
# Requires: AWS CLI configured, cross-region snapshots from Build 06

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
PRIMARY_REGION="us-east-1"
DR_REGION="us-west-2"

echo "============================================="
echo "  SURVIVE Scenario 08: Full Region Failover"
echo "============================================="
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

echo "SCENARIO: The entire us-east-1 region is experiencing a major outage."
echo "Your primary Aurora cluster (devops-lab-cluster) is unreachable."
echo "You must restore service from the DR region (us-west-2)."
echo ""

# Check for existing cross-region snapshots
echo "Checking for available snapshots in $DR_REGION..."
DR_SNAPSHOTS=$(aws rds describe-db-cluster-snapshots \
  --snapshot-type manual \
  --query "DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, 'devops-lab')].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]" \
  --output table \
  --region "$DR_REGION" 2>/dev/null || echo "NONE")

echo "$DR_SNAPSHOTS"
echo ""

if echo "$DR_SNAPSHOTS" | grep -q "available"; then
  LATEST_DR_SNAP=$(aws rds describe-db-cluster-snapshots \
    --snapshot-type manual \
    --query "DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, 'devops-lab') && Status=='available'] | sort_by(@, &SnapshotCreateTime) | [-1].DBClusterSnapshotIdentifier" \
    --output text \
    --region "$DR_REGION")
  echo "Latest available DR snapshot: $LATEST_DR_SNAP"
else
  echo "WARNING: No cross-region snapshots found in $DR_REGION."
  echo "You must first copy a snapshot from $PRIMARY_REGION (if accessible)"
  echo "or acknowledge that RPO has been exceeded."

  # Create a snapshot copy for the exercise
  echo ""
  echo "Creating a cross-region snapshot copy for this exercise..."
  LATEST_SNAP=$(aws rds describe-db-cluster-snapshots \
    --db-cluster-identifier "$CLUSTER_ID" \
    --snapshot-type automated \
    --query 'DBClusterSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBClusterSnapshotArn' \
    --output text --region "$PRIMARY_REGION" 2>/dev/null || echo "NONE")

  if [[ "$LATEST_SNAP" != "NONE" ]]; then
    DR_KMS=$(aws kms describe-key --key-id alias/devops-lab-aurora-cmk \
      --query 'KeyMetadata.Arn' --output text --region "$DR_REGION" 2>/dev/null || echo "")
    if [[ -n "$DR_KMS" ]]; then
      aws rds copy-db-cluster-snapshot \
        --source-db-cluster-snapshot-identifier "$LATEST_SNAP" \
        --target-db-cluster-snapshot-identifier "${CLUSTER_ID}-dr-exercise" \
        --kms-key-id "$DR_KMS" \
        --source-region "$PRIMARY_REGION" \
        --region "$DR_REGION" 2>/dev/null || true
      LATEST_DR_SNAP="${CLUSTER_ID}-dr-exercise"
      echo "Snapshot copy initiated: $LATEST_DR_SNAP"
      echo "Wait for it to become available before proceeding."
    fi
  fi
fi

echo ""
echo "YOUR MISSION:"
echo "  1. Verify the cross-region snapshot is available in us-west-2"
echo "  2. Create a DB subnet group in us-west-2 (you need VPC/subnets there)"
echo "  3. Restore the cluster from the snapshot in us-west-2"
echo "  4. Create a writer instance in the restored cluster"
echo "  5. Verify data integrity in the restored cluster"
echo "  6. Document RPO (how much data was lost) and RTO (how long recovery took)"
echo "  7. Clean up the DR cluster when done"
echo ""
echo "DR REGION: $DR_REGION"
echo "DR SNAPSHOT: ${LATEST_DR_SNAP:-PENDING}"
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
