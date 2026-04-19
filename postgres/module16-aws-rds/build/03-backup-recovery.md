# BUILD 03 - Backup and Recovery on RDS/Aurora

## What You Will Build

By the end of this guide you will know how to manage automated backups, take manual snapshots, perform point-in-time recovery, copy snapshots cross-region, and use Aurora backtrack. These are the core disaster recovery tools for RDS.

---

## Prerequisites

- Completed BUILD 01 (RDS instance `suta-pg-lab` running)
- AWS CLI v2 configured
- psql client installed

---

## Understanding RDS Backup Types

| Feature | Automated Backups | Manual Snapshots |
|---------|-------------------|------------------|
| Created by | RDS (daily) | You (on demand) |
| Retention | 0-35 days (configurable) | Kept until you delete |
| Enables PITR | Yes | No |
| Survives instance deletion | No (unless you set retention) | Yes |
| Cost | Included up to 1x DB size | Charged per GB-month |

---

## Step 1 - Check Automated Backup Configuration

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Retention:BackupRetentionPeriod,Window:PreferredBackupWindow,LatestRestore:LatestRestorableTime}" \
    --output table
```

The `BackupRetentionPeriod` shows how many days automated backups are kept. `PreferredBackupWindow` is when daily snapshots occur. `LatestRestorableTime` is the most recent point you can restore to (usually within the last 5 minutes).

Expected output (yours will differ):

```
-----------------------------------------------------------------
|                    DescribeDBInstances                         |
+-------------------+-------------------------------------------+
|  LatestRestore    |  2024-01-15T12:25:00+00:00                |
|  Retention        |  7                                        |
|  Window           |  03:00-04:00                               |
+-------------------+-------------------------------------------+
```

---

## Step 2 - Modify Backup Retention

To change the retention period:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --backup-retention-period 14 \
    --apply-immediately
```

The `--backup-retention-period 14` keeps automated backups for 14 days. Setting this to 0 disables automated backups entirely (not recommended). `--apply-immediately` applies the change without waiting for the maintenance window.

---

## Step 3 - Create Test Data for Recovery Exercises

Connect to the instance:

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Create a table with timestamped data:

```sql
CREATE TABLE recovery_test (
    id serial PRIMARY KEY,
    data text,
    created_at timestamptz DEFAULT now()
);
```

```sql
INSERT INTO recovery_test (data) VALUES ('before-snapshot');
```

```sql
SELECT now();
```

Write down this timestamp - you will need it for PITR later.

Expected output (yours will differ):

```
              now
-------------------------------
 2024-01-15 12:35:00.123456+00
(1 row)
```

Exit psql:

```sql
\q
```

---

## Step 4 - Take a Manual Snapshot

```bash
aws rds create-db-snapshot \
    --db-instance-identifier suta-pg-lab \
    --db-snapshot-identifier suta-pg-lab-snap-01
```

The `--db-snapshot-identifier` is the name you assign to this snapshot. The snapshot captures the entire instance including all databases.

Expected output (yours will differ):

```json
{
    "DBSnapshot": {
        "DBSnapshotIdentifier": "suta-pg-lab-snap-01",
        "DBInstanceIdentifier": "suta-pg-lab",
        "Status": "creating",
        "Engine": "postgres",
        "AllocatedStorage": 50,
        ...
    }
}
```

Wait for the snapshot to complete:

```bash
aws rds wait db-snapshot-available \
    --db-snapshot-identifier suta-pg-lab-snap-01
```

This polls until the snapshot status is `available`. For a 50 GB instance, this typically takes 5-15 minutes.

---

## Step 5 - List Your Snapshots

```bash
aws rds describe-db-snapshots \
    --db-instance-identifier suta-pg-lab \
    --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Time:SnapshotCreateTime,Size:AllocatedStorage,Type:SnapshotType}" \
    --output table
```

The `Type` column shows `manual` for your snapshots and `automated` for RDS daily backups.

Expected output (yours will differ):

