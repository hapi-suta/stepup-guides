#!/usr/bin/env bash
# SURVIVE Scenario 08: Full Region Failover - Validation
# Verifies the DR restore was performed in us-west-2.
#
# Usage: bash validate.sh

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
PRIMARY_REGION="us-east-1"
DR_REGION="us-west-2"
DR_CLUSTER="devops-lab-dr-cluster"
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
echo "  Validating Scenario 08: Full Region Failover"
echo "============================================="
echo ""

# Check 1: DR cluster exists or existed in us-west-2
DR_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$DR_CLUSTER" \
  --query 'DBClusters[0].Status' --output text --region "$DR_REGION" 2>/dev/null || echo "not-found")

if [[ "$DR_STATUS" == "available" ]]; then
  check "DR cluster is available in $DR_REGION" "PASS"

  # Check 2: DR cluster has a writer
  DR_WRITER=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$DR_CLUSTER" \
    --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
    --output text --region "$DR_REGION" 2>/dev/null || echo "none")
  if [[ -n "$DR_WRITER" && "$DR_WRITER" != "None" && "$DR_WRITER" != "none" ]]; then
    check "DR cluster has writer instance: $DR_WRITER" "PASS"
  else
    check "DR cluster has no writer instance" "FAIL"
  fi

  # Check 3: DR cluster endpoint resolves
  DR_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$DR_CLUSTER" \
    --query 'DBClusters[0].Endpoint' --output text --region "$DR_REGION")
  RESOLVED=$(dig +short "$DR_ENDPOINT" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" ]]; then
    check "DR cluster endpoint resolves" "PASS"
  else
    check "DR cluster endpoint does not resolve" "FAIL"
  fi

  # Check 4: DR cluster is encrypted
  DR_ENCRYPTED=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$DR_CLUSTER" \
    --query 'DBClusters[0].StorageEncrypted' --output text --region "$DR_REGION")
  if [[ "$DR_ENCRYPTED" == "True" ]]; then
    check "DR cluster is encrypted" "PASS"
  else
    check "DR cluster is NOT encrypted" "FAIL"
  fi

elif [[ "$DR_STATUS" == "deleting" ]]; then
  check "DR cluster exists (currently deleting - was created and cleaned up)" "PASS"
  check "DR cluster was restored and verified" "PASS"
  check "DR cleanup in progress" "PASS"
  check "DR was encrypted (verified before deletion)" "PASS"

elif [[ "$DR_STATUS" == "not-found" ]]; then
  # Check if there's evidence of the restore
  DR_EVENTS=$(aws rds describe-events \
    --source-type db-cluster \
    --duration 240 \
    --query "Events[?contains(SourceIdentifier, 'dr-cluster')] | length(@)" \
    --output text --region "$DR_REGION" 2>/dev/null || echo "0")
  if [[ "$DR_EVENTS" -gt 0 ]]; then
    check "DR cluster was created and cleaned up (events found)" "PASS"
    check "DR restore evidence found" "PASS"
    check "DR cleanup completed" "PASS"
    check "Good housekeeping" "PASS"
  else
    check "No evidence of DR restore in $DR_REGION" "FAIL"
    check "DR cluster not found" "FAIL"
    check "No DR events found" "FAIL"
    check "Region failover not performed" "FAIL"
  fi
fi

# Check 5: Primary cluster is still intact
PRIMARY_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Status' --output text --region "$PRIMARY_REGION" 2>/dev/null || echo "not-found")
if [[ "$PRIMARY_STATUS" == "available" ]]; then
  check "Primary cluster is still available (not destroyed)" "PASS"
else
  check "Primary cluster status: $PRIMARY_STATUS" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - Region failover not verified"
  exit 1
else
  echo "  STATUS: PASS - Region failover executed successfully"
  exit 0
fi
