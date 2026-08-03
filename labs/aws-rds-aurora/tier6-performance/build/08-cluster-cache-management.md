# Build 08 - Cluster Cache Management (CCM)

**Time:** 30 minutes
**Goal:** Enable Cluster Cache Management on Aurora PostgreSQL, designate a failover target reader, and understand what happens to cache state during a failover.
**Prerequisites:** Aurora PostgreSQL cluster with at least two instances (one writer, one reader). `$DB_CLUSTER_ID`, `$REGION` set.

---

## Background

Every PostgreSQL instance maintains a shared buffer cache (shared_buffers). This cache holds recently accessed data pages. After a failover, the newly promoted primary starts with a warm page cache only if it was already caching the right data.

Without CCM, a newly promoted reader starts with a cold cache. All queries miss the cache and hit Aurora's distributed storage until the cache warms up (30-60 minutes on a busy instance with a large working set).

With CCM, Aurora continuously replicates the primary's cache state to the designated failover reader. When that reader gets promoted, it already has the hot working set cached. The post-failover performance degradation is minimal.

```
Without CCM:
  Primary: [cache warm, 200GB hot pages in 256GB shared_buffers]
  Failover occurs
  New primary: [cache cold - every query hits storage for 30-60 minutes]

With CCM:
  Primary: [cache warm, 200GB hot pages]
  CCM continuously syncs cache state to designated reader
  Failover occurs
  New primary (was designated reader): [cache warm - 200GB hot pages already loaded]
```

> **Concept:** CCM replicates cache state metadata, not the actual pages. The designated reader still loads pages from Aurora's distributed storage the same way, but CCM tracks which pages the primary has loaded, so the reader pre-loads (prewarms) the same pages. The reader's cache stays aligned with the primary's.

---

## Step 1 - Check Your Aurora Cluster Topology

Identify your writer and readers:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter,Promotion:PromotionTier}" \
  --output table \
  --region "$REGION"
```

Expected output (yours will differ):
```
---------------------------------------------------------------
|               DescribeDBClusters                            |
+---------------------------------+----------+----------------+
|           Instance              |  Writer  | Promotion Tier |
+---------------------------------+----------+----------------+
|  aurora-cluster-instance-1      |  True    |   1            |
|  aurora-cluster-instance-2      |  False   |   1            |
+---------------------------------+----------+----------------+
```

The reader with the lowest promotion tier (closest to 1) will be the first to be promoted during a failover.

Save the writer and reader instance IDs:

```bash
export WRITER_INSTANCE_ID="aurora-cluster-instance-1"
export READER_INSTANCE_ID="aurora-cluster-instance-2"
```

---

## Step 2 - Verify Instance Classes Match

CCM requires the designated failover reader to have the same instance class as the writer. The reader must be able to hold the same cache.

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE_ID" \
  --query "DBInstances[0].DBInstanceClass" \
  --output text \
  --region "$REGION"
```

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$READER_INSTANCE_ID" \
  --query "DBInstances[0].DBInstanceClass" \
  --output text \
  --region "$REGION"
```

Both must be the same class (e.g., both db.r6g.xlarge). If they differ, resize the reader first.

---

## Step 3 - Create Cluster-Level Parameter Group

CCM is controlled at the cluster parameter group level. Create a custom cluster parameter group:

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "aurora-pg16-ccm" \
  --db-parameter-group-family "aurora-postgresql16" \
  --description "Aurora PostgreSQL 16 with Cluster Cache Management" \
  --region "$REGION"
```

`--db-parameter-group-family "aurora-postgresql16"`: Aurora PostgreSQL uses a different family name than RDS PostgreSQL.

---

## Step 4 - Enable CCM in the Cluster Parameter Group

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "aurora-pg16-ccm" \
  --parameters "ParameterName=apg_ccm_enabled,ParameterValue=1,ApplyMethod=immediate" \
  --region "$REGION"
```

`apg_ccm_enabled=1`: Enables cluster cache management at the cluster level. Does not require a restart.

Apply the parameter group to your cluster:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --db-cluster-parameter-group-name "aurora-pg16-ccm" \
  --apply-immediately \
  --region "$REGION"
```

---

## Step 5 - Create Instance-Level Parameter Group for the Designated Reader

The reader that will serve as the CCM failover target needs its own instance parameter group:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name "aurora-pg16-ccm-reader" \
  --db-parameter-group-family "aurora-postgresql16" \
  --description "Aurora PostgreSQL 16 CCM designated reader" \
  --region "$REGION"
```

Set the instance mode:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "aurora-pg16-ccm-reader" \
  --parameters "ParameterName=apg_ccm_instance_mode,ParameterValue=read-only-writer,ApplyMethod=pending-reboot" \
  --region "$REGION"
```

`apg_ccm_instance_mode=read-only-writer`: Tells this instance to maintain a writer-style cache (tracking the same pages as the primary). Requires a reboot to take effect.

