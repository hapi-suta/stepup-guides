#!/usr/bin/env bash
# SURVIVE Scenario 04: Storage Autoscaling Limit - Validation Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

log_info "=== SURVIVE Scenario 04: Storage Autoscaling Limit - Validation ==="
log_info ""

check_required_vars SOURCE_DB_IDENTIFIER SOURCE_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql

# Check 1: Autoscaling maximum is at least 50 GiB above current allocated storage
log_info "Check 1: Autoscaling maximum provides adequate headroom (>= 50 GiB above current)..."
ALLOCATED=$(aws rds describe-db-instances \
  --db-instance-identifier "${SOURCE_DB_IDENTIFIER}" \
  --region "${AWS_REGION}" \
  --query 'DBInstances[0].AllocatedStorage' \
  --output text 2>/dev/null || echo "0")

MAX_STORAGE=$(aws rds describe-db-instances \
  --db-instance-identifier "${SOURCE_DB_IDENTIFIER}" \
  --region "${AWS_REGION}" \
  --query 'DBInstances[0].MaxAllocatedStorage' \
  --output text 2>/dev/null || echo "0")

log_info "  Allocated: ${ALLOCATED} GiB"
log_info "  Max:       ${MAX_STORAGE} GiB"

if [[ "${MAX_STORAGE}" == "None" || "${MAX_STORAGE}" == "null" ]]; then
  log_fail "Storage autoscaling is disabled (MaxAllocatedStorage is null). Enable it with a meaningful ceiling."
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  HEADROOM=$((MAX_STORAGE - ALLOCATED))
  log_info "  Headroom:  ${HEADROOM} GiB"

  if [[ ${HEADROOM} -ge 50 ]]; then
    log_pass "Autoscaling headroom is ${HEADROOM} GiB (>= 50 GiB)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "Autoscaling headroom is only ${HEADROOM} GiB. Raise the maximum storage ceiling."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

# Check 2: Bloat table has been dropped
log_info "Check 2: Injected bloat table has been removed..."
BLOAT_EXISTS=$(psql_source -t -A -c "
  SELECT COUNT(*) FROM pg_tables
  WHERE tablename = 'storage_bloat_inject'
" 2>/dev/null || echo "-1")

assert_equal \
  "Bloat table 'storage_bloat_inject' removed" \
  "0" \
  "${BLOAT_EXISTS}"

# Check 3: Free storage is above 15% of allocated
log_info "Check 3: Free storage is above 15% of allocated storage..."
FREE_STORAGE=$(get_metric_latest "AWS/RDS" "FreeStorageSpace" "DBInstanceIdentifier" "${SOURCE_DB_IDENTIFIER}" "Minimum")

if [[ "${FREE_STORAGE}" != "None" && -n "${FREE_STORAGE}" ]]; then
  ALLOCATED_BYTES=$((ALLOCATED * 1073741824))
  FREE_PCT=$(echo "scale=1; ${FREE_STORAGE} / ${ALLOCATED_BYTES} * 100" | bc 2>/dev/null || echo "0")
  log_info "  Free storage: $(echo "scale=2; ${FREE_STORAGE} / 1073741824" | bc) GiB (${FREE_PCT}%)"

  FIFTEEN_PCT=$((ALLOCATED_BYTES * 15 / 100))
  if [[ $(echo "${FREE_STORAGE} > ${FIFTEEN_PCT}" | bc -l) -eq 1 ]]; then
    log_pass "Free storage (${FREE_PCT}%) is above 15% threshold"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "Free storage (${FREE_PCT}%) is still below 15%. Continue investigation."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_warn "Free storage metric not available yet. Check CloudWatch manually in 5 minutes."
fi

# Check 4: A CloudWatch alarm exists for low free storage
log_info "Check 4: CloudWatch alarm exists for low storage..."
STORAGE_ALARMS=$(aws cloudwatch describe-alarms \
  --region "${AWS_REGION}" \
  --query "length(MetricAlarms[?MetricName=='FreeStorageSpace' && contains(Dimensions[].Value, '${SOURCE_DB_IDENTIFIER}')])" \
  --output text 2>/dev/null || echo "0")

if [[ "${STORAGE_ALARMS}" -gt "0" ]]; then
  log_pass "CloudWatch alarm for FreeStorageSpace exists (${STORAGE_ALARMS} alarm(s))"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_warn "No CloudWatch alarm found for FreeStorageSpace on ${SOURCE_DB_IDENTIFIER}. Strongly recommended."
fi

# Check 5: Table bloat is within normal range for top tables
log_info "Check 5: Table dead tuple ratio is below 20% for main tables..."
HIGH_BLOAT=$(psql_source -t -A -c "
  SELECT COUNT(*)
  FROM pg_stat_user_tables
  WHERE n_dead_tup > 1000
  AND n_live_tup > 0
  AND ROUND(n_dead_tup * 100.0 / (n_live_tup + n_dead_tup), 1) > 20
" 2>/dev/null || echo "-1")

if [[ "${HIGH_BLOAT}" == "0" ]]; then
  log_pass "No tables with dead tuple ratio above 20%"
  PASS_COUNT=$((PASS_COUNT + 1))
elif [[ "${HIGH_BLOAT}" == "-1" ]]; then
  log_warn "Could not check bloat. Verify manually."
else
  log_warn "${HIGH_BLOAT} table(s) have dead tuple ratio > 20%. Run VACUUM ANALYZE on them."
fi

# Check 6: Database is writable (not in read-only mode due to storage)
log_info "Check 6: Database is writable (not in storage-caused read-only mode)..."
WRITE_TEST=$(psql_source -t -A -c "
  INSERT INTO load_test (payload) VALUES ('storage-validate-test') RETURNING id;
" 2>/dev/null || echo "failed")

if [[ "${WRITE_TEST}" != "failed" && -n "${WRITE_TEST}" ]]; then
  log_pass "Database is writable (INSERT succeeded)"
  PASS_COUNT=$((PASS_COUNT + 1))

  # Clean up the test row
  psql_source -c "
    DELETE FROM load_test WHERE payload = 'storage-validate-test';
  " > /dev/null 2>&1 || true
else
  log_fail "Database write test failed. Database may still be in read-only mode or the load_test table does not exist."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Summary
print_validation_summary "04-storage-autoscaling-limit"
