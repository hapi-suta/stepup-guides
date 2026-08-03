# BUILD 03: Cloud Database Backup Strategies

**Module 03 - Cloud Database Services**
**Time Estimate:** 60 minutes
**Prerequisites:** Completed BUILD 01 and BUILD 02, running RDS or Aurora instance

---

## Step 1: Understand Automated Backups in RDS

**Analogy:** Automated backups in RDS are exactly like having pgBackRest configured with `archive_command` for continuous WAL archiving and a cron job for daily full backups. The difference is that AWS sets it all up and manages the storage.

**How automated backups work:**

1. AWS takes a daily snapshot during your backup window (a full backup of your storage volume)
2. AWS continuously archives transaction logs (WAL) throughout the day
3. These two pieces together give you Point-in-Time Recovery (PITR)
4. Backups are stored in S3 internally - you do not see them in your S3 buckets

**Configuration parameters:**

| Setting | Description | DBA Analogy |
|---|---|---|
| `BackupRetentionPeriod` | Days to keep backups (1-35) | pgBackRest `--repo1-retention-full` |
| `PreferredBackupWindow` | UTC time window for daily snapshot | Your cron schedule for pg_basebackup |
| `CopyTagsToSnapshot` | Propagate tags to backups | Naming your backup files |

Check your current backup settings:

**On your Mac, in your terminal:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier lab-postgres \
  --query "DBInstances[0].{Retention:BackupRetentionPeriod,Window:PreferredBackupWindow,LatestRestore:LatestRestorableTime,Storage:AllocatedStorage}"
```

Expected output (yours will differ):
```json
{
    "Retention": 7,
    "Window": "06:00-06:30",
    "LatestRestore": "2026-06-09T15:42:00+00:00",
    "Storage": 20
}
```

Modify the backup retention and window:

```bash
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --backup-retention-period 14 \
  --preferred-backup-window "03:00-03:30" \
  --apply-immediately
```

**Backup window tips:**

- Choose a low-traffic period (like 03:00 UTC for US-based workloads)
- The window must be at least 30 minutes
- Snapshots during the window may cause brief I/O suspension on single-AZ instances
- Multi-AZ instances take snapshots from the standby, so no performance impact on the primary

---

## Step 2: Manual Snapshots - When and Why

Automated backups are continuous and time-limited (max 35 days). Manual snapshots persist until you explicitly delete them.

**When to take manual snapshots:**

- Before a major schema migration
- Before a PostgreSQL version upgrade
- Before changing parameter groups
- Before any change you might want to roll back
- For long-term archival (quarterly, yearly)

Create a manual snapshot:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier lab-postgres \
  --db-snapshot-identifier lab-postgres-pre-migration-$(date +%Y%m%d)
```

Wait for completion:

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier lab-postgres-pre-migration-$(date +%Y%m%d)
echo "Snapshot complete"
```

List all your snapshots:

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier lab-postgres \
  --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,SizeGB:AllocatedStorage,Type:SnapshotType}" \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------------------
|                        DescribeDBSnapshots                          |
+---------------------+-----+--------+-----------+-------------------+
|       Created       | ID  | SizeGB | Status    | Type              |
+---------------------+-----+--------+-----------+-------------------+
|  2026-06-09T03:00   | rds-| 20     | available | automated         |
|  2026-06-09T15:50   | lab-| 20     | available | manual            |
+---------------------+-----+--------+-----------+-------------------+
```

**Automated vs manual snapshots:**

| Feature | Automated | Manual |
|---|---|---|
| Created by | AWS (daily) | You (on demand) |
| Retention | 1-35 days, then deleted | Kept until you delete them |
| Deleted when instance deleted | Yes | No |
| Cost | Free up to DB size | $0.095/GB-month |

---

## Step 3: Cross-Region Snapshot Copy

**Analogy:** This is like copying your pgBackRest backup repository to a different data center for disaster recovery. If your entire AWS region goes down, you can restore from the copy in another region.

Copy a snapshot to another region:

```bash
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier lab-postgres-pre-migration-$(date +%Y%m%d) \
  --target-db-snapshot-identifier lab-postgres-dr-copy-$(date +%Y%m%d) \
  --source-region us-east-1 \
  --region us-west-2 \
  --copy-tags
```

**When to use cross-region copies:**

- Regulatory requirement for geographically separated backups
- Disaster recovery plan that covers entire region failures
- Migrating a database to a different region

**Cost consideration:** You pay for snapshot storage in BOTH regions, plus data transfer between regions (~$0.02/GB).

---

## Step 4: Point-in-Time Recovery (PITR) in RDS

**Analogy:** PITR in RDS works exactly like pgBackRest PITR. AWS uses the daily snapshot as the base backup and replays archived WAL up to your target time. The difference is you never touch `recovery_target_time` in `postgresql.conf`.