Apply to the designated reader:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$READER_INSTANCE_ID" \
  --db-parameter-group-name "aurora-pg16-ccm-reader" \
  --apply-immediately \
  --region "$REGION"
```

Reboot the reader to apply the parameter:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier "$READER_INSTANCE_ID" \
  --region "$REGION"
```

Wait for it to come back:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$READER_INSTANCE_ID" \
  --region "$REGION"
```

---

## Step 6 - Set Failover Priority

Ensure your designated reader (the CCM target) has the highest failover priority (tier 1):

### Via Console

1. Open the RDS Console.
2. Click the **Aurora cluster**.
3. Click on the reader instance.
4. Click **Modify**.
5. Under **Failover**, set **Priority** to **tier-1** (lowest number = highest priority).
6. Apply immediately.

### Via CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$READER_INSTANCE_ID" \
  --promotion-tier 1 \
  --apply-immediately \
  --region "$REGION"
```

`--promotion-tier 1`: Sets the failover priority. Tier 1 is promoted first. Valid values: 0-15.

---

## Step 7 - Verify CCM is Active

Connect to the writer and check:

```bash
psql -h "$AURORA_WRITER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
SHOW apg_ccm_enabled;
```

Expected output:
```
 apg_ccm_enabled
-----------------
 1
```

Connect to the reader:

```bash
psql -h "$AURORA_READER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
SHOW apg_ccm_instance_mode;
```

Expected output:
```
 apg_ccm_instance_mode
-----------------------
 read-only-writer
```

---

## Step 8 - Observe CCM Behavior

Load some data so there is a meaningful working set:

```bash
psql -h "$AURORA_WRITER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
-- Create and load a test table
CREATE TABLE IF NOT EXISTS ccm_test AS
SELECT
    generate_series(1, 1000000) AS id,
    md5(random()::TEXT) AS data;

-- Access the data to populate the cache
SELECT count(*) FROM ccm_test;
SELECT avg(length(data)) FROM ccm_test;
```

Check shared_buffer usage on the writer:

```sql
-- How much of shared_buffers is used?
SELECT
    count(*) * 8 AS used_kb,
    pg_size_pretty(count(*) * 8192) AS used_size
FROM pg_buffercache;
```

> **Concept:** CCM tracks page accesses on the writer and signals the designated reader to pre-load the same pages. This happens asynchronously in the background without impacting query performance on either instance.

---

## Step 9 - Simulate a Failover and Observe Cache Warmth

Test a failover to see how fast the new primary serves queries:

```bash
# Trigger a failover (the reader you designated becomes the new writer)
aws rds failover-db-cluster \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --target-db-instance-identifier "$READER_INSTANCE_ID" \
  --region "$REGION"
```

`--target-db-instance-identifier`: Specifies which reader to promote. Use your CCM-designated reader.

Immediately after failover, connect to the new writer (formerly the reader) and run a query:

```bash
psql -h "$AURORA_WRITER_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM ccm_test;"
```

Expected output (yours will differ, with CCM cache is warm):
```
 Aggregate  (cost=16925.00..16925.01 rows=1 width=8) (actual time=248.3..248.3 rows=1 loops=1)
   Buffers: shared hit=4425 read=0
```

`read=0` or very low read count means the cache was warm. Without CCM, you would see many thousands of reads here.

Wait for the cluster to stabilize:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --region "$REGION"
```

---

## Step 10 - Verify Cluster Topology After Failover

The original writer is now a reader and the designated reader is now the writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}" \
  --output table \
  --region "$REGION"
```

---

## Cleanup

```sql
DROP TABLE IF EXISTS ccm_test;
```

---

## Limitations

- CCM is available only on Aurora PostgreSQL. Not available on RDS PostgreSQL.
- Only one reader can be the designated failover target.
- The reader designated for CCM has higher memory overhead.
- If you have additional readers not designated for CCM, they still have cold caches on promotion.
- CCM does not help if you failover to a non-designated reader.

---

## Summary

You have:
- Enabled CCM at the cluster level with `apg_ccm_enabled`
- Configured the designated reader with `apg_ccm_instance_mode = read-only-writer`
- Set failover priority so the CCM reader is promoted first
- Triggered a failover and observed the warm cache on the new primary

CCM is especially valuable in environments where failover performance matters. Without it, users experience 5-20x slower queries for up to an hour after failover. With it, the impact is typically unnoticeable after 1-2 minutes.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| CCM | Cluster Cache Management - Aurora feature that pre-warms the failover reader's cache |
| apg_ccm_enabled | Cluster-level parameter that enables CCM |
| apg_ccm_instance_mode | Instance-level parameter on the designated reader: set to `read-only-writer` |
| Promotion tier | Failover priority - lower number = promoted first (set reader to tier 1) |
| Cache warmth | State where shared_buffers contains the frequently accessed pages |
| Working set | The subset of database pages that queries access most frequently |
