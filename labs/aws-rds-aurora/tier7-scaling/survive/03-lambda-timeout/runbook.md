# SURVIVE Scenario 03: Lambda Timeout and Connection Leak - Runbook

**Incident type:** Database connections accumulating due to synchronous Lambda calls from PostgreSQL triggers timing out.
**Severity:** P1 if connections approaching `max_connections`. P2 if application is slow but not yet saturated.
**Time to resolve:** 15-20 minutes once the root cause is identified.

---

## Step 1: Confirm the Symptom

Check for long-running connections:

```sql
SELECT
  pid,
  usename,
  application_name,
  state,
  wait_event_type,
  wait_event,
  LEFT(query, 100) AS query_preview,
  NOW() - query_start AS duration
FROM pg_stat_activity
WHERE state <> 'idle'
AND pid <> pg_backend_pid()
ORDER BY duration DESC;
```

What you expect to see:
- Multiple connections in `active` state
- Duration columns showing several seconds or tens of seconds
- Query text showing `UPDATE orders SET status = ...`
- Possible wait events related to extension calls

Check total connection count vs maximum:

```sql
SELECT
  COUNT(*) AS current_connections,
  (SELECT setting::INTEGER FROM pg_settings WHERE name = 'max_connections') AS max_connections,
  ROUND(COUNT(*) * 100.0 /
    (SELECT setting::INTEGER FROM pg_settings WHERE name = 'max_connections'), 1) AS pct_used
FROM pg_stat_activity;
```

If connection usage is above 70%, you need to act quickly.

---

## Step 2: Identify What Is Blocking the Connections

Look at the specific queries that are hanging:

```sql
SELECT pid, state, query, NOW() - query_start AS duration
FROM pg_stat_activity
WHERE query LIKE '%orders%'
AND state = 'active'
ORDER BY duration DESC;
```

The UPDATE queries should complete in milliseconds. If they are taking 10+ seconds, something in the transaction is blocking.

Check for trigger functions:

```sql
SELECT
  tgname AS trigger_name,
  tgtype,
  p.proname AS function_name,
  p.prosrc
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'orders'::regclass;
```

Look for the `notify_order_status_change` trigger. Note the function source.

Check the trigger function body:

```sql
SELECT prosrc FROM pg_proc WHERE proname = 'notify_order_status_change';
```

Look for `'RequestResponse'` in the function source. This is the synchronous invocation mode - it blocks until Lambda returns. If Lambda is timing out, the PostgreSQL transaction waits for the full Lambda timeout duration (up to 15 minutes).

---

## Step 3: Terminate Stuck Connections (Emergency)

If connections are saturating the pool and new connections cannot be established, terminate the stuck ones:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
AND query LIKE '%UPDATE orders%'
AND NOW() - query_start > interval '30 seconds'
AND pid <> pg_backend_pid();
```

This terminates backend PIDs with active UPDATE queries that have been running longer than 30 seconds. The `ROLLBACK` happens automatically when the connection is terminated.

Verify they are gone:

```sql
SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active' AND query LIKE '%UPDATE orders%';
```

---

## Step 4: Fix the Root Cause - Switch to Asynchronous Lambda Invocation

The problem is `'RequestResponse'` (synchronous) being used where `'Event'` (asynchronous) should be.

```sql
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
  payload JSON;
