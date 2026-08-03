#!/usr/bin/env bash
# SURVIVE Scenario 04: Cost Runaway - Validation
# Verifies the oversized instance and unnecessary snapshots were removed.
#
# Usage: bash validate.sh

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local status="$2"
  if [[ "$status" == "PASS" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================="
echo "  Validating Scenario 04: Cost Runaway"
echo "============================================="
echo ""

# Check 1: Oversized reader is gone
CHAOS_READER=$(aws rds describe-db-instances \
  --db-instance-identifier "${CLUSTER_ID}-chaos-reader" \
  --query 'DBInstances[0].DBInstanceStatus' --output text --region "$REGION" 2>/dev/null || echo "not-found")
if [[ "$CHAOS_READER" == "not-found" || "$CHAOS_READER" == "deleting" ]]; then
  check "Oversized reader instance removed" "PASS"
else
  check "Oversized reader still exists (status: $CHAOS_READER)" "FAIL"
fi

# Check 2: All remaining instances use the standard class
INSTANCE_CLASSES=$(aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values="$CLUSTER_ID" \
  --query 'DBInstances[?DBInstanceStatus!=`deleting`].DBInstanceClass' \
  --output text --region "$REGION" 2>/dev/null)
OVERSIZED=0
for CLASS in $INSTANCE_CLASSES; do
  if [[ "$CLASS" != "db.r6g.large" && "$CLASS" != "db.t3.medium" ]]; then
    OVERSIZED=$((OVERSIZED + 1))
  fi
done
if [[ $OVERSIZED -eq 0 ]]; then
  check "All instances use expected instance class" "PASS"
else
  check "Found $OVERSIZED oversized instance(s)" "FAIL"
fi

# Check 3: Chaos snapshots deleted
CHAOS_SNAPS=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier "$CLUSTER_ID" \
  --snapshot-type manual \
  --query "DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, 'chaos-snap')] | length(@)" \
  --output text --region "$REGION" 2>/dev/null || echo "0")
if [[ "$CHAOS_SNAPS" == "0" ]]; then
  check "All chaos snapshots deleted" "PASS"
else
  check "Found $CHAOS_SNAPS chaos snapshot(s) remaining" "FAIL"
fi

# Check 4: Cluster is still healthy
CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Status' --output text --region "$REGION")
if [[ "$CLUSTER_STATUS" == "available" ]]; then
  check "Cluster is available" "PASS"
else
  check "Cluster status: $CLUSTER_STATUS" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - Cost issues not fully remediated"
  exit 1
else
  echo "  STATUS: PASS - Cost runaway contained"
  exit 0
fi
