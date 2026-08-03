#!/usr/bin/env bash
# SURVIVE Scenario 03: Lambda Timeout and Connection Leak
#
# Injects the problem:
#   - Updates the Lambda function to have an artificially long sleep (simulates a slow external call)
#   - The PostgreSQL trigger calls Lambda synchronously
#   - Each order status update holds a transaction open waiting for Lambda to return
#   - Connections accumulate and can't release
#
# The student must identify connection accumulation, understand the trigger -> Lambda relationship,
# fix the Lambda invocation type (sync -> async), and restore normal operation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../lib/common.sh"

# ============================================================
check_required_vars LAMBDA_FUNCTION_NAME SOURCE_DB_HOST DB_NAME DB_USER AWS_REGION
check_aws_cli
check_psql
# ============================================================

log_info "=== SURVIVE Scenario 03: Lambda Timeout and Connection Leak ==="
log_info "Injecting slow Lambda function and switching trigger to synchronous mode."
log_info ""

# Step 1: Deploy a slow version of the Lambda function
log_info "Step 1: Deploying slow Lambda function (30-second sleep per invocation)..."

cat > /tmp/slow_order_notifier.py << 'PYEOF'
import json
import logging
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f"Order event received: {json.dumps(event)}")

    # Simulate a slow external API call (misconfigured HTTP client, no timeout set)
    logger.info("Calling external notification service...")
    time.sleep(30)  # This is the bug: 30-second blocking call

    logger.info("External call complete")
    return {"statusCode": 200, "message": "notified"}
PYEOF

zip /tmp/slow_order_notifier.zip /tmp/slow_order_notifier.py

aws lambda update-function-code \
  --function-name "${LAMBDA_FUNCTION_NAME}" \
  --zip-file fileb:///tmp/slow_order_notifier.zip \
  --region "${AWS_REGION}" > /dev/null 2>&1 || {
  log_warn "Could not update Lambda function code. Ensure LAMBDA_FUNCTION_NAME is correct."
  log_warn "Continuing with trigger modification only."
}

log_info "  Lambda now sleeps 30 seconds per invocation."

# Step 2: Reduce Lambda timeout to 10 seconds (so it times out before completing)
log_info "Step 2: Reducing Lambda timeout to 10 seconds (less than the sleep duration)..."
aws lambda update-function-configuration \
  --function-name "${LAMBDA_FUNCTION_NAME}" \
  --timeout 10 \
  --region "${AWS_REGION}" > /dev/null 2>&1 || {
  log_warn "Could not update Lambda timeout. Continuing."
}

log_info "  Lambda will now timeout after 10 seconds (before the 30-second sleep completes)."

# Step 3: Update the trigger to use synchronous invocation (RequestResponse instead of Event)
log_info "Step 3: Switching trigger to synchronous Lambda invocation..."
psql_source -c "
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS \$\$
DECLARE
  payload JSON;
  response JSON;
BEGIN
  payload := json_build_object(
    'order_id',    NEW.order_id,
    'customer_id', NEW.customer_id,
    'status',      NEW.status,
    'old_status',  OLD.status,
    'updated_at',  NOW()
  );

  -- BUG: synchronous invocation - blocks the PostgreSQL transaction
  SELECT payload INTO response
  FROM aws_lambda.invoke(
    aws_commons.create_lambda_function_arn(
      '${LAMBDA_FUNCTION_NAME}',
      '${AWS_REGION}'
    ),
    payload,
    'RequestResponse'   -- THIS IS THE BUG: should be 'Event' for async
  );

  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;
" > /dev/null 2>&1 || {
  log_warn "Could not update trigger function. The aws_lambda extension may not be installed."
  log_warn "Simulating connection accumulation via pg_sleep instead."

  # Fallback: use pg_sleep to simulate the same connection-holding behavior
  psql_source -c "
  CREATE OR REPLACE FUNCTION notify_order_status_change()
  RETURNS TRIGGER AS \$\$
  BEGIN
    -- Simulate slow external call that blocks the transaction
    PERFORM pg_sleep(15);
    RETURN NEW;
  END;
  \$\$ LANGUAGE plpgsql;" > /dev/null 2>&1 || true
}

log_info "  Trigger is now synchronous. Every order status update will block for 10-30 seconds."

# Step 4: Fire several concurrent updates to accumulate connections
log_info "Step 4: Firing concurrent order updates to accumulate connections..."
for i in {1..5}; do
  psql_source -c "
    UPDATE orders SET status = 'processing'
    WHERE order_id IN (
      SELECT order_id FROM orders WHERE status = 'pending' LIMIT 1
    );" > /dev/null 2>&1 &
done

log_info "  5 concurrent updates fired. Each holds a connection for 10-30 seconds."

sleep 5

# Step 5: Show the symptom
log_info ""
log_info "Current connection state on source database:"
psql_source -c "
SELECT
  pid,
  state,
  wait_event_type,
  wait_event,
  LEFT(query, 80) AS query_preview,
  NOW() - query_start AS duration
FROM pg_stat_activity
WHERE state <> 'idle'
AND pid <> pg_backend_pid()
ORDER BY duration DESC
LIMIT 20;" 2>/dev/null || true

log_warn ""
log_warn "======================================================"
log_warn "  PROBLEM INJECTED."
log_warn "======================================================"
log_warn ""
log_warn "  Symptoms:"
log_warn "    - Order status updates are hanging (10-30 seconds per update)"
log_warn "    - Database connections are accumulating"
log_warn "    - pg_stat_activity shows queries in 'active' state for long durations"
log_warn "    - Lambda CloudWatch logs show timeout errors"
log_warn "    - Application may report slow response times or connection pool exhaustion"
log_warn ""
log_warn "  Starting points for diagnosis:"
log_warn "    1. Check pg_stat_activity for long-running connections"
log_warn "       SELECT pid, state, wait_event, duration, query FROM pg_stat_activity WHERE state <> 'idle';"
log_warn "    2. Check Lambda logs for timeout errors"
log_warn "       aws logs filter-log-events --log-group-name /aws/lambda/${LAMBDA_FUNCTION_NAME} --filter-pattern Task"
log_warn "    3. Identify what is causing the slow transactions"
log_warn ""
log_warn "  DO NOT READ the runbook yet. Diagnose first."
log_warn "  When fixed, run: validate.sh"
log_warn "======================================================"
