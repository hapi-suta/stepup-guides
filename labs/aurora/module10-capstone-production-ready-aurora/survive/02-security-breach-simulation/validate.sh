#!/usr/bin/env bash
# SURVIVE Scenario 02: Security Breach Simulation - Validation
# Checks that the breach was properly contained and remediated.
#
# Usage: bash validate.sh
# Requires: AWS CLI, psql, DB_HOST/DB_USER/DB_PASSWORD set

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"
DB_HOST="${DB_HOST:-$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Endpoint' --output text --region "$REGION")}"
DB_USER="${DB_USER:-dbadmin}"
DB_PASSWORD="${DB_PASSWORD:?ERROR: Set DB_PASSWORD environment variable}"

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
echo "  Validating Scenario 02: Security Breach"
echo "============================================="
echo ""

# Check 1: compromised_user cannot login
CAN_LOGIN=$(PGPASSWORD="weak_password_123" psql -h "$DB_HOST" -U compromised_user -d postgres \
  -tAc "SELECT 1;" 2>/dev/null || echo "blocked")
if [[ "$CAN_LOGIN" == "blocked" ]]; then
  check "compromised_user cannot login" "PASS"
else
  check "compromised_user can still login" "FAIL"
fi

# Check 2: compromised_user has no privileges on app schema
PRIV_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT count(*) FROM information_schema.role_table_grants
  WHERE grantee = 'compromised_user';
" 2>/dev/null || echo "0")
if [[ "$PRIV_COUNT" == "0" || -z "$PRIV_COUNT" ]]; then
  check "compromised_user has no table privileges" "PASS"
else
  check "compromised_user still has $PRIV_COUNT privilege(s)" "FAIL"
fi

# Check 3: compromised_user either dropped or has NOLOGIN
USER_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'compromised_user') THEN 'dropped'
    WHEN NOT rolcanlogin THEN 'locked'
    ELSE 'active'
  END
  FROM pg_roles WHERE rolname = 'compromised_user'
  UNION ALL SELECT 'dropped' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'compromised_user');
" 2>/dev/null | head -1 | tr -d ' ')
if [[ "$USER_EXISTS" == "dropped" || "$USER_EXISTS" == "locked" ]]; then
  check "compromised_user is $USER_EXISTS" "PASS"
else
  check "compromised_user is still active" "FAIL"
fi

# Check 4: No unauthorized superusers
SUPERUSER_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT count(*) FROM pg_roles WHERE rolsuper = true AND rolname != 'rdsadmin';
" 2>/dev/null || echo "unknown")
if [[ "$SUPERUSER_COUNT" == "0" ]]; then
  check "No unauthorized superusers" "PASS"
else
  check "Found $SUPERUSER_COUNT unauthorized superuser(s)" "FAIL"
fi

# Check 5: Auth failure metric filter exists
FILTER_EXISTS=$(aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/$CLUSTER_ID/postgresql \
  --query "metricFilters[?filterPattern=='authentication failed'] | length(@)" \
  --output text --region "$REGION" 2>/dev/null || echo "0")
if [[ "$FILTER_EXISTS" -gt 0 ]]; then
  check "Authentication failure metric filter exists" "PASS"
else
  check "No authentication failure metric filter" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - Breach not fully contained"
  exit 1
else
  echo "  STATUS: PASS - Breach contained and remediated"
  exit 0
fi
