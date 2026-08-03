#!/bin/bash
# =============================================================================
# SURVIVE Scenario 02: Compliance Violation
# VALIDATE - Checks that the student has fixed all compliance violations.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

echo ""
echo "========================================="
echo "  VALIDATING: Compliance Violation Fix"
echo "========================================="
echo ""

# ---------------------------------------------------------------------------
log_step 1 "Check pgaudit.log is enabled"
# ---------------------------------------------------------------------------

PGAUDIT_LOG=$(aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name "${M09_CLUSTER_PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='pgaudit.log'].ParameterValue" \
    --output text \
    --region "${M09_REGION}" 2>/dev/null || echo "NOT_SET")

if [ "${PGAUDIT_LOG}" != "none" ] && [ "${PGAUDIT_LOG}" != "NOT_SET" ] && [ -n "${PGAUDIT_LOG}" ] && [ "${PGAUDIT_LOG}" != "None" ]; then
    log_success "PASS: pgaudit.log = ${PGAUDIT_LOG}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: pgaudit.log = ${PGAUDIT_LOG} (should not be 'none' or empty)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 2 "Check deletion protection is enabled"
# ---------------------------------------------------------------------------

DEL_PROTECT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].DeletionProtection' \
    --output text \
    --region "${M09_REGION}")

if [ "${DEL_PROTECT}" = "True" ]; then
    log_success "PASS: Deletion protection is enabled"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: Deletion protection is DISABLED"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 3 "Check compliance tags are present"
# ---------------------------------------------------------------------------

CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].DBClusterArn' \
    --output text \
    --region "${M09_REGION}")

COMPLIANCE_TAGS=("DataClassification" "Compliance")

for TAG in "${COMPLIANCE_TAGS[@]}"; do
    TAG_VALUE=$(aws rds list-tags-for-resource \
        --resource-name "${CLUSTER_ARN}" \
        --query "TagList[?Key=='${TAG}'].Value" \
        --output text \
        --region "${M09_REGION}" 2>/dev/null || echo "")

    if [ -n "${TAG_VALUE}" ] && [ "${TAG_VALUE}" != "None" ]; then
        log_success "PASS: Tag '${TAG}' = ${TAG_VALUE}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_fail "FAIL: Tag '${TAG}' is missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# ---------------------------------------------------------------------------
log_step 4 "Check IAM authentication is enabled"
# ---------------------------------------------------------------------------

IAM_AUTH=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
    --output text \
    --region "${M09_REGION}")

if [ "${IAM_AUTH}" = "True" ]; then
    log_success "PASS: IAM database authentication is enabled"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: IAM database authentication is DISABLED"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 5 "Check encryption at rest"
# ---------------------------------------------------------------------------

ENCRYPTED=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].StorageEncrypted' \
    --output text \
    --region "${M09_REGION}")

if [ "${ENCRYPTED}" = "True" ]; then
    log_success "PASS: Storage encryption is enabled"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: Storage encryption is DISABLED (cannot be fixed in-place)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_validation_summary
