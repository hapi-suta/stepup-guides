#!/usr/bin/env bash
# Scenario 02 - IAM Token Expired
# validate.sh: Verifies the student can generate a fresh token and connect.
#
# Usage:
#   export CLUSTER_ID="devops-lab-cluster"
#   export CLUSTER_ENDPOINT="your-cluster-endpoint"
#   export MASTER_USER="postgres"
#   export MASTER_PASSWORD="your-password"
#   export AWS_REGION="us-east-1"
#   bash survive/02-iam-token-expired/validate.sh

set -euo pipefail

echo "============================================"
echo "  Scenario 02 - Validating: IAM Token Auth"
echo "============================================"

# ── Validate required variables ──────────────────────────────────────────────
for var in CLUSTER_ID CLUSTER_ENDPOINT MASTER_USER MASTER_PASSWORD AWS_REGION; do
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

# ── Check 1: IAM auth is enabled on the cluster ────────────────────────────
echo "[CHECK 1] IAM database authentication is enabled"

IAM_ENABLED=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
  --output text \
  --region "$AWS_REGION")

if [[ "$IAM_ENABLED" == "True" ]]; then
  check_pass "IAM database authentication is enabled"
else
  check_fail "IAM database authentication is disabled (got: $IAM_ENABLED)"
fi

# ── Check 2: The PostgreSQL role exists ─────────────────────────────────────
echo "[CHECK 2] PostgreSQL role 'iam_scenario_user' exists"

ROLE_EXISTS=$(PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT rolname FROM pg_roles WHERE rolname = 'iam_scenario_user';" 2>/dev/null)

if [[ "$ROLE_EXISTS" == "iam_scenario_user" ]]; then
  check_pass "Role 'iam_scenario_user' exists in PostgreSQL"
else
  check_fail "Role 'iam_scenario_user' not found in PostgreSQL"
fi

# ── Check 3: The role has rds_iam ──────────────────────────────────────────
echo "[CHECK 3] Role 'iam_scenario_user' has rds_iam granted"

RDS_IAM_GRANTED=$(PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require" \
  --tuples-only --no-align \
  --command="SELECT COUNT(*) FROM pg_auth_members am
             JOIN pg_roles r ON r.oid = am.member
             JOIN pg_roles m ON m.oid = am.roleid
             WHERE r.rolname = 'iam_scenario_user'
               AND m.rolname = 'rds_iam';" 2>/dev/null)

if [[ "$RDS_IAM_GRANTED" == "1" ]]; then
  check_pass "rds_iam is granted to 'iam_scenario_user'"
else
  check_fail "rds_iam is NOT granted to 'iam_scenario_user'"
fi

# ── Check 4: Fresh IAM token can be generated and used to connect ──────────
echo "[CHECK 4] Fresh IAM token can be generated and used to connect"

FRESH_TOKEN=$(aws rds generate-db-auth-token \
  --hostname "$CLUSTER_ENDPOINT" \
  --port 5432 \
  --region "$AWS_REGION" \
  --username iam_scenario_user 2>/dev/null || true)

if [[ -z "$FRESH_TOKEN" ]]; then
  check_fail "Could not generate IAM auth token - check AWS CLI credentials and IAM policy"
else
  TOKEN_CONNECT=$(PGPASSWORD="$FRESH_TOKEN" psql \
    "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=iam_scenario_user sslmode=require" \
    --tuples-only --no-align \
    --command="SELECT 'iam_connected';" 2>&1 || true)

  if echo "$TOKEN_CONNECT" | grep -q "iam_connected"; then
    check_pass "Fresh IAM token generated and connection successful"
  else
    check_fail "Fresh IAM token generated but connection failed: ${TOKEN_CONNECT:0:120}"
  fi
fi

# ── Check 5: Stale token is rejected (informational) ──────────────────────
echo "[CHECK 5] Verifying stale token handling (informational)"
STALE_TOKEN_FILE="/tmp/module04-scenario02-stale-token.txt"
if [[ -f "$STALE_TOKEN_FILE" ]]; then
  FILE_AGE_SECONDS=$(( $(date +%s) - $(stat -f %m "$STALE_TOKEN_FILE" 2>/dev/null || stat -c %Y "$STALE_TOKEN_FILE" 2>/dev/null || echo 0) ))
  if [[ $FILE_AGE_SECONDS -gt 900 ]]; then
    STALE_RESULT=$(PGPASSWORD="$(cat $STALE_TOKEN_FILE)" psql \
      "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=iam_scenario_user sslmode=require" \
      --tuples-only --no-align \
      --command="SELECT 1;" 2>&1 || true)
    if echo "$STALE_RESULT" | grep -q "PAM authentication failed\|authentication failed"; then
      check_pass "Stale token correctly rejected (token expired after 15 minutes)"
    else
      echo "[WARN] Stale token check inconclusive - result: ${STALE_RESULT:0:80}"
    fi
  else
    echo "[WARN] Stale token file is only ${FILE_AGE_SECONDS}s old - not yet expired (needs 900s). Skipping."
  fi
else
  echo "[WARN] Stale token file not found at $STALE_TOKEN_FILE - skipping stale token check."
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "============================================"

if [[ $CHECKS_FAILED -eq 0 ]]; then
  echo "  PASS - All checks passed. IAM token authentication is working."
else
  echo "  FAIL - Some checks failed. Review and fix the issues above."
fi

exit $CHECKS_FAILED
