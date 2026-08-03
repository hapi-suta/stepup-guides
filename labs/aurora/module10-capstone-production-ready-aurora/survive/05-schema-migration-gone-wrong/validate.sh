#!/usr/bin/env bash
# SURVIVE Scenario 05: Schema Migration Gone Wrong - Validation
# Verifies the lock was resolved and the table is accessible.
#
# Usage: bash validate.sh

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
echo "  Validating Scenario 05: Schema Migration"
echo "============================================="
echo ""

# Check 1: No ACCESS EXCLUSIVE locks on app.orders
LOCK_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT count(*) FROM pg_locks l
  JOIN pg_class c ON l.relation = c.oid
  WHERE c.relname = 'orders' AND l.mode = 'AccessExclusiveLock';
" 2>/dev/null || echo "0")
LOCK_COUNT=$(echo "$LOCK_COUNT" | tr -d ' ')
if [[ "$LOCK_COUNT" == "0" ]]; then
  check "No ACCESS EXCLUSIVE locks on app.orders" "PASS"
else
  check "Found $LOCK_COUNT ACCESS EXCLUSIVE lock(s)" "FAIL"
fi

# Check 2: Table is queryable (responds within 5 seconds)
QUERY_RESULT=$(timeout 5 bash -c "PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -U '$DB_USER' -d postgres -tAc 'SELECT count(*) FROM app.orders;'" 2>/dev/null || echo "timeout")
QUERY_RESULT=$(echo "$QUERY_RESULT" | tr -d ' ')
if [[ "$QUERY_RESULT" =~ ^[0-9]+$ && "$QUERY_RESULT" -gt 0 ]]; then
  check "Table is queryable ($QUERY_RESULT rows)" "PASS"
else
  check "Table query failed or timed out ($QUERY_RESULT)" "FAIL"
fi

# Check 3: No blocked queries
BLOCKED=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT count(*) FROM pg_stat_activity
  WHERE wait_event_type = 'Lock' AND state = 'active';
" 2>/dev/null || echo "0")
BLOCKED=$(echo "$BLOCKED" | tr -d ' ')
if [[ "$BLOCKED" == "0" ]]; then
  check "No blocked queries" "PASS"
else
  check "Found $BLOCKED blocked queries" "FAIL"
fi

# Check 4: No long-running transactions (> 5 minutes)
LONG_TX=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT count(*) FROM pg_stat_activity
  WHERE state IN ('active', 'idle in transaction')
  AND query_start < now() - interval '5 minutes'
  AND usename != 'rdsadmin';
" 2>/dev/null || echo "0")
LONG_TX=$(echo "$LONG_TX" | tr -d ' ')
if [[ "$LONG_TX" == "0" ]]; then
  check "No long-running transactions" "PASS"
else
  check "Found $LONG_TX long-running transaction(s)" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - Migration issue not resolved"
  exit 1
else
  echo "  STATUS: PASS - Table accessible, no blocking locks"
  exit 0
fi
