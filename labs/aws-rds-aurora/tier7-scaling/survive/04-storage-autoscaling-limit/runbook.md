# SURVIVE Scenario 04: Storage Autoscaling Limit Hit - Runbook

**Incident type:** RDS storage approaching or at the autoscaling maximum ceiling. Autoscaling cannot expand further.
**Severity:** P1 if free storage < 5% of allocated. The database will become read-only when storage fills.
**Time to resolve:** 5-15 minutes to restore headroom. Root cause investigation follows.

---

## Stop. Assess Urgency First.

Check how much free storage remains:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[DB-IDENTIFIER] \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Minimum \
  --region [REGION]
```

Translate bytes to GiB by dividing by 1,073,741,824.

**Decision matrix based on free storage remaining:**
- Less than 1 GiB: Emergency. Go to Step 2 immediately. Do not investigate root cause first.
- 1-10 GiB: Urgent. Raise the ceiling now. Root cause after.
- 10+ GiB: You have time to investigate before acting.

---

## Step 1: Understand the Full Storage Picture

### Check current vs maximum allocated storage

```bash
aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].{Allocated:AllocatedStorage,Max:MaxAllocatedStorage,StorageType:StorageType}' \
  --output table
```

If `Allocated == Max` (or very close), autoscaling has no room to expand.

### Find what is consuming storage in the database

Connect to the database:

```sql
-- Top tables by size
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename) -
    pg_relation_size(schemaname || '.' || tablename)) AS index_size,
  pg_total_relation_size(schemaname || '.' || tablename) AS bytes
FROM pg_stat_user_tables
ORDER BY bytes DESC
LIMIT 20;
```

Look for:
- Tables much larger than expected (bloat, undeleted data)
- Tables that have grown recently (check `n_dead_tup` for unvacuumed bloat)
- Unexpected tables that should not be in production

```sql
-- Check for dead tuple bloat (unvacuumed rows consuming space)
SELECT
  schemaname,
  tablename,
  n_live_tup,
  n_dead_tup,
  ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

Dead tuples above 20-30% of total tuples indicate autovacuum is not keeping up.

```sql
-- Find the injected bloat table
SELECT
  tablename,
  pg_size_pretty(pg_total_relation_size('public.' || tablename)) AS size
FROM pg_stat_user_tables
WHERE tablename LIKE '%bloat%' OR tablename LIKE '%inject%'
ORDER BY pg_total_relation_size('public.' || tablename) DESC;
```

---

## Step 2: Immediate Remediation - Raise the Autoscaling Ceiling

This is the fastest way to restore headroom. It does not solve the root cause but prevents the database from going read-only.

### Console

1. Go to **RDS** > your database > **Modify**.
2. Under **Storage**, find **Maximum storage threshold**.
3. Increase it by a significant margin. If the ceiling was 200 GiB and you were at 195 GiB, raise to 500 GiB to give room to investigate.
4. Apply immediately.

### CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier [DB-IDENTIFIER] \
  --max-allocated-storage [NEW-MAXIMUM-IN-GIB] \
  --apply-immediately \
  --region [REGION]
```

Choose the new maximum carefully:
- It must be larger than current allocated storage (otherwise it will not trigger autoscaling).
- Set it large enough to give you time to investigate and fix the root cause.
- Storage cannot shrink later - whatever you allocate is permanent.

Verify the change:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].MaxAllocatedStorage' \
  --output text
```

---

## Step 3: Remove the Root Cause

### If the bloat table exists (from inject.sh)

```sql
DROP TABLE IF EXISTS storage_bloat_inject;
```

Verify storage starts recovering in CloudWatch within 10-15 minutes.

### If table bloat is the problem

Run VACUUM on the largest tables with high dead tuple counts:

```sql
VACUUM ANALYZE orders;
VACUUM ANALYZE customers;
```

For severe bloat:

```sql
VACUUM FULL orders;  -- WARNING: takes an exclusive lock. Use during maintenance only.
```

### If WAL accumulation is the problem

Check replication slots (as in Scenario 01):

```sql
SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained
FROM pg_replication_slots;
```

Drop any unconsumed slots causing WAL retention.

### If the application wrote unexpected data

Identify the tables, work with the application team to understand why data volume grew, and archive or delete the unexpected data:

```sql
-- Archive old completed orders to a separate table before deleting
CREATE TABLE orders_archive_2024 AS
SELECT * FROM orders
WHERE status = 'completed' AND created_at < '2024-01-01';

-- Delete after verifying the archive
DELETE FROM orders WHERE status = 'completed' AND created_at < '2024-01-01';

-- Run VACUUM after a large delete
VACUUM ANALYZE orders;
```

---

## Step 4: Prevent Recurrence

### Lower the autoscaling maximum to a reasonable ceiling

After removing the root cause, set the autoscaling maximum to a value that is:
- Large enough for genuine growth
- Low enough to alert you before it becomes a crisis

```bash
aws rds modify-db-instance \
  --db-instance-identifier [DB-IDENTIFIER] \
  --max-allocated-storage [APPROPRIATE-CEILING] \
  --apply-immediately \
  --region [REGION]
```

### Set a CloudWatch alarm at 20% free storage (not 10%)

The default autoscaling threshold is 10%. By the time autoscaling triggers, you may be close to the ceiling. Set an alarm earlier:

```bash
ALLOCATED_BYTES=$(aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].AllocatedStorage' \
  --output text)

# 20% of allocated storage in bytes
THRESHOLD_BYTES=$((ALLOCATED_BYTES * 1073741824 / 5))

aws cloudwatch put-metric-alarm \
  --alarm-name "[DB-IDENTIFIER]-storage-20pct-free" \
  --alarm-description "Free storage below 20% of allocated" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=[DB-IDENTIFIER] \
  --statistic Minimum \
  --period 300 \
  --evaluation-periods 3 \
  --threshold "${THRESHOLD_BYTES}" \
  --comparison-operator LessThanThreshold \
  --alarm-actions [SNS-TOPIC-ARN] \
  --region [REGION]
```

### Add table size monitoring

Add a weekly job or Lambda function that checks for the top 10 largest tables and alerts if any table exceeds a defined threshold. This catches unexpected growth before it causes an incident.

---

## Root Cause Summary

The autoscaling ceiling was set too low relative to actual storage usage. When a bloat table consumed additional space, the ceiling was reached and autoscaling could not expand further. The database was at risk of becoming read-only.

The fix was:
1. Raise the autoscaling ceiling immediately to restore headroom.
2. Drop the bloat table (or address the actual root cause of unexpected storage growth).
3. Set an early-warning CloudWatch alarm at 20% free space (not 10%).
4. Set the autoscaling ceiling to a deliberate, documented maximum that accounts for expected growth.

The key lesson: storage autoscaling is not a safety net for unlimited growth. It is a convenience feature for gradual, expected growth. The ceiling must be deliberately set and monitored.
