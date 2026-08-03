# Build 07 - Optimized Writes and Aurora I/O-Optimized

**Time:** 30 minutes
**Goal:** Enable RDS Optimized Writes to reduce WAL volume and write latency. Understand Aurora I/O-Optimized pricing mode and calculate when switching saves money.
**Prerequisites:** RDS PostgreSQL on a supported instance family. Aurora PostgreSQL cluster. `$DB_INSTANCE_ID`, `$DB_CLUSTER_ID`, `$REGION` set.

---

## Part A: RDS Optimized Writes

### Background

Standard PostgreSQL protects against partial page writes during a crash using a mechanism called full-page images (FPI). After each checkpoint, the first time PostgreSQL modifies a page, it writes the entire 8KB page to the WAL before writing only the changed bytes. This doubles the WAL for write-heavy workloads.

RDS Optimized Writes eliminates full-page images by using a checksummed atomic write mechanism at the EBS storage level. EBS guarantees the write is atomic (all-or-nothing), so PostgreSQL no longer needs to protect against partial writes.

The result:
- WAL volume drops (fewer full-page images)
- Write throughput increases
- Replica lag decreases (replicas have less WAL to process)

> **Concept:** Full-page images (FPI) are safe to remove because EBS storage is not subject to the torn page problem that plagues direct-attached disk. AWS validated this specifically for RDS Optimized Writes.

---

### Step 1 - Check Supported Instance Families

Supported as of 2024: db.m6i, db.m7g, db.r6i, db.r7g, db.x2g, and all "d" variants.

Check your current instance:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].{Class:DBInstanceClass,OptimizedWrites:MultiAZ}" \
  --output table \
  --region "$REGION"
```

Check if Optimized Writes is already enabled:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].AwsBackupRecoveryPointArn" \
  --output text \
  --region "$REGION"
```

Better - check via parameters:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name "custom-pg16-perf" \
  --query "Parameters[?ParameterName=='rds.optimized_writes'].{Name:ParameterName,Value:ParameterValue}" \
  --output table \
  --region "$REGION"
```

---

### Step 2 - Measure Baseline WAL Generation

Before enabling Optimized Writes, measure current WAL generation:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
-- Record current WAL position
SELECT pg_current_wal_lsn() AS start_lsn;
```

Note the value. Now run a write-heavy workload:

```sql
CREATE TABLE IF NOT EXISTS write_test (
    id BIGSERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    value INT NOT NULL
);

-- Insert 100K rows
INSERT INTO write_test (data, value)
SELECT md5(random()::TEXT), (random() * 1000)::INT
FROM generate_series(1, 100000);

-- Do 10K updates
UPDATE write_test
SET value = value + 1
WHERE id % 10 = 0;

-- Record end WAL position
SELECT pg_current_wal_lsn() AS end_lsn;
```

Calculate WAL generated:

```sql
SELECT
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            'YOUR_START_LSN_HERE'::pg_lsn
        )
    ) AS wal_generated;
```

Note this number. You will compare it after enabling Optimized Writes.

---

### Step 3 - Enable Optimized Writes

### Via Console

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click your instance and then **Modify**.
3. Scroll to **Storage**.
4. Find **RDS Optimized Writes** and enable it.
5. Click **Continue**, then **Apply immediately**, then **Modify DB Instance**.

### Via Parameter Group

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters "ParameterName=rds.optimized_writes,ParameterValue=ON,ApplyMethod=immediate" \
  --region "$REGION"
```

Verify it applied (no restart required):

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "SHOW rds.optimized_writes;"
```

Expected output (yours will differ):
```
 rds.optimized_writes
----------------------
 ON
```

---

### Step 4 - Measure WAL After Enabling Optimized Writes

Drop and recreate the test table (so you start fresh):

```sql
DROP TABLE IF EXISTS write_test;

CREATE TABLE write_test (
    id BIGSERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    value INT NOT NULL
);

-- Record start position
SELECT pg_current_wal_lsn() AS start_lsn;

-- Same workload as before
INSERT INTO write_test (data, value)
SELECT md5(random()::TEXT), (random() * 1000)::INT
FROM generate_series(1, 100000);

UPDATE write_test
SET value = value + 1
WHERE id % 10 = 0;

-- Measure WAL generated
SELECT
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            'YOUR_START_LSN_HERE'::pg_lsn
        )
    ) AS wal_generated_after_optimized_writes;
```

Expected result: WAL generation typically drops 30-50% for write-heavy workloads with many unique page updates.

---

### Step 5 - Monitor full_page_writes

Verify full-page writes are eliminated:

```sql
SELECT name, setting FROM pg_settings WHERE name = 'full_page_writes';
```

Expected output (yours will differ):
```
      name       | setting
-----------------+---------
 full_page_writes | off
```

`full_page_writes = off` confirms that full-page images are no longer being written to WAL. This is safe only because RDS Optimized Writes handles crash safety at the storage level.

---

