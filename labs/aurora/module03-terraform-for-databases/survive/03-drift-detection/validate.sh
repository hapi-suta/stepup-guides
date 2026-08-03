#!/bin/bash
# SURVIVE 03: Drift Detection - Validation Script
# Verifies that the student reconciled all drift so state matches reality.
#
# DETERMINISTIC: Outputs clear PASS/FAIL for each check.

set -euo pipefail

LAB_DIR="$HOME/terraform-labs/survive03-drift-detection"
PASS=0
FAIL=0

echo "=== SURVIVE 03: Validation ==="
echo ""

# Check 1: Lab directory exists
echo -n "Check 1: Lab directory exists... "
if [ -d "$LAB_DIR" ]; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - $LAB_DIR does not exist"
  FAIL=$((FAIL + 1))
  echo ""
  echo "RESULT: $PASS passed, $FAIL failed"
  exit 1
fi

cd "$LAB_DIR"

# Check 2: State file exists
echo -n "Check 2: State file exists... "
if [ -f "terraform.tfstate" ]; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - terraform.tfstate is missing"
  FAIL=$((FAIL + 1))
fi

# Check 3: All 4 resources in state
echo -n "Check 3: All 4 resources in state... "
RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESOURCE_COUNT" -eq 4 ]; then
  echo "PASS ($RESOURCE_COUNT resources)"
  PASS=$((PASS + 1))
else
  echo "FAIL - Expected 4 resources, found $RESOURCE_COUNT"
  FAIL=$((FAIL + 1))
fi

# Check 4: Security group does NOT contain 0.0.0.0/0
echo -n "Check 4: Dangerous SG rule (0.0.0.0/0) removed... "
if [ -f "security-group.conf" ] && ! grep -q "0.0.0.0/0" security-group.conf; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - 0.0.0.0/0 still in security-group.conf (security risk!)"
  FAIL=$((FAIL + 1))
fi

# Check 5: Security group contains original rules
echo -n "Check 5: Original SG rules preserved... "
if [ -f "security-group.conf" ] && grep -q "10.0.0.0/8" security-group.conf && grep -q "172.16.0.0/12" security-group.conf; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - Original SG rules missing"
  FAIL=$((FAIL + 1))
fi

# Check 6: Backup retention is adequate (not reduced to 7)
echo -n "Check 6: Backup retention not dangerously low... "
if [ -f "aurora-config.conf" ] && ! grep -q "backup_retention=7" aurora-config.conf; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - backup_retention is still 7 (too low for production)"
  FAIL=$((FAIL + 1))
fi

# Check 7: All .conf files exist
echo -n "Check 7: All .conf files exist... "
MISSING=0
for f in security-group.conf cluster-params.conf instance-params.conf aurora-config.conf; do
  if [ ! -f "$f" ]; then
    MISSING=$((MISSING + 1))
  fi
done
if [ "$MISSING" -eq 0 ]; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - $MISSING .conf files missing"
  FAIL=$((FAIL + 1))
fi

# Check 8: terraform plan shows no changes (no drift)
echo -n "Check 8: No drift (terraform plan clean)... "
PLAN_OUTPUT=$(terraform plan -detailed-exitcode 2>&1) || true
PLAN_EXIT=$?
if [ "$PLAN_EXIT" -eq 0 ]; then
  echo "PASS - No drift detected"
  PASS=$((PASS + 1))
else
  echo "FAIL - Drift still present (terraform plan shows changes)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS / $((PASS + FAIL))"
echo "Failed: $FAIL / $((PASS + FAIL))"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "STATUS: ALL CHECKS PASSED - All drift reconciled successfully!"
else
  echo "STATUS: $FAIL CHECK(S) FAILED - Review the runbook and try again."
fi
