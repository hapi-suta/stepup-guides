#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 02: Validate - Compliance Violation Remediated
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 02: Validation - Compliance Violation"

t8_validate_config || exit 1
check_aws_auth || exit 1

PASS_COUNT=0
FAIL_COUNT=0

# Load inject state
if [[ -f "${SCRIPT_DIR}/.inject-state" ]]; then
  source "${SCRIPT_DIR}/.inject-state"
else
  log_error ".inject-state not found. Was inject.sh run first?"
  exit 1
fi

log_info "Validating remediation for violation instance: ${VIOLATION_INSTANCE_ID}"

# -----------------------------------------------------------------------
# Check 1: Unencrypted instance is deleted
# -----------------------------------------------------------------------
log_step "Check 1: Unencrypted violation instance is deleted"

INSTANCE_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "${VIOLATION_INSTANCE_ID}" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region "${T8_REGION}" 2>/dev/null || echo "NOT_FOUND")

if [[ "${INSTANCE_STATUS}" == "NOT_FOUND" || "${INSTANCE_STATUS}" == "" ]]; then
  validate_check "Unencrypted instance '${VIOLATION_INSTANCE_ID}' is deleted" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
elif [[ "${INSTANCE_STATUS}" == "deleting" ]]; then
  log_warn "Instance is currently being deleted. Status: deleting"
  log_warn "Re-run validate.sh in a few minutes."
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  validate_check "Unencrypted instance '${VIOLATION_INSTANCE_ID}' is deleted" "fail" \
    "Instance status: ${INSTANCE_STATUS}"
  echo ""
  echo "  The violation instance still exists. To delete it:"
  echo ""
  echo "  # First disable deletion protection (if set)"
  echo "  aws rds modify-db-instance \\"
  echo "    --db-instance-identifier ${VIOLATION_INSTANCE_ID} \\"
  echo "    --no-deletion-protection --apply-immediately \\"
  echo "    --region ${T8_REGION}"
  echo ""
  echo "  # Then delete"
  echo "  aws rds delete-db-instance \\"
  echo "    --db-instance-identifier ${VIOLATION_INSTANCE_ID} \\"
  echo "    --skip-final-snapshot \\"
  echo "    --region ${T8_REGION}"
  echo ""
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 2: No unencrypted production-tagged instances remain
# -----------------------------------------------------------------------
log_step "Check 2: No unencrypted instances tagged as production"

UNENCRYPTED_PROD=$(aws rds describe-db-instances \
  --query 'DBInstances[?StorageEncrypted==`false`].DBInstanceIdentifier' \
  --output text \
  --region "${T8_REGION}" 2>/dev/null)

if [[ -z "${UNENCRYPTED_PROD}" ]]; then
  validate_check "No unencrypted RDS instances in account" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Unencrypted instances still exist" "fail" \
    "Unencrypted instances: ${UNENCRYPTED_PROD}"
  echo "  Review each instance - are they development-only, or do they need encryption?"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 3: AWS Config rule rds-storage-encrypted exists
# -----------------------------------------------------------------------
log_step "Check 3: AWS Config rule for encryption is active"

CONFIG_RULE_STATUS=$(aws configservice describe-config-rule-compliance-summary \
  --region "${T8_REGION}" 2>/dev/null | \
  python3 -c "import sys,json; data=json.load(sys.stdin); rules=[r for r in data.get('GroupedResourceCounts',[]) if True]; print('EXISTS')" 2>/dev/null || echo "UNKNOWN")

ENCRYPTION_RULE=$(aws configservice describe-config-rules \
  --config-rule-names rds-storage-encrypted \
  --region "${T8_REGION}" \
  --query 'ConfigRules[0].ConfigRuleState' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${ENCRYPTION_RULE}" == "ACTIVE" ]]; then
  validate_check "AWS Config rule 'rds-storage-encrypted' is active" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "AWS Config rule 'rds-storage-encrypted' is active" "fail" \
    "Rule state: ${ENCRYPTION_RULE}"
  echo "  Deploy the Config rule from Build Guide 02 to detect future violations automatically."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 4: Existing instance (used in this lab) is encrypted
# -----------------------------------------------------------------------
log_step "Check 4: Primary lab instance is encrypted"

PRIMARY_ENCRYPTED=$(get_instance_attr "StorageEncrypted")

if [[ "${PRIMARY_ENCRYPTED}" == "True" ]]; then
  validate_check "Primary instance '${T8_INSTANCE_ID}' is encrypted" "pass"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Primary instance '${T8_INSTANCE_ID}' is encrypted" "fail" \
    "StorageEncrypted: ${PRIMARY_ENCRYPTED}"
  echo "  This is a separate finding - the primary lab instance itself is not encrypted."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Cleanup: Remove inject state if all checks pass
# -----------------------------------------------------------------------
if [[ ${FAIL_COUNT} -eq 0 ]]; then
  rm -f "${SCRIPT_DIR}/.inject-state"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "==========================================="
echo "VALIDATION SUMMARY"
echo "==========================================="
echo "Checks passed:  ${PASS_COUNT}"
echo "Checks failed:  ${FAIL_COUNT}"
echo ""

if [[ ${FAIL_COUNT} -eq 0 ]]; then
  log_success "Scenario 02 RESOLVED: All checks pass."
  echo ""
  echo "What you demonstrated:"
  echo "  - Detected an unencrypted production-tagged RDS instance"
  echo "  - Assessed the risk (data presence, network exposure)"
  echo "  - Remediated by deleting the violation instance (or snapshot+recreate)"
  echo "  - Verified AWS Config continuous monitoring is in place"
else
  log_fail "Scenario 02 NOT FULLY RESOLVED: ${FAIL_COUNT} check(s) still failing."
fi
echo ""
