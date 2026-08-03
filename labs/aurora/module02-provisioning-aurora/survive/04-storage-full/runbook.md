# Runbook: Storage Growing Unexpectedly
## Survive Scenario 04

**What is being tested:** Your ability to detect unexpected storage growth in an Aurora cluster, identify the cause, clean it up, and set up monitoring to prevent future surprises.

**Why this matters:** Aurora storage auto-scales up to 128 TiB. Unlike standard RDS, Aurora will never run out of disk space and crash. But that does not make storage growth harmless - Aurora charges $0.10 per GB-month. If a rogue process dumps 500 GB of test data, that is $50/month in storage costs that keep accumulating even after the process stops. You need to detect this, clean it up, and monitor for it.

**Symptom:** CloudWatch VolumeBytesUsed metric spiking. Unexpected increase in AWS bill. Large tables appearing in the database.
**Severity:** Medium - no immediate outage, but cost and performance impact
**Time to resolve:** 15 to 30 minutes

---

## Your Starting Point

You receive a billing alert or notice that the Aurora cluster's storage usage has jumped significantly. The application is still running, but storage costs are climbing.

You check CloudWatch and see VolumeBytesUsed has increased sharply:
```
CloudWatch Metric: VolumeBytesUsed
Cluster: devops-lab-cluster
Value: 3,500,000,000 bytes (~3.3 GB)
Previous week average: 500,000,000 bytes (~0.5 GB)
```

Storage grew by nearly 3 GB. That is unusual.

---

## Symptoms

You will observe these symptoms:

1. CloudWatch VolumeBytesUsed metric shows a sharp increase
2. AWS billing shows higher-than-expected RDS charges
3. Database queries may slow down if the bloat is causing increased I/O
4. The application is still working - no outage
5. Disk space is NOT exhausted (Aurora auto-scales), but costs are rising

The key clue: storage grew rapidly without a corresponding increase in application usage.

---

## Diagnostic Steps

### Step 1 - Check Aurora Volume Usage

Check the CloudWatch metric for storage:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions "Name=DBClusterIdentifier,Value=devops-lab-cluster" \
  --start-time "$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average \
  --query "sort_by(Datapoints, &Timestamp)[-1].Average" \
  --output text
```

This returns the volume usage in bytes. Convert to GB:

**Hint:** Divide bytes by 1,073,741,824 to get GB.

### Step 2 - Check Database Size Inside PostgreSQL

Connect to the writer:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

Check total database size:

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
```

### Step 3 - Find the Largest Tables

This is the critical query - it shows you where the space is going:

```sql
SELECT
    schemaname || '.' || tablename AS table_name,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS data_size,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename) -
                   pg_relation_size(schemaname || '.' || tablename)) AS index_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 10;
```

**Hint:** Look for a table that is much larger than the others. That is your storage hog.

### Step 4 - Investigate the Suspicious Table

For the largest table, check its properties:

```sql
SELECT
    relname AS table_name,
    relkind,
    relpersistence,
    n_live_tup,
    pg_size_pretty(pg_total_relation_size(oid)) AS size
FROM pg_class
WHERE relname = 'storage_bloat';
```

Check `relpersistence`:
- `p` = permanent (normal table)
- `u` = unlogged (no WAL - suspicious for production)
- `t` = temporary

An `u` (unlogged) table with millions of rows is a strong indicator of a test/debug operation that was not cleaned up.

### Step 5 - Check Row Count and Growth Rate

```sql
SELECT count(*) FROM storage_bloat;
```

If this returns millions of rows, someone ran a bulk insert.

### Step 6 - Decide: Drop or Keep

If the table is unwanted (test data, debug output, accidental insert):

```sql
DROP TABLE IF EXISTS storage_bloat;
```

If the table contains real data that might be needed:

```sql
-- Create a backup first
CREATE TABLE storage_bloat_backup AS SELECT * FROM storage_bloat;
-- Then drop the original
DROP TABLE storage_bloat;
```

