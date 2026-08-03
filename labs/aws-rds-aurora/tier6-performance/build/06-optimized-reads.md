# Build 06 - Optimized Reads (RDS NVMe and Aurora Tiered Cache)

**Time:** 30 minutes
**Goal:** Understand RDS Optimized Reads and Aurora's tiered cache, identify which workloads benefit, enable the feature, and measure the improvement.
**Prerequisites:** An RDS instance on a supported instance family (db.m6gd, db.m7gd, db.r6gd, db.r7gd) OR an Aurora cluster on db.r6gd or db.r7gd. If you only have db.t3 or similar, follow along with the concept steps and note where you would apply them.

---

## Background

Optimized Reads solves a specific problem: queries that spill to disk because work_mem is insufficient for sorting or hashing.

Without Optimized Reads, those spills go to EBS storage (network-attached, shared with data file reads/writes). With Optimized Reads, spills go to local NVMe SSD attached directly to the instance. NVMe is 10-100x faster than EBS for this type of I/O.

On Aurora, Optimized Reads also creates a second-tier cache: NVMe acts as a buffer between RAM and Aurora's distributed storage. Pages evicted from shared_buffers land in the NVMe cache instead of going all the way back to storage.

---

## Step 1 - Check If Your Instance Supports Optimized Reads

### RDS

Supported instance families (as of 2024): db.m6gd, db.m7gd, db.r6gd, db.r7gd, db.x2gd.

The "d" suffix indicates local NVMe storage.

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].{Class:DBInstanceClass,Engine:Engine,EngineVersion:EngineVersion}" \
  --output table \
  --region "$REGION"
```

Expected output (yours will differ):
```
---------------------------------------------------
|             DescribeDBInstances                 |
+---------+----------+----------------------------+
|  Class  |  Engine  |       EngineVersion        |
+---------+----------+----------------------------+
|  db.r6gd.xlarge  |  postgres  |  16.1          |
+---------+----------+----------------------------+
```

If you see a "d" in the instance class, it supports Optimized Reads.

### Aurora

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}" \
  --output table \
  --region "$REGION"
```

Then check each instance class for the "d" suffix.

---

## Step 2 - Enable Optimized Reads on RDS

### Via Console

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click your database and then **Modify**.
3. Under **Storage**, look for **RDS Optimized Reads**.
4. Toggle it to **Enable**.
5. Click **Continue** and then **Apply immediately**.

### Via CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --enable-optimized-reads \
  --apply-immediately \
  --region "$REGION"
```

`--enable-optimized-reads`: Tells RDS to direct temp file writes to the local NVMe device.

Wait for the modification:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

> **Concept:** Enabling Optimized Reads does not change where your data is stored. Your data files and WAL remain on EBS. Only temp files (from sort/hash spills) are redirected to NVMe.

---

## Step 3 - Enable Aurora Tiered Cache

For Aurora clusters with compatible instance types (r6gd, r7gd):

### Via Parameter Group

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "your-aurora-pg-parameter-group" \
  --parameters "ParameterName=aurora_tiered_cache_enabled,ParameterValue=1,ApplyMethod=immediate" \
  --region "$REGION"
```

`ApplyMethod=immediate`: This parameter does not require a restart on Aurora.

Verify:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SHOW aurora_tiered_cache_enabled;"
```

Expected output (yours will differ):
```
 aurora_tiered_cache_enabled
-----------------------------
 on
```

---

## Step 4 - Measure the Benefit

### Find Queries That Currently Spill to Disk

Connect to your database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
-- Check current temp file usage
SELECT
    left(query, 80) AS query_snippet,
    calls,
    temp_blks_written,
    round(temp_blks_written::numeric / nullif(calls, 0) * 8, 0) AS spill_kb_per_call
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

### Generate a Workload That Spills

```sql
-- Create a large table
CREATE TABLE IF NOT EXISTS sort_test AS
SELECT
    generate_series(1, 5000000) AS id,
    (random() * 100000)::INT AS group_id,
    (random() * 1000)::NUMERIC(12,2) AS value,
    repeat(md5(random()::TEXT), 4) AS payload;

