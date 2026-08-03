#!/usr/bin/env bash
# survive/03-instance-stopped/validate.sh
# Verifies that all expected instances are running in the Aurora cluster
# after the reader-missing scenario.
#
# Required environment variables:
#   CLUSTER_ID       - Aurora cluster identifier (default: devops-lab-cluster)
#   REGION           - AWS region (default: us-east-1)
#   DB_USER          - Database username (default: clusteradmin)
#   DB_NAME          - Database name (default: devopsdb)
#   PGPASSWORD       - Database password (must be set)
#   EXPECTED_COUNT   - Expected number of instances (default: 3)
#
# Usage:
#   export CLUSTER_ID=devops-lab-cluster
#   export REGION=us-east-1
#   export PGPASSWORD=YourPassword
#   bash validate.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${REGION:-us-east-1}"
DB_USER="${DB_USER:-clusteradmin}"
DB_NAME="${DB_NAME:-devopsdb}"
DB_PORT="5432"
EXPECTED_COUNT="${EXPECTED_COUNT:-3}"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "[PASS]  $1"
  (( PASS_COUNT++ )) || true
}

fail() {
  echo "[FAIL]  $1"
  if [[ -n "${2:-}" ]]; then
    echo "        Hint: $2"
  fi
  (( FAIL_COUNT++ )) || true
}

echo ""
echo "========================================"
echo "  VALIDATE: Reader Instance Missing"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Get cluster info
# ---------------------------------------------------------------------------
CLUSTER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Endpoint" \
  --output text 2>/dev/null || echo "")

READER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].ReaderEndpoint" \
  --output text 2>/dev/null || echo "")

# ---------------------------------------------------------------------------
# Check 1 - Cluster is available
# ---------------------------------------------------------------------------
echo "[INFO]  Check 1: Aurora cluster status"

CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Status" \
  --output text 2>/dev/null || echo "not-found")

if [[ "$CLUSTER_STATUS" == "available" ]]; then
  pass "Aurora cluster $CLUSTER_ID is available"
else
  fail "Aurora cluster status: $CLUSTER_STATUS" "Expected: available"
fi

# ---------------------------------------------------------------------------
# Check 2 - Correct number of cluster members
# ---------------------------------------------------------------------------
echo "[INFO]  Check 2: Cluster has $EXPECTED_COUNT instances"

MEMBER_COUNT=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].DBClusterMembers | length(@)" \
  --output text 2>/dev/null || echo "0")

if [[ "$MEMBER_COUNT" -ge "$EXPECTED_COUNT" ]]; then
  pass "Cluster has $MEMBER_COUNT instance(s) (expected: $EXPECTED_COUNT)"
else
  fail "Cluster has $MEMBER_COUNT instance(s) (expected: $EXPECTED_COUNT)" \
    "Add reader: aws rds create-db-instance --db-instance-identifier devops-lab-cluster-reader-2 --db-cluster-identifier $CLUSTER_ID --db-instance-class db.r6g.large --engine aurora-postgresql --publicly-accessible"
fi

# ---------------------------------------------------------------------------
# Check 3 - All instances are available
# ---------------------------------------------------------------------------
echo "[INFO]  Check 3: All instances are in 'available' status"

INSTANCE_STATUSES=$(aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}" \
  --output json 2>/dev/null)

NOT_AVAILABLE=$(echo "$INSTANCE_STATUSES" | python3 -c "
import sys, json
instances = json.load(sys.stdin)
bad = [i for i in instances if i['Status'] != 'available']
for b in bad:
    print(f\"  {b['ID']}: {b['Status']}\")
print(len(bad))
" 2>/dev/null || echo "1")

BAD_COUNT=$(echo "$NOT_AVAILABLE" | tail -1)

if [[ "$BAD_COUNT" == "0" ]]; then
  pass "All instances are available"
else
  fail "Some instances are not available:" \
    "Wait for instances to finish creating/starting"
  echo "$NOT_AVAILABLE" | head -n -1
fi

# ---------------------------------------------------------------------------
# Check 4 - Cluster has exactly 1 writer
# ---------------------------------------------------------------------------
echo "[INFO]  Check 4: Cluster has exactly 1 writer"

WRITER_COUNT=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].DBClusterMembers[?IsClusterWriter==\`true\`] | length(@)" \
  --output text 2>/dev/null || echo "0")

if [[ "$WRITER_COUNT" == "1" ]]; then
  pass "Cluster has exactly 1 writer"
else
  fail "Cluster has $WRITER_COUNT writer(s) (expected: 1)"
fi

# ---------------------------------------------------------------------------
# Check 5 - Writer is reachable
# ---------------------------------------------------------------------------
echo "[INFO]  Check 5: Writer endpoint is reachable"

if [[ -n "$CLUSTER_EP" ]]; then
  QUERY_RESULT=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT 'connected'" 2>/dev/null || echo "failed")

  if [[ "$QUERY_RESULT" == "connected" ]]; then
    pass "Writer endpoint is reachable and accepting connections"
  else
    fail "Writer endpoint connection failed"
  fi
else
  fail "No cluster endpoint found"
fi

# ---------------------------------------------------------------------------
# Check 6 - Reader endpoint is reachable
# ---------------------------------------------------------------------------
echo "[INFO]  Check 6: Reader endpoint is reachable"

if [[ -n "$READER_EP" ]]; then
  QUERY_RESULT=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$READER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT 'connected'" 2>/dev/null || echo "failed")

  if [[ "$QUERY_RESULT" == "connected" ]]; then
    pass "Reader endpoint is reachable and accepting connections"
  else
    fail "Reader endpoint connection failed" \
      "Make sure at least one reader is available"
  fi
else
  fail "No reader endpoint found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================"
echo "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "[WARN]  Some checks failed. See details above."
  exit 1
else
  echo "[PASS]  All checks passed."
  exit 0
fi
