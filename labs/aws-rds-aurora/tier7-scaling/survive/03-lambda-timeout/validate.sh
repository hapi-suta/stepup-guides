#!/usr/bin/env bash
# SURVIVE Scenario 03: Lambda Timeout - Validation Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

log_info "=== SURVIVE Scenario 03: Lambda Timeout - Validation ==="
log_info ""

check_required_vars LAMBDA_FUNCTION_NAME SOURCE_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql

# Check 1: No long-running active connections (none older than 10 seconds)
log_info "Check 1: No connections stuck for more than 10 seconds..."
STUCK_CONNECTIONS=$(psql_source -t -A -c "
  SELECT COUNT(*)
  FROM pg_stat_activity
  WHERE state = 'active'
  AND NOW() - query_start > interval '10 seconds'
  AND pid <> pg_backend_pid()
  AND query NOT ILIKE '%pg_stat_activity%'
" 2>/dev/null || echo "-1")

assert_equal \
  "No connections stuck longer than 10 seconds" \
  "0" \
  "${STUCK_CONNECTIONS}"

# Check 2: Trigger function uses async Lambda invocation
log_info "Check 2: Trigger function uses async Lambda invocation ('Event' mode)..."
TRIGGER_MODE=$(psql_source -t -A -c "
  SELECT prosrc FROM pg_proc WHERE proname = 'notify_order_status_change'
" 2>/dev/null || echo "not_found")

if echo "${TRIGGER_MODE}" | grep -q "'Event'"; then
  log_pass "Trigger function uses async invocation ('Event')"
  PASS_COUNT=$((PASS_COUNT + 1))
elif echo "${TRIGGER_MODE}" | grep -q "RequestResponse"; then
  log_fail "Trigger function still uses synchronous invocation ('RequestResponse'). Fix the trigger."
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  log_warn "Could not determine trigger invocation mode. Verify manually."
fi

# Check 3: Lambda function timeout is reasonable (> 10 seconds)
log_info "Check 3: Lambda function timeout is at least 15 seconds..."
LAMBDA_TIMEOUT=$(aws lambda get-function-configuration \
  --function-name "${LAMBDA_FUNCTION_NAME}" \
  --region "${AWS_REGION}" \
  --query 'Timeout' \
  --output text 2>/dev/null || echo "0")

assert_less_than \
  "Lambda timeout is at most 60 seconds (not absurdly high)" \
  "${LAMBDA_TIMEOUT}" \
  "61"

if [[ "${LAMBDA_TIMEOUT}" -ge 15 ]]; then
  log_pass "Lambda timeout is ${LAMBDA_TIMEOUT}s (reasonable for async notifications)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "Lambda timeout is ${LAMBDA_TIMEOUT}s - too low for reliable execution"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check 4: An order status update completes in less than 5 seconds
log_info "Check 4: Order status update completes in under 5 seconds..."
START_TIME=$(date +%s%N)

psql_source -c "
  UPDATE orders SET status = 'validated'
  WHERE order_id = (SELECT MIN(order_id) FROM orders);
" > /dev/null 2>&1 || true

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
DURATION_S=$(echo "scale=2; ${DURATION_MS} / 1000" | bc)

log_info "  Update completed in ${DURATION_S} seconds"

if [[ ${DURATION_MS} -lt 5000 ]]; then
  log_pass "Order status update completed in ${DURATION_S}s (< 5s)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_fail "Order status update took ${DURATION_S}s (> 5s). Lambda is still blocking the transaction."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check 5: Lambda was invoked (check CloudWatch logs for recent invocations)
log_info "Check 5: Lambda was invoked asynchronously (check recent CloudWatch logs)..."
RECENT_LOGS=$(aws logs filter-log-events \
  --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
  --start-time $(date -d '2 minutes ago' +%s000) \
  --filter-pattern "Order event received" \
  --region "${AWS_REGION}" \
  --query 'length(events)' \
  --output text 2>/dev/null || echo "0")

if [[ "${RECENT_LOGS}" -gt "0" ]]; then
  log_pass "Lambda was invoked recently (${RECENT_LOGS} log entries found)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_warn "No recent Lambda invocations found in logs. This may be OK if the Lambda is async and logs take time to appear."
fi

# Check 6: Connection count is healthy
log_info "Check 6: Database connection count is below 80% of max_connections..."
CONN_INFO=$(psql_source -t -A -c "
  SELECT
    COUNT(*)::FLOAT /
    (SELECT setting::FLOAT FROM pg_settings WHERE name = 'max_connections') * 100
  FROM pg_stat_activity
" 2>/dev/null || echo "999")

assert_less_than \
  "Connection usage below 80% of max_connections" \
  "${CONN_INFO}" \
  "80"

# Summary
print_validation_summary "03-lambda-timeout"
