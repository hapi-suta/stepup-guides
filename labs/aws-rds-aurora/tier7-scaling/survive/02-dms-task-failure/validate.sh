#!/usr/bin/env bash
# SURVIVE Scenario 02: DMS Task Failure - Validation Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

log_info "=== SURVIVE Scenario 02: DMS Task Failure - Validation ==="
log_info ""

check_required_vars DMS_TASK_ARN SOURCE_DB_HOST TARGET_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql

# Check 1: DMS task is running (not failed or stopped)
log_info "Check 1: DMS task is in running state..."
TASK_STATUS=$(aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'ReplicationTasks[0].Status' \
  --output text 2>/dev/null || echo "unknown")

assert_equal \
  "DMS task is running" \
  "running" \
  "${TASK_STATUS}"

# Check 2: Incompatible column has been removed from target
log_info "Check 2: Incompatible column 'required_approval_code' removed from target..."
COLUMN_EXISTS=$(psql_target -t -A -c "
  SELECT COUNT(*) FROM information_schema.columns
  WHERE table_name = 'orders'
  AND column_name IN ('required_approval_code', 'fake_required_field')
  AND is_nullable = 'NO'
  AND column_default IS NULL
" 2>/dev/null || echo "-1")

assert_equal \
  "Incompatible NOT NULL column without default removed from target" \
  "0" \
  "${COLUMN_EXISTS}"

# Check 3: Source and target row counts are within 5% of each other
log_info "Check 3: Row counts between source and target are within 5%..."
SOURCE_COUNT=$(psql_source -t -A -c "SELECT COUNT(*) FROM orders" 2>/dev/null || echo "0")
TARGET_COUNT=$(psql_target -t -A -c "SELECT COUNT(*) FROM orders" 2>/dev/null || echo "0")

log_info "  Source row count: ${SOURCE_COUNT}"
log_info "  Target row count: ${TARGET_COUNT}"

if [[ "${SOURCE_COUNT}" -gt 0 && "${TARGET_COUNT}" -gt 0 ]]; then
  DIFF=$(echo "scale=4; (${SOURCE_COUNT} - ${TARGET_COUNT}) / ${SOURCE_COUNT}" | bc -l)
  # Remove negative sign for absolute value
  ABS_DIFF="${DIFF#-}"
  # Check if within 5% (0.05)
  if [[ $(echo "${ABS_DIFF} < 0.05" | bc -l) -eq 1 ]]; then
    log_pass "Row counts within 5% of each other (diff: $(echo "scale=2; ${ABS_DIFF} * 100" | bc)%)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_fail "Row counts differ by more than 5% (diff: $(echo "scale=2; ${ABS_DIFF} * 100" | bc)%). DMS may not have fully synced."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_warn "Could not compare row counts (one or both returned 0). Verify manually."
fi

# Check 4: DMS replication latency is below 60 seconds
log_info "Check 4: DMS replication latency is below 60 seconds..."
LATENCY=$(aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'ReplicationTasks[0].ReplicationTaskStats.ApplyLatency' \
  --output text 2>/dev/null || echo "9999")

if [[ "${LATENCY}" != "None" && "${LATENCY}" != "null" ]]; then
  assert_less_than \
    "DMS apply latency below 60 seconds" \
    "${LATENCY}" \
    "60"
else
  log_warn "Could not read DMS latency metric. Task may not be in CDC mode yet."
fi

# Check 5: No recent errors in DMS task statistics
log_info "Check 5: DMS task has not applied failed rows recently..."
FAILED_ROWS=$(aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
  --region "${AWS_REGION}" \
  --query 'ReplicationTasks[0].ReplicationTaskStats.ApplyRowsFailed' \
  --output text 2>/dev/null || echo "0")

if [[ "${FAILED_ROWS}" == "None" || -z "${FAILED_ROWS}" ]]; then
  FAILED_ROWS="0"
fi

assert_equal \
  "No failed rows in DMS task statistics" \
  "0" \
  "${FAILED_ROWS}"

# Check 6: A test insert on source appears on target
log_info "Check 6: Testing live replication - insert on source appears on target..."
TEST_SKU="VALIDATE-02-$(date +%s)"

psql_source -c "
  INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
  VALUES (1, '${TEST_SKU}', 1, 0.01, 'validated');
" > /dev/null 2>&1 || true

sleep 15

REPLICATED=$(psql_target -t -A -c "
  SELECT COUNT(*) FROM orders WHERE product_sku = '${TEST_SKU}'
" 2>/dev/null || echo "0")

assert_equal \
  "Test row replicated from source to target via DMS" \
  "1" \
  "${REPLICATED}"

# Summary
print_validation_summary "02-dms-task-failure"