Verify space was freed:

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
```

```sql
\q
```

---

## Important: Aurora Storage Reclamation

> **Concept:** Aurora storage works differently from standard RDS. When you DROP a table on standard RDS, the EBS space is freed immediately. On Aurora, the storage volume does not shrink automatically. Aurora reclaims space over time as the storage subsystem compacts, but the VolumeBytesUsed metric may not decrease immediately after dropping a table. This is expected behavior. The space IS freed internally for reuse by Aurora, but the volume size may remain the same or decrease slowly.

This means: even after cleanup, your VolumeBytesUsed metric may not drop right away. Monitor it over 24-48 hours.

---

## Resolution Approach

1. Check VolumeBytesUsed to confirm the growth
2. Connect to the database and find the largest tables
3. Identify any table that does not belong (test data, bloat, unlogged tables)
4. Drop the unwanted table
5. Set up monitoring to catch future growth early

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | Large unlogged table `storage_bloat` created by a test/debug process |
| Impact | ~3 GB of unnecessary storage. No outage, but increased cost. |
| How to detect | CloudWatch VolumeBytesUsed spike or billing alert |
| Immediate fix | DROP TABLE to free the space |
| Long-term fix | CloudWatch alarm on storage growth rate + access controls |
| Time to recover | Under 5 minutes (DROP TABLE is instant) |

---

## Prevention

1. **CloudWatch alarm on VolumeBytesUsed** - Set an alarm when storage exceeds a threshold (e.g., 10 GB for a small cluster). Also set an alarm on the rate of change - if storage grows by more than 1 GB in an hour, something unusual is happening.

2. **AWS Budgets** - Set a monthly budget for RDS costs. AWS will alert you when actual or forecasted costs exceed the budget.

3. **Restrict CREATE TABLE permissions** - In production, application users should not be able to create tables. Only the DBA or migration tool should have DDL privileges.

4. **Weekly storage reports** - Schedule a Lambda function that queries the top 10 tables by size and sends a report. If a new large table appears, you catch it early.

5. **Audit logging** - Enable `log_statement = ddl` in the cluster parameter group. This logs all CREATE TABLE, DROP TABLE, and ALTER TABLE statements so you can trace who created the bloat.

---

## Interview Questions

**Q1: How does Aurora storage differ from standard RDS storage? Can an Aurora cluster run out of disk space?**

Strong answer: Aurora uses a shared storage volume that automatically scales from 10 GiB up to 128 TiB. You do not need to pre-allocate storage or set up storage autoscaling like you do with standard RDS. Aurora will never run out of disk space and crash. However, you still need to monitor storage because Aurora charges $0.10 per GB-month. Uncontrolled growth can cause significant cost increases. Also, after deleting data, Aurora's VolumeBytesUsed may not decrease immediately - the storage subsystem reclaims space asynchronously.

**Q2: You notice VolumeBytesUsed for an Aurora cluster jumped from 50 GB to 200 GB overnight. How do you investigate?**

Strong answer: First, check which database has the largest size with `pg_database_size()`. Then within that database, list the top tables by size with `pg_total_relation_size()`. Look for unusually large tables - especially unlogged or temp tables. Check `pg_stat_user_tables` for insert counts to see which tables received the most writes recently. Check the audit log for CREATE TABLE and INSERT statements. Also check for bloat: dead tuples from mass updates or deletes that have not been vacuumed.

**Q3: After dropping a 100 GB table in Aurora, the VolumeBytesUsed metric still shows the same value 6 hours later. Is this a problem?**

Strong answer: Not necessarily. Aurora's storage reclamation is asynchronous. After dropping a table, the space is marked as reusable internally, but the volume size metric may not decrease immediately. It can take hours to days for the metric to reflect the freed space. This is documented Aurora behavior. You can verify the drop worked by checking `pg_database_size()` inside PostgreSQL - that will show the reduced size immediately. The CloudWatch metric will catch up eventually.

---

## Key Terminology

| Term | Definition |
|------|-----------|
| VolumeBytesUsed | CloudWatch metric showing total Aurora storage volume usage in bytes |
| Auto-scaling storage | Aurora automatically grows storage as data increases (up to 128 TiB) |
| Unlogged table | A PostgreSQL table that does not write to WAL - faster but data lost on crash |
| Storage reclamation | Aurora's internal process that frees deleted data space over time |
| pg_total_relation_size() | PostgreSQL function that returns total disk space used by a table including indexes |

---

## Red Flags

These are answers that would concern an interviewer:

- "I would increase the allocated storage" - Aurora auto-scales. You do not manually allocate storage.
- "Aurora will run out of disk and crash" - Aurora can grow to 128 TiB. The real risk is cost, not crashing.
- "I would VACUUM FULL the entire database" - VACUUM FULL locks tables and is rarely needed. For Aurora, DROP TABLE is the right fix for unwanted tables.
- Not mentioning cost as a concern when discussing uncontrolled storage growth
- Not knowing that Aurora's VolumeBytesUsed may not decrease immediately after dropping data

---

## Now Run the Validate Script

```bash
export CLUSTER_ID=devops-lab-cluster
export REGION=us-east-1
export PGPASSWORD=YourPassword
bash validate.sh
```
