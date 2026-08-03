#!/usr/bin/env bash
# survive/03-instance-stopped/inject.sh
# Deletes a reader instance from the Aurora cluster to simulate a missing reader.
# Aurora does not support stop-db-instance on cluster members, so we delete instead.
#
# Required environment variables:
#   CLUSTER_ID       - Aurora cluster identifier (default: devops-lab-cluster)
#   REGION           - AWS region (default: us-east-1)
#   TARGET_READER    - Reader instance to delete (default: devops-lab-cluster-reader-2)
#
# Usage:
#   export CLUSTER_ID=devops-lab-cluster
#   export REGION=us-east-1
#   bash inject.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${REGION:-us-east-1}"
TARGET_READER="${TARGET_READER:-devops-lab-cluster-reader-2}"
BACKUP_FILE="/tmp/devops-reader-backup-03.json"

echo ""
echo "========================================"
echo "  INJECT: Instance Stopped (Reader Missing)"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1 - Verify the cluster is available
# ---------------------------------------------------------------------------
echo "[INFO]  Checking cluster status..."

CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Status" \
  --output text 2>/dev/null || echo "not-found")

if [[ "$CLUSTER_STATUS" != "available" ]]; then
  echo "[FAIL]  Cluster $CLUSTER_ID is not available (status: $CLUSTER_STATUS). Aborting."
  exit 1
fi
echo "[PASS]  Cluster is available"

# ---------------------------------------------------------------------------
# Step 2 - List current cluster members
# ---------------------------------------------------------------------------
echo "[INFO]  Current cluster members:"

aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}" \
  --output table 2>/dev/null

# ---------------------------------------------------------------------------
# Step 3 - Verify target reader exists and is NOT the writer
# ---------------------------------------------------------------------------
echo "[INFO]  Checking target reader: $TARGET_READER..."

IS_WRITER=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].DBClusterMembers[?DBInstanceIdentifier=='$TARGET_READER'].IsClusterWriter" \
  --output text 2>/dev/null || echo "not-found")

if [[ "$IS_WRITER" == "True" ]]; then
  echo "[FAIL]  $TARGET_READER is the writer. Cannot delete the writer. Choose a reader."
  exit 1
fi

if [[ "$IS_WRITER" == "not-found" || -z "$IS_WRITER" ]]; then
  echo "[FAIL]  $TARGET_READER not found in cluster $CLUSTER_ID."
  exit 1
fi

echo "[PASS]  $TARGET_READER is a reader - safe to delete"

# ---------------------------------------------------------------------------
# Step 4 - Save reader instance details for reference
# ---------------------------------------------------------------------------
echo "[INFO]  Saving reader details to $BACKUP_FILE..."

aws rds describe-db-instances \
  --db-instance-identifier "$TARGET_READER" \
  --region "$REGION" \
  --query "DBInstances[0].{ID:DBInstanceIdentifier,Class:DBInstanceClass,AZ:AvailabilityZone,Engine:Engine}" \
  --output json > "$BACKUP_FILE" 2>/dev/null

echo "[PASS]  Reader details saved"

# ---------------------------------------------------------------------------
# Step 5 - Delete the reader instance
# ---------------------------------------------------------------------------
echo "[INFO]  Deleting reader instance $TARGET_READER..."

aws rds delete-db-instance \
  --db-instance-identifier "$TARGET_READER" \
  --region "$REGION" \
  --skip-final-snapshot > /dev/null 2>&1

echo "[PASS]  Delete initiated for $TARGET_READER"

# ---------------------------------------------------------------------------
# Step 6 - Confirm deletion is in progress
# ---------------------------------------------------------------------------
sleep 5

READER_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$TARGET_READER" \
  --region "$REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || echo "deleted")

echo "[INFO]  Reader status: $READER_STATUS"

echo ""
echo "========================================"
echo "  INJECTION COMPLETE"
echo "========================================"
echo ""
echo "  Scenario: Reader Instance Missing"
echo "  Reader $TARGET_READER has been deleted from cluster $CLUSTER_ID."
echo "  Status: $READER_STATUS"
echo ""
echo "  The reader endpoint may return errors or route all"
echo "  traffic to the remaining reader."
echo ""
echo "  Reader details saved to: $BACKUP_FILE"
echo "  (Use the class and AZ info when recreating)"
echo ""
echo "  Now open: survive/03-instance-stopped/runbook.md"
echo "========================================"
