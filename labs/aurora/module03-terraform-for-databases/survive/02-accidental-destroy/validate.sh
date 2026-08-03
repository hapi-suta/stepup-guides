#!/bin/bash
# SURVIVE 02: Accidental Destroy - Validation Script
# Verifies that the student recovered from accidental destroy
# and implemented prevent_destroy safeguards.
#
# DETERMINISTIC: Outputs clear PASS/FAIL for each check.

set -euo pipefail

LAB_DIR="$HOME/terraform-labs/survive02-accidental-destroy"
PASS=0
FAIL=0

echo "=== SURVIVE 02: Validation ==="
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

# Check 3: All 5 resources are in state
echo -n "Check 3: All 5 resources in state... "
RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESOURCE_COUNT" -eq 5 ]; then
  echo "PASS ($RESOURCE_COUNT resources)"
  PASS=$((PASS + 1))
else
  echo "FAIL - Expected 5 resources, found $RESOURCE_COUNT"
  FAIL=$((FAIL + 1))
fi

# Check 4: All .conf files exist on disk
echo -n "Check 4: All .conf files exist on disk... "
MISSING_FILES=0
for f in aurora-cluster-prod.conf writer-prod.conf reader-prod.conf security-group-prod.conf parameter-group-prod.conf; do
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

# Check 5: terraform plan shows no changes
echo -n "Check 5: No drift (terraform plan clean)... "
PLAN_OUTPUT=$(terraform plan -detailed-exitcode 2>&1) || true
PLAN_EXIT=$?
if [ "$PLAN_EXIT" -eq 0 ]; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - Changes detected or plan errored"
  FAIL=$((FAIL + 1))
fi

# Check 6: prevent_destroy is set on aurora_cluster
echo -n "Check 6: prevent_destroy on aurora_cluster... "
if grep -A3 'resource "local_file" "aurora_cluster"' main.tf | grep -q "prevent_destroy" 2>/dev/null || \
   grep -A10 'resource "local_file" "aurora_cluster"' main.tf | grep -q "prevent_destroy.*true" 2>/dev/null; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - prevent_destroy not found on aurora_cluster"
  FAIL=$((FAIL + 1))
fi

# Check 7: prevent_destroy is set on writer_instance
echo -n "Check 7: prevent_destroy on writer_instance... "
if grep -A3 'resource "local_file" "writer_instance"' main.tf | grep -q "prevent_destroy" 2>/dev/null || \
   grep -A10 'resource "local_file" "writer_instance"' main.tf | grep -q "prevent_destroy.*true" 2>/dev/null; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - prevent_destroy not found on writer_instance"
  FAIL=$((FAIL + 1))
fi

# Check 8: prevent_destroy is set on reader_instance
echo -n "Check 8: prevent_destroy on reader_instance... "
if grep -A3 'resource "local_file" "reader_instance"' main.tf | grep -q "prevent_destroy" 2>/dev/null || \
   grep -A10 'resource "local_file" "reader_instance"' main.tf | grep -q "prevent_destroy.*true" 2>/dev/null; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL - prevent_destroy not found on reader_instance"
  FAIL=$((FAIL + 1))
fi

# Check 9: terraform destroy is blocked
echo -n "Check 9: terraform destroy is blocked... "
DESTROY_OUTPUT=$(terraform destroy -auto-approve 2>&1) || true
if echo "$DESTROY_OUTPUT" | grep -q "cannot be destroyed\|prevent_destroy"; then
  echo "PASS - destroy correctly blocked"
  PASS=$((PASS + 1))
else
  echo "FAIL - destroy was NOT blocked (prevent_destroy not working)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS / $((PASS + FAIL))"
echo "Failed: $FAIL / $((PASS + FAIL))"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "STATUS: ALL CHECKS PASSED - Resources recovered and safeguards in place!"
else
  echo "STATUS: $FAIL CHECK(S) FAILED - Review the runbook and try again."
fi