ANALYZE sort_test;
```

Set work_mem low to force spills (simulating insufficient memory):

```sql
SET work_mem = '4MB';
```

Time a sort-heavy query:

```sql
\timing on

SELECT group_id, sum(value) AS total, count(*) AS cnt
FROM sort_test
GROUP BY group_id
ORDER BY total DESC
LIMIT 1000;

\timing off
```

Note the execution time. Look at the plan:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT group_id, sum(value) AS total, count(*) AS cnt
FROM sort_test
GROUP BY group_id
ORDER BY total DESC
LIMIT 1000;
```

Expected output (yours will differ):
```
 Sort  (cost=...) (actual time=4823.1..4823.8 rows=1000 loops=1)
   Sort Key: (sum(value)) DESC
   Sort Method: external merge  Disk: 42160kB
   Buffers: shared hit=22096, temp read=5270 written=5270
```

`Disk: 42160kB` - 42MB spilled to disk. `temp read=5270` blocks read back.

### Before/After Comparison

Without Optimized Reads (EBS temp files):
- The sort above might take 4-6 seconds

With Optimized Reads (NVMe temp files):
- The same sort typically takes 0.5-1.5 seconds (3-10x faster)

The exact improvement depends on your instance type and EBS bandwidth utilization.

---

## Step 5 - Check Optimized Reads Status

### Verify NVMe is Being Used

On Aurora, check the tiered cache hit rate:

```sql
-- Aurora-specific view
SELECT *
FROM aurora_stat_io_funcs
WHERE function_name LIKE '%tiered%';
```

Check temp file location (RDS Optimized Reads):

```sql
-- PostgreSQL temp file statistics
SELECT
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE datname = current_database();
```

### CloudWatch Metric for Temp Files

Monitor temp file usage via CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name TempStorageIOPS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 \
  --statistics Average \
  --region "$REGION"
```

---

## Step 6 - Aurora Tiered Cache - Checking Cache Stats

For Aurora with tiered cache enabled:

```sql
-- Aurora-specific: check pages in tiered cache vs shared_buffers
SELECT
    name,
    setting,
    unit
FROM pg_settings
WHERE name IN ('aurora_tiered_cache_enabled', 'shared_buffers');
```

The tiered cache is transparent - PostgreSQL does not know the difference between fetching a page from NVMe cache vs distributed storage. The benefit shows up as lower `IO:DataFileRead` wait events in Performance Insights.

---

## Step 7 - When Optimized Reads Is NOT the Right Fix

Optimized Reads helps when temp files are the bottleneck. It does NOT help when:

- Queries are slow because of missing indexes (fix: add the index)
- Data is not fitting in shared_buffers (fix: increase instance size or shared_buffers)
- The bottleneck is CPU computation (fix: rewrite query or add index)
- The application has connection issues (fix: RDS Proxy)

Check if temp files are actually the issue before assuming Optimized Reads will help:

```sql
SELECT
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE datname = current_database();
```

If `temp_files` is 0 or very small, Optimized Reads will not meaningfully help. Look elsewhere.

---

## Cleanup

```sql
DROP TABLE IF EXISTS sort_test;
RESET work_mem;
```

---

## Summary

You have:
- Identified whether your instance supports Optimized Reads
- Enabled RDS Optimized Reads and Aurora tiered cache
- Generated and measured sort spill workload before and after
- Understood when Optimized Reads helps and when it does not

The biggest wins come from workloads with analytics mixed into OLTP - reporting queries that do large GROUP BY and ORDER BY operations alongside transactional queries.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| NVMe | Non-Volatile Memory Express - local SSD attached directly to the instance, 10-100x faster I/O than EBS |
| EBS | Elastic Block Store - network-attached storage, shared between data files, WAL, and (without Optimized Reads) temp files |
| Temp files | Files created when sort/hash operations exceed work_mem |
| Tiered cache | Aurora feature using NVMe as a second-level cache between shared_buffers and distributed storage |
| external merge | PostgreSQL sort method that uses temp files (indicator that Optimized Reads will help) |
| TempStorageIOPS | CloudWatch metric measuring I/O operations on the local NVMe (RDS Optimized Reads) |