**How PITR works in RDS:**

```
Daily Snapshot (base backup)
    |
    +--- WAL archives (continuous) ---> Latest Restorable Time
    |
    You can restore to any second within this range
```

Check your restorable time range:

```bash
aws rds describe-db-instances \
  --db-instance-identifier lab-postgres \
  --query "DBInstances[0].{Earliest:InstanceCreateTime,Latest:LatestRestorableTime}"
```

**Critical concept:** RDS PITR always restores to a NEW instance. You cannot overwrite the existing instance. This is different from self-managed PostgreSQL where you might restore in-place.

**The workflow:**

1. Identify the target time (just before the bad event)
2. Restore to a new instance
3. Verify the data on the new instance
4. If good, rename the old instance and point your application to the new one
5. Delete the old instance

Perform a PITR:

```bash
# First, note the current time (we'll restore to 5 minutes ago)
TARGET_TIME=$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)
echo "Restoring to: $TARGET_TIME"

aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier lab-postgres \
  --target-db-instance-identifier lab-postgres-restored \
  --restore-time "$TARGET_TIME" \
  --db-instance-class db.t3.micro \
  --publicly-accessible
```

Wait for the restored instance:

```bash
aws rds wait db-instance-available --db-instance-identifier lab-postgres-restored
echo "Restore complete"
```

Connect and verify:

```bash
RESTORED_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier lab-postgres-restored \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

psql -h "$RESTORED_ENDPOINT" -U labadmin -d labdb -c "SELECT count(*) FROM employees;"
```

---

## Step 5: Aurora Backtrack (MySQL Only - Not Available for PostgreSQL)

**Important:** Aurora Backtrack is only available for **Aurora MySQL**, not Aurora PostgreSQL. We include it here so you know it exists (you may encounter it in job interviews or mixed-engine environments), but you cannot use it with Aurora PostgreSQL.

**What Backtrack does (Aurora MySQL only):**

- Lets you "rewind" your database to a previous point in time without creating a new instance
- Aurora continuously saves change records
- You specify a backtrack window (up to 72 hours)
- The operation takes seconds to minutes, not the hours a restore takes

**Backtrack vs PITR:**

| Feature | PITR (RDS and Aurora PostgreSQL) | Backtrack (Aurora MySQL only) |
|---|---|---|
| Creates new instance | Yes | No - modifies in-place |
| Time to complete | 30-60 minutes | Seconds to minutes |
| Maximum window | Up to 35 days | Up to 72 hours |
| PostgreSQL support | Yes | **No** |

**For Aurora PostgreSQL, use PITR** (covered in Step 4 above). PITR creates a new cluster from a point-in-time, which takes longer but is the correct approach for PostgreSQL on Aurora

---

## Step 6: Export Snapshots to S3

For long-term archival or analysis outside of RDS, you can export snapshots to S3 in Apache Parquet format.

**Analogy:** This is like running `pg_dump` and storing the output in S3, except AWS does it for you and the format is optimized for analytics tools like Athena and Redshift.

```bash
# Create an S3 bucket for exports
aws s3 mb s3://lab-rds-exports-$(aws sts get-caller-identity --query Account --output text)

# You also need an IAM role and KMS key for the export
# (Simplified - in production, your cloud team sets this up)

aws rds start-export-task \
  --export-task-identifier lab-export-01 \
  --source-arn "arn:aws:rds:us-east-1:$(aws sts get-caller-identity --query Account --output text):snapshot:lab-postgres-pre-migration-$(date +%Y%m%d)" \
  --s3-bucket-name "lab-rds-exports-$(aws sts get-caller-identity --query Account --output text)" \
  --iam-role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/rds-s3-export-role" \
  --kms-key-id "your-kms-key-id"
```

**Note:** The IAM role and KMS key setup can be complex. This is typically a one-time setup that your cloud infrastructure team handles. The key point is knowing this capability exists for archival and analytics use cases.

---

## Step 7: Backup Cost Optimization

Backup storage has real costs. Here is how to optimize:

**Free backup storage:**
- Each RDS instance gets free backup storage equal to its provisioned database storage
- Example: 500 GB instance gets 500 GB of free backup storage

**What costs money:**
- Manual snapshots that accumulate over time
- Backup storage exceeding the free tier
- Cross-region snapshot copies
- Long retention periods (more daily snapshots stored)

**Optimization strategies:**

| Strategy | Savings | Risk |
|---|---|---|
| Reduce retention from 35 to 14 days | Moderate | Less PITR window |
| Delete old manual snapshots | Immediate | Cannot restore from them |
| Use lifecycle policies for cross-region copies | Moderate | Need to implement |
| Use Aurora Backtrack instead of frequent snapshots | Low | 72-hour limit |

