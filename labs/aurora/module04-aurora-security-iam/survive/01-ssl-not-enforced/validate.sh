#!/usr/bin/env bash
# Scenario 01 - SSL Not Enforced
# validate.sh: Verifies that SSL enforcement has been restored.
#
# Usage:
#   export CLUSTER_ID="devops-lab-cluster"
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export PARAM_GROUP_NAME="devops-lab-cluster-params"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/01-ssl-not-enforced/validate.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 01 - Validating: SSL Enforcement"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ID CLUSTER_ENDPOINT PARAM_GROUP_NAME MASTER_USER MASTER_PASSWORD AWS_REGION; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Export it before running this script."
    exit 1
  fi
done

CHECKS_PASSED=0
CHECKS_FAILED=0

check_pass() {
  echo "[PASS] $1"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_fail() {
  echo "[FAIL] $1"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

echo ""

# ── Check 1: Parameter group has rds.force_ssl = 1 ──────────────────────────
echo "[CHECK 1] rds.force_ssl parameter value"

FORCE_SSL=$(aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
  --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue | [0]" \
  --output text \
  --region "$AWS_REGION" 2>/dev/null || echo "not set")

if [[ "$FORCE_SSL" == "1" ]]; then
  check_pass "rds.force_ssl = 1 in parameter group '$PARAM_GROUP_NAME'"
else
  check_fail "rds.force_ssl = '${FORCE_SSL}' in parameter group '$PARAM_GROUP_NAME' (expected: 1)"
fi

# ── Check 2: Instance rejects non-SSL connections ───────────────────────────
echo "[CHECK 2] Aurora cluster rejects non-SSL connection"

NON_SSL_RESULT=$(PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=disable" \
  --command="SELECT 1;" 2>&1 || true)

if echo "$NON_SSL_RESULT" | grep -q "SSL off\|SSL connection is required"; then
  check_pass "Aurora cluster rejected non-SSL connection"
else
  check_fail "Aurora cluster accepted a non-SSL connection (got: ${NON_SSL_RESULT:0:100})"
fi

# ── Check 3: SSL connections still work ─────────────────────────────────────
echo "[CHECK 3] SSL connections still accepted"

SSL_RESULT=$(PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT 'ssl_ok';" 2>&1 || true)

if echo "$SSL_RESULT" | grep -q "ssl_ok"; then
  check_pass "SSL connections accepted successfully"
else
  check_fail "SSL connection also failed - check cluster status"
fi

# ── Check 4: Parameter group is assigned to the cluster ─────────────────────
echo "[CHECK 4] Custom parameter group assigned to cluster"

ASSIGNED_PG=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].DBClusterParameterGroup' \
  --output text \
  --region "$AWS_REGION")

if [[ "$ASSIGNED_PG" == "$PARAM_GROUP_NAME" ]]; then
  check_pass "Parameter group '$PARAM_GROUP_NAME' is assigned to the cluster"
else
  check_fail "Cluster is using parameter group '$ASSIGNED_PG', expected '$PARAM_GROUP_NAME'"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "============================================"

if [[ $CHECKS_FAILED -eq 0 ]]; then
  echo "  PASS - All checks passed. SSL enforcement is restored."
else
  echo "  FAIL - Some checks failed. Review and fix the issues above."
fi

exit $CHECKS_FAILED
