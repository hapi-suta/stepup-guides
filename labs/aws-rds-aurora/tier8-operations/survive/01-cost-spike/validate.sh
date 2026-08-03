#!/usr/bin/env bash
# =============================================================================
# SURVIVE Scenario 01: Validate - Cost Spike Remediated
# Run this after completing your remediation to confirm the scenario is resolved.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

print_banner "SURVIVE 01: Validation - Cost Spike"

t8_validate_config || exit 1
check_aws_auth || exit 1

PASS_COUNT=0
FAIL_COUNT=0

# Load inject state if available
if [[ -f "${SCRIPT_DIR}/.inject-state" ]]; then
  source "${SCRIPT_DIR}/.inject-state"
fi

# -----------------------------------------------------------------------
# Check 1: Aurora cluster is on I/O-Optimized storage
# -----------------------------------------------------------------------
log_step "Check 1: Aurora cluster storage type"

STORAGE_TYPE=$(aws rds describe-db-clusters \
  --db-cluster-identifier "${T8_CLUSTER_ID}" \
  --query 'DBClusters[0].StorageType' \
  --output text \
  --region "${T8_REGION}" 2>/dev/null || echo "UNKNOWN")

if [[ "${STORAGE_TYPE}" == "aurora-iopt1" ]]; then
  validate_check "Aurora cluster is on I/O-Optimized storage" "pass" "StorageType: ${STORAGE_TYPE}"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  validate_check "Aurora cluster is on I/O-Optimized storage" "fail" \
    "StorageType: ${STORAGE_TYPE} (expected aurora-iopt1)"
  echo "  Fix: aws rds modify-db-cluster --db-cluster-identifier ${T8_CLUSTER_ID} --storage-type aurora-iopt1 --apply-immediately --region ${T8_REGION}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------
# Check 2: log_min_duration_statement is not 0
# -----------------------------------------------------------------------
log_step "Check 2: PostgreSQL verbose logging disabled"

if [[ -n "${T8_PARAMETER_GROUP}" ]]; then
  LOG_DURATION=$(get_parameter_value "log_min_duration_statement")

  if [[ "${LOG_DURATION}" == "0" ]]; then
    validate_check "log_min_duration_statement is not 0 (all queries logged)" "fail" \
      "Current value: ${LOG_DURATION} - This causes excessive CloudWatch Logs charges"
    echo "  Fix: aws rds modify-db-parameter-group --db-parameter-group-name ${T8_PARAMETER_GROUP} --parameters ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate --region ${T8_REGION}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    validate_check "log_min_duration_statement is not 0" "pass" "Current value: ${LOG_DURATION}ms"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
else
  log_warn "T8_PARAMETER_GROUP not set - skipping parameter check."
fi

# -----------------------------------------------------------------------
# Check 3: Workload test table is cleaned up
# -----------------------------------------------------------------------
log_step "Check 3: I/O workload test table removed"

if check_db_connectivity &>/dev/null; then
  TABLE_EXISTS=$(run_sql "SELECT count(*) FROM information_schema.tables WHERE table_name = 't8_cost_spike_test';" 2>/dev/null | tr -d ' ')

  if [[ "${TABLE_EXISTS}" == "0" ]]; then
    validate_check "I/O workload test table removed" "pass"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    validate_check "I/O workload test table removed" "fail" \
      "Table t8_cost_spike_test still exists"
    echo "  Fix: psql ... -c \"DROP TABLE IF EXISTS t8_cost_spike_test;\""
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_warn "Cannot connect to database - skipping table check."
fi

# -----------------------------------------------------------------------
# Check 4: CloudWatch Logs retention policy is set
# -----------------------------------------------------------------------
log_step "Check 4: CloudWatch Logs retention policy is configured"

RETENTION=$(aws logs describe-log-groups \
  --log-group-name "${T8_LOG_GROUP}" \
  --query 'logGroups[0].retentionInDays' \
  --output text \
  --region "${T8_REGION}" 2>/dev/null || echo "None")

if [[ "${RETENTION}" == "None" || "${RETENTION}" == "" ]]; then
  validate_check "CloudWatch Logs retention policy configured" "fail" \
    "Log group has no retention policy - logs will accumulate indefinitely"
  echo "  Fix: aws logs put-retention-policy --log-group-name ${T8_LOG_GROUP} --retention-in-days 90 --region ${T8_REGION}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  validate_check "CloudWatch Logs retention policy configured" "pass" \
    "Retention: ${RETENTION} days"
  PASS_COUNT=$((PASS_COUNT + 1))
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
  log_success "Scenario 01 RESOLVED: All checks pass."
  echo ""
  echo "What you demonstrated:"
  echo "  - Identified unexpected I/O charges as the cost driver"
  echo "  - Switched Aurora cluster to I/O-Optimized storage"
  echo "  - Restored appropriate query logging threshold"
  echo "  - Cleaned up the workload artifacts"
  echo "  - Configured log retention to prevent future cost accumulation"
else
  log_fail "Scenario 01 NOT FULLY RESOLVED: ${FAIL_COUNT} check(s) still failing."
  echo ""
  echo "Review the failed checks above and their suggested fixes."
  echo "Run validate.sh again after each fix."
fi
echo ""
