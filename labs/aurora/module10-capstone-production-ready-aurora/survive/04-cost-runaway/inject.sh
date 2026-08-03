#!/usr/bin/env bash
# SURVIVE Scenario 04: Cost Runaway
# Injects: Creates an oversized reader instance and unnecessary manual snapshots
#          that will inflate costs.
# Idempotent: Deletes existing chaos resources before recreating.
#
# Usage: bash inject.sh
# Requires: AWS CLI configured, CLUSTER_ID set

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================="
echo "  SURVIVE Scenario 04: Cost Runaway"
echo "============================================="
echo ""

INJECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "Injection time: $INJECT_TIME"
echo ""

# Step 1: Create an oversized reader instance (db.r6g.2xlarge instead of db.r6g.large)
echo "Creating oversized reader instance (db.r6g.2xlarge)..."
aws rds delete-db-instance \
  --db-instance-identifier "${CLUSTER_ID}-chaos-reader" \
  --skip-final-snapshot \
  --region "$REGION" 2>/dev/null || true

# Wait for deletion if it was in progress
sleep 5

aws rds create-db-instance \
  --db-instance-identifier "${CLUSTER_ID}-chaos-reader" \
  --db-cluster-identifier "$CLUSTER_ID" \
  --db-instance-class db.r6g.2xlarge \
  --engine aurora-postgresql \
  --region "$REGION" 2>/dev/null || echo "  (Instance may already exist - continuing)"

echo "Oversized reader created: db.r6g.2xlarge (4x the cost of db.r6g.large)"
echo ""

# Step 2: Create multiple unnecessary manual snapshots
echo "Creating unnecessary manual snapshots..."
for i in $(seq 1 3); do
  SNAP_ID="${CLUSTER_ID}-chaos-snap-$(printf '%03d' $i)"
  aws rds create-db-cluster-snapshot \
    --db-cluster-identifier "$CLUSTER_ID" \
    --db-cluster-snapshot-identifier "$SNAP_ID" \
    --region "$REGION" 2>/dev/null || true
  echo "  Created snapshot: $SNAP_ID"
done

echo ""
echo "YOUR MISSION:"
echo "  1. Calculate the current monthly cost of all cluster instances"
echo "  2. Identify the oversized reader instance"
echo "  3. Calculate how much the oversized instance costs per month"
echo "  4. Identify and delete unnecessary manual snapshots"
echo "  5. Delete or resize the oversized reader"
echo "  6. Document the cost impact and remediation"
echo ""
echo "START TIME: $INJECT_TIME"
echo "CLOCK IS TICKING."
