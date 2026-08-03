#!/bin/bash
# SURVIVE 01: State File Disaster - Validation Script
# Verifies that the student successfully recovered from state loss.
#
# DETERMINISTIC: Outputs clear PASS/FAIL for each check.

set -euo pipefail

LAB_DIR="$HOME/terraform-labs/survive01-state-disaster"
PASS=0
FAIL=0

echo "=== SURVIVE 01: Validation ==="
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

# Check 3: State file is valid JSON
echo -n "Check 3: State file is valid JSON... "
if [ -f "terraform.tfstate" ] && python3 -m json.tool terraform.tfstate > /dev/null 2>&1; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - terraform.tfstate is not valid JSON"
  FAIL=$((FAIL + 1))
fi

# Check 4: All 4 resources are in state
echo -n "Check 4: All 4 resources in state... "
RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESOURCE_COUNT" -eq 4 ]; then
  echo "PASS ($RESOURCE_COUNT resources)"
  PASS=$((PASS + 1))
else
  echo "FAIL - Expected 4 resources, found $RESOURCE_COUNT"
  FAIL=$((FAIL + 1))
fi

# Check 5: aurora_config in state
echo -n "Check 5: aurora_config in state... "
if terraform state list 2>/dev/null | grep -q "local_file.aurora_config"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - local_file.aurora_config not found in state"
  FAIL=$((FAIL + 1))
fi

# Check 6: security_group in state
echo -n "Check 6: security_group in state... "
if terraform state list 2>/dev/null | grep -q "local_file.security_group"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - local_file.security_group not found in state"
  FAIL=$((FAIL + 1))
fi

# Check 7: parameter_group in state
echo -n "Check 7: parameter_group in state... "
if terraform state list 2>/dev/null | grep -q "local_file.parameter_group"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - local_file.parameter_group not found in state"
  FAIL=$((FAIL + 1))
fi

# Check 8: backup_policy in state
echo -n "Check 8: backup_policy in state... "
if terraform state list 2>/dev/null | grep -q "local_file.backup_policy"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - local_file.backup_policy not found in state"
  FAIL=$((FAIL + 1))
fi

# Check 9: All .conf files exist on disk
echo -n "Check 9: All .conf files exist on disk... "
MISSING_FILES=0
for f in aurora-config.conf security-group.conf parameter-group.conf backup-policy.conf; do
  if [ ! -f "$f" ]; then
    MISSING_FILES=$((MISSING_FILES + 1))
  fi
done
if [ "$MISSING_FILES" -eq 0 ]; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - $MISSING_FILES .conf files missing"
  FAIL=$((FAIL + 1))
fi

# Check 10: terraform plan shows no changes (state matches reality)
echo -n "Check 10: No drift (terraform plan clean)... "
PLAN_OUTPUT=$(terraform plan -detailed-exitcode 2>&1) || true
PLAN_EXIT=$?
if [ "$PLAN_EXIT" -eq 0 ]; then
  echo "PASS - No changes detected"
  PASS=$((PASS + 1))
elif [ "$PLAN_EXIT" -eq 2 ]; then
  echo "FAIL - Changes detected (state does not match config)"
  FAIL=$((FAIL + 1))
else
  echo "FAIL - terraform plan errored"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS / $((PASS + FAIL))"
echo "Failed: $FAIL / $((PASS + FAIL))"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "STATUS: ALL CHECKS PASSED - State successfully recovered!"
else
  echo "STATUS: $FAIL CHECK(S) FAILED - Review the runbook and try again."
fi
