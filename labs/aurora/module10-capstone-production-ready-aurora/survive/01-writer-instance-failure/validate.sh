#!/usr/bin/env bash
# SURVIVE Scenario 01: Writer Instance Failure - Validation
# Checks that the cluster recovered from failover successfully.
#
# Usage: bash validate.sh
# Requires: AWS CLI configured, CLUSTER_ID environment variable set

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
echo "  Validating Scenario 01: Writer Instance Failure"
echo "============================================="
echo ""

# Check 1: Cluster is available
CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Status' --output text --region "$REGION" 2>/dev/null || echo "not-found")
if [[ "$CLUSTER_STATUS" == "available" ]]; then
  check "Cluster is available" "PASS"
else
  check "Cluster status: $CLUSTER_STATUS (expected: available)" "FAIL"
fi

# Check 2: A writer instance exists
WRITER_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
  --output text --region "$REGION" 2>/dev/null || echo "")
if [[ -n "$WRITER_ID" && "$WRITER_ID" != "None" ]]; then
  check "Writer instance exists: $WRITER_ID" "PASS"
else
  check "No writer instance found" "FAIL"
fi

# Check 3: Writer instance is available
if [[ -n "$WRITER_ID" && "$WRITER_ID" != "None" ]]; then
  WRITER_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$WRITER_ID" \
    --query 'DBInstances[0].DBInstanceStatus' --output text --region "$REGION" 2>/dev/null || echo "unknown")
  if [[ "$WRITER_STATUS" == "available" ]]; then
    check "Writer instance is available" "PASS"
  else
    check "Writer instance status: $WRITER_STATUS (expected: available)" "FAIL"
  fi
fi

# Check 4: Cluster endpoint resolves
ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Endpoint' --output text --region "$REGION" 2>/dev/null || echo "")
if [[ -n "$ENDPOINT" ]]; then
  RESOLVED=$(dig +short "$ENDPOINT" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" ]]; then
    check "Cluster endpoint resolves: $ENDPOINT -> $RESOLVED" "PASS"
  else
    check "Cluster endpoint does not resolve: $ENDPOINT" "FAIL"
  fi
fi

# Check 5: At least one reader exists
READER_COUNT=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`false`] | length(@)' \
  --output text --region "$REGION" 2>/dev/null || echo "0")
if [[ "$READER_COUNT" -ge 1 ]]; then
  check "Reader instance(s) exist: $READER_COUNT" "PASS"
else
  check "No reader instances found" "FAIL"
fi

# Check 6: Failover event exists in recent history
FAILOVER_EVENTS=$(aws rds describe-events \
  --source-identifier "$CLUSTER_ID" \
  --source-type db-cluster \
  --duration 60 \
  --query 'Events[?contains(Message, `failover`) || contains(Message, `promoted`)] | length(@)' \
  --output text --region "$REGION" 2>/dev/null || echo "0")
if [[ "$FAILOVER_EVENTS" -gt 0 ]]; then
  check "Failover event found in cluster history" "PASS"
else
  check "No failover event found (may have expired from event history)" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - Review failed checks above"
  exit 1
else
  echo "  STATUS: PASS - Failover recovery verified"
  exit 0
fi