Check your current backup storage usage:

```bash
aws rds describe-db-instances \
  --query "DBInstances[*].{Instance:DBInstanceIdentifier,StorageGB:AllocatedStorage,Retention:BackupRetentionPeriod}" \
  --output table
```

List and audit manual snapshots:

```bash
aws rds describe-db-snapshots \
  --snapshot-type manual \
  --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,SizeGB:AllocatedStorage,Created:SnapshotCreateTime}" \
  --output table
```

---

## Step 8: Testing Your Backups

**This is the most important step.** An untested backup is not a backup - it is a hope. Every DBA knows this, but in the cloud it is easy to assume AWS "handles it." You still need to verify.

**Backup test checklist:**

- [ ] Restore from automated backup to a new instance
- [ ] Connect to the restored instance and run queries
- [ ] Verify row counts match expectations
- [ ] Verify recent data is present (check timestamps)
- [ ] Measure restore time (document it for your RTO planning)
- [ ] Delete the test instance when done

**Quarterly backup test procedure:**

```bash
# 1. Get the latest restorable time
LATEST=$(aws rds describe-db-instances \
  --db-instance-identifier lab-postgres \
  --query "DBInstances[0].LatestRestorableTime" \
  --output text)
echo "Latest restorable time: $LATEST"

# 2. Restore to a test instance
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier lab-postgres \
  --target-db-instance-identifier lab-postgres-backup-test \
  --restore-time "$LATEST" \
  --db-instance-class db.t3.micro \
  --publicly-accessible \
  --no-multi-az

# 3. Wait for restore
aws rds wait db-instance-available --db-instance-identifier lab-postgres-backup-test

# 4. Get endpoint and test
TEST_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier lab-postgres-backup-test \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

psql -h "$TEST_ENDPOINT" -U labadmin -d labdb -c "
  SELECT 'Row count' AS check, count(*)::text AS result FROM employees
  UNION ALL
  SELECT 'Max ID', max(id)::text FROM employees
  UNION ALL
  SELECT 'Latest hire', max(hire_date)::text FROM employees;
"

# 5. Clean up
aws rds delete-db-instance \
  --db-instance-identifier lab-postgres-backup-test \
  --skip-final-snapshot
```

---

## Step 9: Restore to a New Instance - The Full Workflow

**Critical concept for DBAs new to RDS:** Restoring in RDS always creates a NEW instance. You cannot restore over the existing one. This changes your recovery workflow.

**Self-managed recovery workflow:**
1. Stop PostgreSQL
2. Restore backup to `$PGDATA`
3. Set `recovery_target_time`
4. Start PostgreSQL
5. Verify data

**RDS recovery workflow:**
1. Restore to a new instance (PITR or snapshot)
2. Wait for instance to become available
3. Connect and verify data
4. Update your application's connection string (or rename instances)
5. Delete the old instance

**Instance renaming trick:**

```bash
# Rename the bad instance
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --new-db-instance-identifier lab-postgres-old \
  --apply-immediately

# Wait for rename to complete
sleep 30

# Rename the restored instance to the original name
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres-restored \
  --new-db-instance-identifier lab-postgres \
  --apply-immediately
```

**Warning:** Renaming changes the DNS endpoint. Any connection strings using the full RDS hostname will break during this transition. If your application uses a CNAME that you control, point the CNAME to the new instance instead.

---

## Step 10: Clean Up

Delete any restored instances created during this guide:

```bash
# Delete restored instance if it exists
aws rds delete-db-instance \
  --db-instance-identifier lab-postgres-restored \
  --skip-final-snapshot 2>/dev/null

# Delete backup test instance if it exists
aws rds delete-db-instance \
  --db-instance-identifier lab-postgres-backup-test \
  --skip-final-snapshot 2>/dev/null

# Delete manual snapshots from this lab
aws rds delete-db-snapshot \
  --db-snapshot-identifier lab-postgres-pre-migration-$(date +%Y%m%d) 2>/dev/null

echo "Cleanup complete"
```

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| Automated backups | Daily snapshots + continuous WAL archiving - configured by retention period and backup window |
| Manual snapshots | On-demand, persist until deleted - take before major changes |
| Cross-region copy | Copy snapshots to another region for disaster recovery |
| PITR | Restore to any second within retention window - always creates a NEW instance |
| Aurora Backtrack | Rewind in-place in seconds - unique to Aurora, 72-hour limit |
| S3 export | Export snapshots in Parquet format for analytics and archival |
| Cost optimization | Free backup storage = provisioned DB size; manual snapshots accumulate costs |
| Backup testing | Untested backups are not backups - test quarterly at minimum |
| Restore workflow | RDS always restores to a new instance - plan for DNS/connection string changes |
