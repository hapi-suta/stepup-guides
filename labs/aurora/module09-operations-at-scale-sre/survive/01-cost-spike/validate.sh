#!/bin/bash
# =============================================================================
# SURVIVE Scenario 01: Cost Spike
# VALIDATE - Checks that the student has remediated all cost issues.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

STATE_FILE="${M09_STATE_DIR}/01-cost-spike.state"

echo ""
echo "========================================="
echo "  VALIDATING: Cost Spike Remediation"
echo "========================================="
echo ""

# ---------------------------------------------------------------------------
log_step 1 "Check log_min_duration_statement is not 0"
# ---------------------------------------------------------------------------

LOG_DURATION=$(aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name "${M09_CLUSTER_PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='log_min_duration_statement'].ParameterValue" \
    --output text \
    --region "${M09_REGION}" 2>/dev/null || echo "UNKNOWN")

if [ "${LOG_DURATION}" != "0" ] && [ "${LOG_DURATION}" != "UNKNOWN" ] && [ -n "${LOG_DURATION}" ]; then
    log_success "PASS: log_min_duration_statement = ${LOG_DURATION} (not verbose)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: log_min_duration_statement = ${LOG_DURATION} (should not be 0)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 2 "Check CloudWatch log retention is set"
# ---------------------------------------------------------------------------

LOG_GROUP="/aws/rds/cluster/${M09_CLUSTER_ID}/postgresql"

RETENTION=$(aws logs describe-log-groups \
    --log-group-name-prefix "${LOG_GROUP}" \
    --query "logGroups[?logGroupName=='${LOG_GROUP}'].retentionInDays" \
    --output text \
    --region "${M09_REGION}" 2>/dev/null || echo "NONE")

if [ "${RETENTION}" != "None" ] && [ "${RETENTION}" != "NONE" ] && [ -n "${RETENTION}" ]; then
    log_success "PASS: CloudWatch log retention = ${RETENTION} days"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    log_fail "FAIL: CloudWatch log retention is not set (logs stored forever)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 3 "Check orphaned snapshot has been deleted"
# ---------------------------------------------------------------------------

SNAPSHOT_ID="${M09_CHAOS_PREFIX}-cost-spike-snapshot"

if aws rds describe-db-cluster-snapshots \
    --db-cluster-snapshot-identifier "${SNAPSHOT_ID}" \
    --region "${M09_REGION}" > /dev/null 2>&1; then
    log_fail "FAIL: Orphaned snapshot ${SNAPSHOT_ID} still exists"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    log_success "PASS: Orphaned snapshot ${SNAPSHOT_ID} has been deleted"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# ---------------------------------------------------------------------------
log_step 4 "Check cost allocation tags are present"
# ---------------------------------------------------------------------------

CLUSTER_ARN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${M09_CLUSTER_ID}" \
    --query 'DBClusters[0].DBClusterArn' \
    --output text \
    --region "${M09_REGION}")

REQUIRED_TAGS=("CostCenter" "Environment" "Team")
TAG_PASS=0
TAG_FAIL=0

for TAG in "${REQUIRED_TAGS[@]}"; do
    TAG_VALUE=$(aws rds list-tags-for-resource \
        --resource-name "${CLUSTER_ARN}" \
        --query "TagList[?Key=='${TAG}'].Value" \
        --output text \
        --region "${M09_REGION}" 2>/dev/null || echo "")

    if [ -n "${TAG_VALUE}" ] && [ "${TAG_VALUE}" != "None" ]; then
        log_success "PASS: Tag '${TAG}' = ${TAG_VALUE}"
        TAG_PASS=$((TAG_PASS + 1))
    else
        log_fail "FAIL: Tag '${TAG}' is missing"
        TAG_FAIL=$((TAG_FAIL + 1))
    fi
done

PASS_COUNT=$((PASS_COUNT + TAG_PASS))
FAIL_COUNT=$((FAIL_COUNT + TAG_FAIL))

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_validation_summary
