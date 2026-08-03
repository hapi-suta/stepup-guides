# BUILD 01 - Automated Backups
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 35 minutes
**Goal:** View backup status for your Aurora cluster, configure the retention period, verify the backup window, and confirm the latest restorable time.

**Prerequisites:**
- An Aurora PostgreSQL cluster running (e.g., `devops-lab-cluster`)
- AWS CLI configured with a profile that has `rds:*` permissions
- Your cluster identifier ready

---

## Step 1 - Set Your Variables

Open a terminal. Set these variables so you do not retype them throughout the lab.

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
```

`export` makes each variable available in all commands during this terminal session.

---

## Step 2 - View Automated Backup Status

### Console

1. Open the AWS Console and go to **RDS**.
2. Click **Databases** in the left menu.
3. Click your cluster name (e.g., `devops-lab-cluster`).
4. Click the **Maintenance and backups** tab.
5. Under **Backup**, you will see:
   - **Automated backups:** Enabled
   - **Backup retention period:** e.g., 7 days
   - **Latest restore time:** the most recent second you can recover to

### CLI

Run this command to see backup details for your cluster:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{BackupRetention:BackupRetentionPeriod,LatestRestorableTime:LatestRestorableTime,Status:Status,PreferredBackupWindow:PreferredBackupWindow}' \
  --output table
```

`--query` filters the JSON response to only the fields we care about.
`--output table` formats the result as a readable table.

Expected output (yours will differ):

```
------------------------------------------------------------------
|                      DescribeDBClusters                        |
+------------------+---------------------------------------------+
|  BackupRetention |  7                                          |
|  LatestRestorable|  2026-06-09T12:43:11.000Z                   |
|  PreferredBackup |  08:00-09:00                                |
|  Status          |  available                                  |
+------------------+---------------------------------------------+
```

---

## Step 3 - Understand the Backup Window

Aurora continuously backs up your data to S3. The "backup window" for Aurora clusters is the preferred time for system maintenance tasks related to backups (like creating the daily recovery point marker), but unlike standard RDS, Aurora does NOT take a single large daily snapshot during this window.

Check the current backup window:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].PreferredBackupWindow'
```

Expected output (yours will differ):

```
"08:00-09:00"
```

This is a UTC time window. Choose a time that is during low-traffic hours for your application.

---

## Step 4 - Set the Backup Retention Period

### Console

1. Click your cluster in the RDS console.
2. Click **Modify**.
3. Scroll to **Backup**.
4. Change **Backup retention period** to `14` days.
5. Scroll down and click **Continue**.
6. Under **Scheduling of modifications**, select **Apply immediately**.
7. Click **Modify cluster**.

### CLI

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --backup-retention-period 14 \
  --apply-immediately \
  --region $AWS_REGION
```

`--backup-retention-period 14` sets retention to 14 days. Maximum is 35 days.
`--apply-immediately` applies the change now rather than waiting for the next maintenance window.

Expected output (yours will differ):

```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "BackupRetentionPeriod": 14,
        "Status": "available"
    }
}
```

Confirm the change took effect:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].BackupRetentionPeriod'
```

Expected output:

```
14
```

> **Concept:** Unlike standard RDS where setting retention to 0 disables backups entirely, Aurora does NOT allow retention = 0. The minimum is 1 day. Automated backups are always enabled for Aurora clusters.

---

## Step 5 - Check the Latest Restorable Time

The latest restorable time tells you how far forward PITR can reach. It lags 2-5 minutes behind real-time.

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].LatestRestorableTime'
```

Expected output (yours will differ):

```
"2026-06-09T14:37:11.000Z"
```

Compare this to the current time:

```bash
date -u
```

Expected output (yours will differ):

```
Mon Jun  9 14:40:00 UTC 2026
```

The difference between the current time and the latest restorable time is the PITR lag. This is normal - Aurora needs a few minutes to finish committing backup data to S3.

---

## Step 6 - Modify the Backup Window

Change the backup window to a time that does not conflict with your maintenance window:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --preferred-backup-window "06:00-07:00" \
  --apply-immediately \
  --region $AWS_REGION
```

`--preferred-backup-window` uses the format `hh24:mi-hh24:mi` in UTC.
The window must be at least 30 minutes long.

Verify the change:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].PreferredBackupWindow'
```

Expected output:

```
"06:00-07:00"
```

> **Concept:** The backup window and maintenance window must NOT overlap. If you try to set them to the same time, the API returns an error.

---

## Step 7 - View Automated Backup History

List the automated backups for your cluster:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier $CLUSTER_ID \
  --snapshot-type automated \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[*].{SnapshotId:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status,AllocatedStorage:AllocatedStorage}' \
  --output table
```

`--snapshot-type automated` filters to show only the automated backups, not manual ones.

Expected output (yours will differ):

```
----------------------------------------------------------------------------------
|                         DescribeDBClusterSnapshots                             |
+------------------+-----------------+-------+----------------------------------+
|  AllocatedStorage|  Created        | Status|  SnapshotId                      |
+------------------+-----------------+-------+----------------------------------+
|  20              |  2026-06-09T... |  available | rds:devops-lab-cluster-...  |
|  20              |  2026-06-08T... |  available | rds:devops-lab-cluster-...  |
+------------------+-----------------+-------+----------------------------------+
```

> **Concept:** Automated snapshot names start with `rds:` followed by your cluster identifier and a timestamp. You cannot create or delete these directly - AWS manages them based on your retention period.

---

## Step 8 - Verify Backup Configuration Summary

Run a final check that shows all backup-related settings in one view:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{
    Cluster: DBClusterIdentifier,
    BackupRetention: BackupRetentionPeriod,
    BackupWindow: PreferredBackupWindow,
    LatestRestorableTime: LatestRestorableTime,
    Status: Status,
    Engine: Engine,
    EngineVersion: EngineVersion
  }' \
  --output table
```

Expected output (yours will differ):

```
---------------------------------------------------------------------
|                      DescribeDBClusters                           |
+-----------------------+-------------------------------------------+
|  BackupRetention      |  14                                       |
|  BackupWindow         |  06:00-07:00                              |
|  Cluster              |  devops-lab-cluster                       |
|  Engine               |  aurora-postgresql                        |
|  EngineVersion        |  16.4                                     |
|  LatestRestorableTime |  2026-06-09T14:37:11.000Z                 |
|  Status               |  available                                |
+-----------------------+-------------------------------------------+
```

---

## Summary

You can now:
- Check the backup status and retention period for an Aurora cluster
- Change the backup retention period (1-35 days)
- View and modify the preferred backup window
- Check the latest restorable time and understand the 2-5 minute lag
- View the history of automated backups
- Explain why Aurora backups cannot be disabled (minimum 1 day retention)

**Next:** BUILD 02 - Manual Snapshots
