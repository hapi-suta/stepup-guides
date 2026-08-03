# SURVIVE Scenario 02: DMS Task Failure - Runbook

**Incident type:** AWS DMS migration task failed mid-stream due to schema incompatibility.
**Severity:** P2 - Migration is blocked. Data is not flowing. Source and target are diverging.
**Time to resolve:** 20-45 minutes depending on the type and extent of the schema difference.

---

## Step 1: Confirm the Task Is Failed and Get the Error

### Check task status

```bash
aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=[TASK-ARN]" \
  --region [REGION] \
  --query 'ReplicationTasks[0].{Status:Status,StopReason:StopReason,ErrorMessage:ReplicationTaskStats}' \
  --output table
```

Look for `Status: failed` or `Status: stopped` with an error reason.

### Check DMS task logs in CloudWatch

DMS writes error details to CloudWatch Logs. This is where you find the specific error.

```bash
# List DMS log groups
aws logs describe-log-groups \
  --log-group-name-prefix "dms-tasks" \
  --region [REGION] \
  --query 'logGroups[*].logGroupName' \
  --output table
```

```bash
# Search for errors in the task log
aws logs filter-log-events \
  --log-group-name "dms-tasks-[REPLICATION-INSTANCE-ID]" \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --region [REGION] \
  --query 'events[*].message' \
  --output text
```

You are looking for messages like:
- `ERROR: column "required_approval_code" of relation "orders" is NOT NULL without default`
- `FATAL: invalid input syntax for type...`
- `ERROR: duplicate key value violates unique constraint...`

Write down the exact error. This tells you exactly what to fix.

---

## Step 2: Identify the Schema Difference

Compare the schema between source and target for the affected table.

**On the source:**

```sql
SELECT
  column_name,
  data_type,
  character_maximum_length,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'orders'
ORDER BY ordinal_position;
```

**On the target (same query):**

```sql
SELECT
  column_name,
  data_type,
  character_maximum_length,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'orders'
ORDER BY ordinal_position;
```

Diff the two outputs. In this scenario, the target has a column (`required_approval_code`) that:
- Exists only on the target
- Has `is_nullable = NO`
- Has no `column_default`

DMS cannot insert rows into the target because the column has no value to put in `required_approval_code` - it is required and has no default.

---

## Step 3: Fix the Schema

You have three options:

### Option A: Drop the incompatible column (recommended if it is a mistake)

```sql
-- On the target
ALTER TABLE orders DROP COLUMN IF EXISTS required_approval_code;
```

Use this when the column was added to the target by mistake and should not exist.

### Option B: Make the column nullable (if it must exist but is not required)

```sql
-- On the target
ALTER TABLE orders ALTER COLUMN required_approval_code DROP NOT NULL;
```

DMS can then insert NULL for this column when no value comes from the source.

### Option C: Add a default value (if it must exist and must have a value)

```sql
-- On the target
ALTER TABLE orders
  ALTER COLUMN required_approval_code SET DEFAULT 'PENDING-REVIEW';
```

DMS will use the default for rows coming from the source where this column does not exist.

For this scenario, use **Option A** - the column was injected as a test.

Verify the fix:

```sql
SELECT column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'orders' AND column_name = 'required_approval_code';
```

Expected: 0 rows returned (column is gone).

---

## Step 4: Resume the DMS Task

After fixing the schema, resume the task.

**If the task was doing full load and failed mid-way:**

```bash
aws dms start-replication-task \
  --replication-task-arn [TASK-ARN] \
  --start-replication-task-type reload-target \
  --region [REGION]
```

The `reload-target` option drops and reloads all target data. Use this when the full load was not complete.

**If the task was in CDC mode and failed:**

```bash
aws dms start-replication-task \
  --replication-task-arn [TASK-ARN] \
  --start-replication-task-type resume-processing \
  --region [REGION]
```

The `resume-processing` option continues from where the task left off. The CDC stream position is remembered.

### Monitor the task restart

```bash
watch -n 15 "aws dms describe-replication-tasks \
  --filters Name=replication-task-arn,Values=[TASK-ARN] \
  --region [REGION] \
  --query 'ReplicationTasks[0].{Status:Status,FullLoad:ReplicationTaskStats.FullLoadProgressPercent,Latency:ReplicationTaskStats.ApplyLatency}' \
  --output table"
```

Wait until:
- `Status` is `running`
- `FullLoad` reaches 100 (for full-load tasks)
- `Latency` drops toward 0 seconds (for CDC tasks)

---

## Step 5: Validate Data Integrity

After the task is running again, validate that data matches.

**Row count comparison:**

On source:
```sql
SELECT COUNT(*) FROM orders;
```

On target (same query). Counts should match within the expected delta based on time elapsed since failure.

**Sample data comparison:**

```sql
-- On source: get the max order_id
SELECT MAX(order_id) FROM orders;
```

```sql
-- On target: confirm that order_id exists
SELECT order_id, status, product_sku FROM orders WHERE order_id = [MAX-FROM-SOURCE];
```

---

## Step 6: Post-Incident Actions

### Add schema comparison to pre-migration checklist

Before every migration, compare schemas:

```bash
pg_dump -h [SOURCE] -U postgres -d [DATABASE] --schema-only \
  | grep -E "CREATE TABLE|ALTER TABLE|ADD COLUMN" > /tmp/source_schema.txt

pg_dump -h [TARGET] -U postgres -d [DATABASE] --schema-only \
  | grep -E "CREATE TABLE|ALTER TABLE|ADD COLUMN" > /tmp/target_schema.txt

diff /tmp/source_schema.txt /tmp/target_schema.txt
```

Any diff output indicates schema drift that needs to be resolved before starting DMS.

### Enable DMS CloudWatch alerts

Create a CloudWatch alarm for DMS task failures:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "dms-task-failure" \
  --metric-name ReplicationNotApplicableRows \
  --namespace AWS/DMS \
  --dimensions Name=ReplicationInstanceIdentifier,Value=[DMS-INSTANCE-ID] \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions [SNS-TOPIC-ARN] \
  --region [REGION]
```

`ReplicationNotApplicableRows` counts rows that DMS could not apply to the target. Any value > 0 warrants investigation.

---

## Root Cause Summary

The DMS task failed because the target schema diverged from the source schema. The target had a NOT NULL column without a default value that DMS had no data for when loading rows from the source.

The fix was:
1. Identify the schema difference by comparing `information_schema.columns` on both instances.
2. Remove or adjust the incompatible column constraint on the target.
3. Resume the DMS task.

The prevention is:
- Always run a schema comparison before starting DMS.
- Use DMS table mapping rules to exclude target-only columns from the comparison.
- Implement a pre-flight check script as part of the migration runbook.
- Alert on `ReplicationNotApplicableRows` metric to catch row-level failures during CDC.
