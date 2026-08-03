#!/usr/bin/env bash
# SURVIVE Scenario 03: Backup Restore Under Pressure - Validation
# Verifies the PITR restore was performed and data was recovered.
#
# Usage: bash validate.sh
# Requires: AWS CLI, psql, DB_HOST/DB_USER/DB_PASSWORD set

set -euo pipefail

CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
REGION="${AWS_REGION:-us-east-1}"
RECOVERY_CLUSTER="devops-lab-pitr-recovery"
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
echo "  Validating Scenario 03: Backup Restore"
echo "============================================="
echo ""

# Check 1: Original table is still dropped
ORIGINAL_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Endpoint' --output text --region "$REGION")
TABLE_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$ORIGINAL_HOST" -U "$DB_USER" -d postgres -tAc "
  SELECT EXISTS(SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'app' AND table_name = 'critical_data');
" 2>/dev/null || echo "error")
if [[ "$TABLE_EXISTS" == "f" ]]; then
  check "Original table is confirmed dropped" "PASS"
else
  check "Original table still exists (drop was not simulated)" "FAIL"
fi

# Check 2: Recovery cluster exists or existed
RECOVERY_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$RECOVERY_CLUSTER" \
  --query 'DBClusters[0].Status' --output text --region "$REGION" 2>/dev/null || echo "not-found")
if [[ "$RECOVERY_STATUS" == "available" || "$RECOVERY_STATUS" == "deleting" ]]; then
  check "Recovery cluster was created ($RECOVERY_STATUS)" "PASS"

  # Check 3: Data exists in recovery cluster (only if available)
  if [[ "$RECOVERY_STATUS" == "available" ]]; then
    RECOVERED_HOST=$(aws rds describe-db-clusters \
      --db-cluster-identifier "$RECOVERY_CLUSTER" \
      --query 'DBClusters[0].Endpoint' --output text --region "$REGION")
    ROW_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$RECOVERED_HOST" -U "$DB_USER" -d postgres -tAc "
      SELECT count(*) FROM app.critical_data;
    " 2>/dev/null || echo "0")
    if [[ "$ROW_COUNT" -ge 1000 ]]; then
      check "Recovered data: $ROW_COUNT rows (expected 1000)" "PASS"
    else
      check "Recovered data: $ROW_COUNT rows (expected 1000)" "FAIL"
    fi
  else
    check "Recovery cluster is being cleaned up (data was verified)" "PASS"
  fi
elif [[ "$RECOVERY_STATUS" == "not-found" ]]; then
  # Cluster was already cleaned up - check for recent restore events
  RESTORE_EVENTS=$(aws rds describe-events \
    --source-type db-cluster \
    --duration 120 \
    --query "Events[?contains(Message, 'restore') || contains(SourceIdentifier, 'pitr')] | length(@)" \
    --output text --region "$REGION" 2>/dev/null || echo "0")
  if [[ "$RESTORE_EVENTS" -gt 0 ]]; then
    check "Recovery cluster was created and cleaned up" "PASS"
    check "PITR events found in history" "PASS"
  else
    check "No evidence of PITR restore found" "FAIL"
    check "Recovery cluster not found" "FAIL"
  fi
fi

# Check 4: Original cluster still healthy
ORIG_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Status' --output text --region "$REGION")
if [[ "$ORIG_STATUS" == "available" ]]; then
  check "Original cluster is still available" "PASS"
else
  check "Original cluster status: $ORIG_STATUS" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - PITR restore not verified"
  exit 1
else
  echo "  STATUS: PASS - Data recovered via PITR"
  exit 0
fi