```
------------------------------------------------------------------------------
|                          DescribeDBSnapshots                               |
+------------------------+-----------+----------------------------+----+------+
|          ID            |  Size     |           Time             |Status|Type|
+------------------------+-----------+----------------------------+------+----+
| suta-pg-lab-snap-01    |  50       | 2024-01-15T12:40:00+00:00  | available | manual    |
| rds:suta-pg-lab-2024.. |  50       | 2024-01-15T03:00:00+00:00  | available | automated |
+------------------------+-----------+----------------------------+-----------+----------+
```

---

## Step 6 - Add More Data After Snapshot

This creates data that exists after the snapshot but before PITR.

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
INSERT INTO recovery_test (data) VALUES ('after-snapshot-1');
```

```sql
INSERT INTO recovery_test (data) VALUES ('after-snapshot-2');
```

Note the current time:

```sql
SELECT now();
```

Write down this timestamp too.

Now simulate accidental data loss:

```sql
DELETE FROM recovery_test;
```

```sql
SELECT * FROM recovery_test;
```

Expected output:

```
 id | data | created_at
----+------+------------
(0 rows)
```

The data is gone. Exit psql:

```sql
\q
```

---

## Step 7 - Point-in-Time Recovery (PITR)

PITR creates a NEW instance restored to any second within your backup retention period. It does NOT modify the existing instance.

Use the timestamp from before the DELETE:

```bash
aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier suta-pg-lab \
    --target-db-instance-identifier suta-pg-lab-pitr \
    --restore-time "2024-01-15T12:45:00Z" \
    --db-instance-class db.t3.medium \
    --vpc-security-group-ids "${SG_ID}" \
    --db-subnet-group-name suta-pg-subnet-group \
    --no-publicly-accessible
```

Replace `2024-01-15T12:45:00Z` with the timestamp you noted in Step 6 (the one BEFORE the DELETE).

Flag breakdown:
- `--source-db-instance-identifier` - the instance whose backups you are restoring from
- `--target-db-instance-identifier` - the NEW instance that will be created
- `--restore-time` - the exact second to restore to (UTC format)
- `--db-instance-class` - can be different from the source
- `--vpc-security-group-ids` - must specify (not copied from source)
- `--no-publicly-accessible` - security best practice

To restore to the latest possible time instead of a specific time:

```bash
aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier suta-pg-lab \
    --target-db-instance-identifier suta-pg-lab-latest \
    --use-latest-restorable-time \
    --db-instance-class db.t3.medium \
    --vpc-security-group-ids "${SG_ID}" \
    --db-subnet-group-name suta-pg-subnet-group \
    --no-publicly-accessible
```

Wait for the restored instance:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab-pitr
```

---

## Step 8 - Verify Restored Data

Get the new instance's endpoint:

```bash
PITR_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab-pitr --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${PITR_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT * FROM recovery_test;
```

Expected output (yours will differ):

```
 id |       data       |          created_at
----+------------------+-------------------------------
  1 | before-snapshot  | 2024-01-15 12:35:00.123456+00
  2 | after-snapshot-1 | 2024-01-15 12:45:10.654321+00
  3 | after-snapshot-2 | 2024-01-15 12:45:15.789012+00
(3 rows)
```

The data is recovered up to your specified restore time, including the rows inserted after the manual snapshot.

Exit psql:

```sql
\q
```

---

## Step 9 - Restore from Snapshot

Restoring from a snapshot also creates a NEW instance:

```bash
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier suta-pg-lab-from-snap \
    --db-snapshot-identifier suta-pg-lab-snap-01 \
    --db-instance-class db.t3.medium \
    --vpc-security-group-ids "${SG_ID}" \
    --db-subnet-group-name suta-pg-subnet-group \
    --no-publicly-accessible
```

This restores to the exact moment the snapshot was taken. Unlike PITR, you cannot choose an arbitrary point in time - only the snapshot time.

