#!/usr/bin/env bash
# survive/01-security-group-lockout/validate.sh
# Verifies that connectivity to the Aurora cluster has been restored
# after the security group lockout scenario.
#
# Required environment variables:
#   CLUSTER_ID       - Aurora cluster identifier (default: devops-lab-cluster)
#   REGION           - AWS region (default: us-east-1)
#   DB_USER          - Database username (default: clusteradmin)
#   DB_NAME          - Database name (default: devopsdb)
#   PGPASSWORD       - Database password (must be set)
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

# ---------------------------------------------------------------------------
# Get cluster info
# ---------------------------------------------------------------------------
CLUSTER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].Endpoint" \
  --output text 2>/dev/null || echo "")

SG_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --region "$REGION" \
  --query "DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId" \
  --output text 2>/dev/null || echo "")

echo ""
echo "========================================"
echo "  VALIDATE: Security Group Lockout"
echo "========================================"
echo ""

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
# Check 2 - Security group has at least one inbound rule on port 5432
# ---------------------------------------------------------------------------
echo "[INFO]  Check 2: Security group has inbound rule on port 5432"

if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
  RULE_COUNT=$(aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --region "$REGION" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\`] | length(@)" \
    --output text 2>/dev/null || echo "0")

  if [[ "$RULE_COUNT" -gt 0 ]]; then
    pass "Security group $SG_ID has $RULE_COUNT inbound rule(s) on port 5432"
  else
    fail "Security group $SG_ID has no inbound rules on port 5432" \
      "Run: aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 5432 --cidr YOUR_IP/32"
  fi
else
  fail "Could not find security group for cluster $CLUSTER_ID"
fi

# ---------------------------------------------------------------------------
# Check 3 - Port 5432 is reachable
# ---------------------------------------------------------------------------
echo "[INFO]  Check 3: Port $DB_PORT is reachable on cluster endpoint"

if [[ -n "$CLUSTER_EP" ]] && nc -z -w 10 "$CLUSTER_EP" "$DB_PORT" 2>/dev/null; then
  pass "Port $DB_PORT is open on $CLUSTER_EP"
else
  fail "Port $DB_PORT is NOT reachable on $CLUSTER_EP" \
    "Security group rule may be pointing to wrong IP or not yet applied"
fi

# ---------------------------------------------------------------------------
# Check 4 - psql can connect and run a query
# ---------------------------------------------------------------------------
echo "[INFO]  Check 4: psql can authenticate and execute a query"

if [[ -n "$CLUSTER_EP" ]]; then
  QUERY_RESULT=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT 'connected'" 2>/dev/null || echo "failed")

  if [[ "$QUERY_RESULT" == "connected" ]]; then
    pass "psql connection and query successful"
  else
    fail "psql connection failed" \
      "Verify: psql -h $CLUSTER_EP -U $DB_USER -d $DB_NAME -p $DB_PORT"
  fi
else
  fail "No cluster endpoint found - cannot test psql"
fi

# ---------------------------------------------------------------------------
# Check 5 - Connected to the writer (not a reader)
# ---------------------------------------------------------------------------
echo "[INFO]  Check 5: Confirming connection is to the writer"

if [[ -n "$CLUSTER_EP" ]]; then
  IS_RECOVERY=$(PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$CLUSTER_EP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -p "$DB_PORT" \
    -t -A \
    -c "SELECT pg_is_in_recovery()" 2>/dev/null || echo "error")

  if [[ "$IS_RECOVERY" == "f" ]]; then
    pass "Connected to writer (pg_is_in_recovery = false)"
  elif [[ "$IS_RECOVERY" == "t" ]]; then
    fail "Connected to a reader (pg_is_in_recovery = true)" \
      "The cluster endpoint should always route to the writer"
  else
    fail "Could not determine instance role" "psql query failed"
  fi
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