## Part B: Aurora I/O-Optimized

### Background

Aurora charges for storage I/O separately from storage capacity. In Standard mode, every page read and write to Aurora's distributed storage costs money. In I/O-Optimized mode, there is no per-I/O charge - you pay a higher storage rate instead.

---

### Step 6 - Understand Aurora I/O Costs

Check your current Aurora I/O usage in the AWS Cost Explorer or via CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeReadIOPs \
  --dimensions Name=DbClusterIdentifier,Value="$DB_CLUSTER_ID" \
  --start-time "$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 2592000 \
  --statistics Sum \
  --region "$REGION"
```

And write IOPs:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeWriteIOPs \
  --dimensions Name=DbClusterIdentifier,Value="$DB_CLUSTER_ID" \
  --start-time "$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 2592000 \
  --statistics Sum \
  --region "$REGION"
```

---

### Step 7 - Calculate Break-Even Point

Use this formula to decide whether I/O-Optimized saves money:

```
Standard mode monthly cost:
  storage_cost = storage_gb * $0.10/GB
  io_cost = (read_ios + write_ios) / 1,000,000 * $0.20
  total_standard = storage_cost + io_cost

I/O-Optimized mode monthly cost:
  total_io_optimized = storage_gb * $0.225/GB   (storage rate 125% higher)

Switch to I/O-Optimized when:
  total_standard > total_io_optimized
  io_cost > storage_gb * 0.125
  io_cost / storage_cost > 1.25
```

Example calculation:

```bash
STORAGE_GB=500
READ_IOS=2000000000   # 2 billion reads per month
WRITE_IOS=500000000   # 500 million writes per month

STANDARD_STORAGE=$(echo "scale=2; $STORAGE_GB * 0.10" | bc)
STANDARD_IO=$(echo "scale=2; ($READ_IOS + $WRITE_IOS) / 1000000 * 0.20" | bc)
STANDARD_TOTAL=$(echo "scale=2; $STANDARD_STORAGE + $STANDARD_IO" | bc)

IO_OPTIMIZED_TOTAL=$(echo "scale=2; $STORAGE_GB * 0.225" | bc)

echo "Standard mode: \$$STANDARD_TOTAL/month"
echo "I/O-Optimized: \$$IO_OPTIMIZED_TOTAL/month"
echo "Savings: \$$(echo "scale=2; $STANDARD_TOTAL - $IO_OPTIMIZED_TOTAL" | bc)/month"
```

Expected output (yours will differ):
```
Standard mode: $550.00/month
I/O-Optimized: $112.50/month
Savings: $437.50/month
```

---

### Step 8 - Enable Aurora I/O-Optimized

### Via Console

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click **Databases** and select your Aurora cluster (not an individual instance).
3. Click **Modify**.
4. Under **Storage configuration**, find **Storage type**.
5. Change from **Aurora Standard** to **Aurora I/O-Optimized**.
6. Click **Continue**, then **Apply immediately**, then **Modify cluster**.

### Via CLI

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --storage-type aurora-iopt1 \
  --apply-immediately \
  --region "$REGION"
```

`--storage-type aurora-iopt1`: The identifier for Aurora I/O-Optimized storage.

> **Concept:** Switching between Standard and I/O-Optimized is online - no downtime required. The change takes effect immediately but may take a few minutes to complete.

Wait for the cluster modification:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --region "$REGION"
```

---

### Step 9 - Verify I/O-Optimized is Active

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --query "DBClusters[0].StorageType" \
  --output text \
  --region "$REGION"
```

Expected output:
```
aurora-iopt1
```

`aurora-iopt1` confirms I/O-Optimized is active.

---

### Step 10 - Revert to Standard If Needed

If your I/O volume decreases and Standard becomes cheaper:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier "$DB_CLUSTER_ID" \
  --storage-type aurora \
  --apply-immediately \
  --region "$REGION"
```

---

## Cleanup

```sql
DROP TABLE IF EXISTS write_test;
```

---

## Summary

You have:
- Measured WAL volume before and after enabling RDS Optimized Writes
- Confirmed full_page_writes is safely disabled by Optimized Writes
- Calculated the Aurora I/O break-even point
- Switched an Aurora cluster to I/O-Optimized storage

For write-heavy production workloads: enable Optimized Writes on RDS (it is a net positive with no downside). For Aurora: run the break-even calculation every quarter and switch storage types as your I/O patterns change.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Full-page image (FPI) | 8KB page written to WAL at first modification after checkpoint - crash protection |
| rds.optimized_writes | Parameter that enables storage-level crash safety, allowing FPIs to be eliminated |
| full_page_writes | PostgreSQL parameter - set to off when Optimized Writes handles crash safety |
| aurora-iopt1 | Storage type identifier for Aurora I/O-Optimized |
| VolumeReadIOPs | CloudWatch metric counting Aurora distributed storage read operations |
| VolumeWriteIOPs | CloudWatch metric counting Aurora distributed storage write operations |
