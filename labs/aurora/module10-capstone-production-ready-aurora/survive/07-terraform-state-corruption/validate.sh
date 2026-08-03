#!/usr/bin/env bash
# SURVIVE Scenario 07: Terraform State Corruption - Validation
# Verifies the Terraform state was restored and matches AWS reality.
#
# Usage: bash validate.sh

set -euo pipefail

TERRAFORM_DIR="${TERRAFORM_DIR:-$HOME/capstone-aurora/terraform}"
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
echo "  Validating Scenario 07: Terraform State"
echo "============================================="
echo ""

# Check 1: State file exists
if [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
  check "Terraform state file exists" "PASS"
else
  check "Terraform state file missing" "FAIL"
fi

# Check 2: Aurora cluster is in state
cd "$TERRAFORM_DIR"
CLUSTER_IN_STATE=$(terraform state list 2>/dev/null | grep -c "aws_rds_cluster\.aurora" || echo "0")
if [[ "$CLUSTER_IN_STATE" -ge 1 ]]; then
  check "Aurora cluster resource in state" "PASS"
else
  check "Aurora cluster resource missing from state" "FAIL"
fi

# Check 3: Writer instance is in state
WRITER_IN_STATE=$(terraform state list 2>/dev/null | grep -c "aws_rds_cluster_instance\.writer" || echo "0")
if [[ "$WRITER_IN_STATE" -ge 1 ]]; then
  check "Writer instance in state" "PASS"
else
  check "Writer instance missing from state" "FAIL"
fi

# Check 4: Reader instance is in state
READER_IN_STATE=$(terraform state list 2>/dev/null | grep -c "aws_rds_cluster_instance\.reader" || echo "0")
if [[ "$READER_IN_STATE" -ge 1 ]]; then
  check "Reader instance in state" "PASS"
else
  check "Reader instance missing from state" "FAIL"
fi

# Check 5: terraform plan shows no destructive changes
PLAN_OUTPUT=$(terraform plan -var-file=production.tfvars -no-color 2>&1 || true)
DESTROY_COUNT=$(echo "$PLAN_OUTPUT" | grep -c "will be destroyed\|must be replaced" || echo "0")
if [[ "$DESTROY_COUNT" == "0" ]]; then
  check "No destructive changes in plan" "PASS"
else
  check "Plan shows $DESTROY_COUNT destructive change(s)" "FAIL"
fi

# Check 6: Actual cluster is still healthy
CLUSTER_STATUS=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Status' --output text --region "$REGION" 2>/dev/null || echo "not-found")
if [[ "$CLUSTER_STATUS" == "available" ]]; then
  check "Actual cluster is still available" "PASS"
else
  check "Cluster status: $CLUSTER_STATUS" "FAIL"
fi

echo ""
echo "============================================="
echo "  Results: $PASS PASS, $FAIL FAIL"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo "  STATUS: FAIL - State not fully recovered"
  exit 1
else
  echo "  STATUS: PASS - Terraform state matches reality"
  exit 0
fi