Wait for it:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab-from-snap
```

Verify - this will only have the "before-snapshot" row since the snapshot was taken before the other inserts:

```bash
SNAP_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab-from-snap --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${SNAP_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT * FROM recovery_test;
```

Expected output:

```
 id |      data       |          created_at
----+-----------------+-------------------------------
  1 | before-snapshot | 2024-01-15 12:35:00.123456+00
(1 row)
```

Exit psql:

```sql
\q
```

---

## Step 10 - Cross-Region Snapshot Copy

Copy a snapshot to another region for disaster recovery:

```bash
aws rds copy-db-snapshot \
    --source-db-snapshot-identifier arn:aws:rds:us-east-1:123456789012:snapshot:suta-pg-lab-snap-01 \
    --target-db-snapshot-identifier suta-pg-lab-snap-01-copy \
    --region us-west-2
```

For cross-region copies, you must use the full ARN for `--source-db-snapshot-identifier`, not just the name. The `--region us-west-2` tells AWS to create the copy in us-west-2.

Get the ARN of your snapshot:

```bash
aws rds describe-db-snapshots \
    --db-snapshot-identifier suta-pg-lab-snap-01 \
    --query "DBSnapshots[0].DBSnapshotArn" \
    --output text
```

Expected output (yours will differ):

```
arn:aws:rds:us-east-1:123456789012:snapshot:suta-pg-lab-snap-01
```

---

## Step 11 - Aurora Backtrack (Aurora Only)

Backtrack lets you rewind an Aurora cluster to a previous point in time WITHOUT creating a new instance. It modifies the existing cluster in place.

To enable backtrack, the cluster must be created with it (or you can enable it later):

```bash
aws rds modify-db-cluster \
    --db-cluster-identifier suta-aurora-pg-lab \
    --backtrack-window 86400
```

The `--backtrack-window` is in seconds. 86400 seconds = 24 hours. This means you can backtrack to any point within the last 24 hours.

To actually backtrack:

```bash
aws rds backtrack-db-cluster \
    --db-cluster-identifier suta-aurora-pg-lab \
    --backtrack-to "2024-01-15T12:45:00Z"
```

Replace with the time you want to rewind to. Backtrack takes seconds, not minutes. The cluster briefly becomes unavailable (usually under 1 minute) then comes back at the specified point in time.

**Important**: Backtrack rewinds ALL data. You cannot backtrack a single table. Any writes after the backtrack point are lost.

Check backtrack status:

```bash
aws rds describe-db-cluster-backtracks \
    --db-cluster-identifier suta-aurora-pg-lab \
    --query "DBClusterBacktracks[0].{Status:Status,BacktrackTo:BacktrackTo,BacktrackedFrom:BacktrackedFrom}"
```

Expected output (yours will differ):

```json
{
    "Status": "completed",
    "BacktrackTo": "2024-01-15T12:45:00Z",
    "BacktrackedFrom": "2024-01-15T13:00:00Z"
}
```

---

## Step 12 - Verify Backup Cost

Check how much storage your snapshots use:

```bash
aws rds describe-db-snapshots \
    --db-instance-identifier suta-pg-lab \
    --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,SizeGB:AllocatedStorage,Type:SnapshotType}" \
    --output table
```

Automated backups up to 1x your provisioned storage size are free. Manual snapshots are charged at ~$0.095/GB-month.

---

## Summary

You learned:
- Automated backups run daily and enable PITR for up to 35 days
- Manual snapshots persist until you delete them
- PITR creates a new instance at any second within retention
- Snapshot restore creates a new instance at the snapshot time
- Cross-region copies require the full snapshot ARN
- Aurora backtrack rewinds in place (seconds, not minutes)
- Restored instances always get a new endpoint

Key decision guide:
- "I need to undo something from minutes ago" - PITR or Aurora backtrack
- "I need a copy of the database at a specific milestone" - Manual snapshot
- "I need DR in another region" - Cross-region snapshot copy

---

## Clean Up

Delete the test instances:

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-pg-lab-pitr \
    --skip-final-snapshot \
    --delete-automated-backups
```

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-pg-lab-from-snap \
    --skip-final-snapshot \
    --delete-automated-backups
```

Delete the manual snapshot:

```bash
aws rds delete-db-snapshot \
    --db-snapshot-identifier suta-pg-lab-snap-01
```