BEGIN
  payload := json_build_object(
    'order_id',    NEW.order_id,
    'customer_id', NEW.customer_id,
    'status',      NEW.status,
    'old_status',  OLD.status,
    'updated_at',  NOW()
  );

  -- FIXED: Use 'Event' for async invocation (fire and forget)
  PERFORM aws_lambda.invoke(
    aws_commons.create_lambda_function_arn(
      'order-status-notifier',
      '[REGION]'
    ),
    payload,
    'Event'   -- Async: returns immediately, Lambda runs in background
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

The change: `SELECT ... INTO response FROM aws_lambda.invoke(...)` becomes `PERFORM aws_lambda.invoke(...)` with `'Event'`. The `PERFORM` keyword discards the return value (appropriate for async where there is none). The `'Event'` invocation type tells AWS to queue the Lambda invocation and return to PostgreSQL immediately without waiting.

---

## Step 5: Fix the Lambda Function

Also fix the Lambda function itself - the slow sleep was the root cause of why synchronous invocation was problematic.

```bash
cat > /tmp/order_notifier_fixed.py << 'EOF'
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f"Order event received: {json.dumps(event)}")

    order_id = event.get("order_id")
    status = event.get("status")
    customer_id = event.get("customer_id")

    # Real implementation: send notification, call API, publish to SQS, etc.
    # This must complete quickly (Lambda is async - errors won't roll back the DB transaction)
    message = f"Order {order_id} for customer {customer_id} moved to status: {status}"
    logger.info(message)

    return {
        "statusCode": 200,
        "message": message
    }
EOF

zip /tmp/order_notifier_fixed.zip /tmp/order_notifier_fixed.py

aws lambda update-function-code \
  --function-name order-status-notifier \
  --zip-file fileb:///tmp/order_notifier_fixed.zip \
  --region [REGION]
```

Also restore the Lambda timeout to a reasonable value:

```bash
aws lambda update-function-configuration \
  --function-name order-status-notifier \
  --timeout 30 \
  --region [REGION]
```

---

## Step 6: Verify the Fix

Test an order status update and confirm it completes immediately:

```sql
\timing on
UPDATE orders SET status = 'shipped' WHERE order_id = 1;
```

Expected: completes in < 100ms.

Check Lambda logs to confirm the async invocation fired:

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/order-status-notifier \
  --start-time $(date -d '2 minutes ago' +%s000) \
  --filter-pattern "Order event received" \
  --region [REGION] \
  --query 'events[*].message' \
  --output text
```

The event should appear in Lambda logs, confirming the async invocation worked.

---

## Step 7: Post-Incident Prevention

### Statement timeout as a safety net

Add a statement timeout to the trigger function so it can never hold a connection indefinitely:

```sql
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Set a 2-second local timeout for the trigger body
  SET LOCAL statement_timeout = '2s';

  PERFORM aws_lambda.invoke(
    aws_commons.create_lambda_function_arn('order-status-notifier', '[REGION]'),
    json_build_object('order_id', NEW.order_id, 'status', NEW.status),
    'Event'
  );

  RETURN NEW;
EXCEPTION
  WHEN query_canceled OR others THEN
    -- Log the error but do not fail the transaction
    RAISE WARNING 'Lambda notification failed for order %: %', NEW.order_id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

The `SET LOCAL statement_timeout` applies only within the trigger execution. The `EXCEPTION` block catches timeout errors and logs a warning instead of failing the transaction. The data transaction succeeds even if the notification fails.

### CloudWatch alarm on DatabaseConnections

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "[DB-IDENTIFIER]-high-connections" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=[DB-IDENTIFIER] \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions [SNS-TOPIC-ARN] \
  --region [REGION]
```

Adjust the threshold (80) to be 80% of your `max_connections` value.

---

## Root Cause Summary

A PostgreSQL trigger called Lambda using synchronous invocation (`RequestResponse`). The Lambda function had a bug (30-second sleep simulating an external API call without a timeout). The Lambda function also had a 10-second execution timeout. Each trigger invocation held a PostgreSQL transaction open for the full Lambda timeout duration, leaking connections.

The fix was:
1. Switch the trigger to asynchronous invocation (`Event`). The database transaction no longer waits for Lambda.
2. Fix the Lambda function to not have the blocking sleep.
3. Add a statement timeout and exception handler in the trigger as a safety net.

The rule: Never use synchronous Lambda calls (`RequestResponse`) from database triggers. Use async (`Event`) for notifications and fire-and-forget patterns. If you need synchronous behavior, ensure Lambda has a very short execution timeout and the trigger has an exception handler.
