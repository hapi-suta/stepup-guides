# BUILD 01 - Automated Backups and Snapshots
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 40 minutes
**Goal:** View backup status, configure retention, create a snapshot, copy it to another region, share it with another account, and delete it safely.

**Prerequisites:**
- An RDS PostgreSQL instance running (db.t3.micro is fine)
- AWS CLI configured with a profile that has `rds:*` permissions
- Your instance identifier ready (e.g., `suta-t5-primary-hfa`)

---

## Step 1 - Set Your Variables

Open a terminal. Set these variables so you do not retype them throughout the lab.

```bash
export DB_INSTANCE="suta-t5-primary-hfa"
export AWS_REGION="us-east-1"
export DEST_REGION="us-west-2"
export SNAPSHOT_ID="suta-t5-snap-manual-$(date +%Y%m%d)"
```

Each `export` makes the variable available in all commands in this session.
`$(date +%Y%m%d)` appends today's date so snapshot names are unique.

---

## Step 2 - View Automated Backup Status

### Console

1. Open the AWS Console and go to **RDS**.
2. Click **Databases** in the left menu.
3. Click your instance name.
4. Click the **Maintenance and backups** tab.
5. Under **Backup**, you will see:
   - **Automated backups:** Enabled or Disabled
   - **Backup retention period:** e.g., 7 days
   - **Backup window:** e.g., 08:00-09:00 UTC
   - **Latest restore time:** the most recent second you can recover to

### CLI

Run this command to see backup details:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{BackupRetention:BackupRetentionPeriod,BackupWindow:PreferredBackupWindow,LatestRestorableTime:LatestRestorableTime,Status:DBInstanceStatus}' \
  --output table
```

`--query` filters the JSON response to only the fields we care about.
`--output table` formats the result as a readable table.

Expected output (yours will differ):

```
------------------------------------------------------------------
|                      DescribeDBInstances                       |
+------------------+---------------------------------------------+
|  BackupRetention |  7                                          |
|  BackupWindow    |  08:00-09:00                                |
|  LatestRestorable|  2025-05-30T12:43:11.000Z                   |
|  Status          |  available                                  |
+------------------+---------------------------------------------+
```

---

## Step 3 - View Existing Automated Backups

Automated backups are stored as a special type of snapshot. View them:

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --snapshot-type automated \
  --region $AWS_REGION \
  --query 'DBSnapshots[*].{SnapshotId:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status,AllocatedStorage:AllocatedStorage}' \
  --output table
```

`--snapshot-type automated` filters to show only the daily automated backups, not manual ones.

Expected output (yours will differ):

```
----------------------------------------------------------------------------------
|                            DescribeDBSnapshots                                 |
+------------------+-----------------+-------+----------------------------------+
|  AllocatedStorage|  Created        | Status|  SnapshotId                      |
+------------------+-----------------+-------+----------------------------------+
|  20              |  2025-05-30T... |  available | rds:suta-t5-primary-hfa-... |
|  20              |  2025-05-29T... |  available | rds:suta-t5-primary-hfa-... |
+------------------+-----------------+-------+----------------------------------+
```

> **Concept:** Automated snapshot names start with `rds:` followed by your instance identifier and a timestamp. You cannot create or delete these directly - AWS manages them.

---

## Step 4 - Set the Backup Retention Period

### Console

1. Click your instance in the RDS console.
2. Click **Modify**.
3. Scroll to **Backup**.
4. Change **Backup retention period** to `14` days.
5. Scroll down and click **Continue**.
6. Under **Scheduling of modifications**, select **Apply immediately**.
7. Click **Modify DB Instance**.

> **Concept:** Retention period controls how far back PITR can reach. Longer retention costs more in S3 storage. Maximum is 35 days. Setting to 0 disables automated backups entirely (this also disables PITR).

### CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --backup-retention-period 14 \
  --apply-immediately \
  --region $AWS_REGION
```

`--backup-retention-period 14` sets retention to 14 days.
`--apply-immediately` applies the change now rather than waiting for the next maintenance window.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "suta-t5-primary-hfa",
        "BackupRetentionPeriod": 14,
        "PendingModifiedValues": {}
    }
}
```

Confirm the change took effect:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].BackupRetentionPeriod'
```

Expected output:

```
14
```

---

## Step 5 - Create a Manual Snapshot

A manual snapshot is a full backup you trigger on demand. It is kept until you delete it.

### Console

1. Click your instance in the RDS console.
2. Click **Actions** (top right).
3. Click **Take snapshot**.
4. Enter a name: `suta-t5-snap-manual-20250530` (replace the date).
5. Click **Take snapshot**.
6. The snapshot status shows `creating` then changes to `available` (2-5 minutes for small instances).

### CLI

```bash
aws rds create-db-snapshot \
  --db-instance-identifier $DB_INSTANCE \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

`--db-instance-identifier` is the source instance to snapshot.
`--db-snapshot-identifier` is the name you choose for this snapshot.

Expected output (yours will differ):

```json
{
    "DBSnapshot": {
        "DBSnapshotIdentifier": "suta-t5-snap-manual-20250530",
        "DBInstanceIdentifier": "suta-t5-primary-hfa",
        "Status": "creating",
        "AllocatedStorage": 20
    }
}
```

Wait for the snapshot to become available:

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

`aws rds wait` blocks until the resource reaches the target state. It polls every 30 seconds and times out after 20 minutes.

This command returns nothing when done. You will get your prompt back.

---

## Step 6 - Copy the Snapshot to Another Region

Copying to another region creates an independent copy for geographic disaster recovery.

### Console

1. Go to **RDS > Snapshots** in the left menu.
2. Click **Manual** tab to see your manual snapshot.
3. Select the snapshot checkbox.
4. Click **Actions > Copy snapshot**.
5. Set **Destination Region** to `us-west-2`.
6. Set a name for the copy: `suta-t5-snap-manual-20250530-copy`.
7. Leave encryption as default.
8. Click **Copy snapshot**.
9. Switch your console region to `us-west-2` to see the copy arrive.

### CLI

```bash
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier $SNAPSHOT_ID \
  --target-db-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --source-region $AWS_REGION \
  --region $DEST_REGION
```

`--source-region` is where the original snapshot lives.
`--region` is where the copy will be created (the destination).
`--target-db-snapshot-identifier` is the name for the new copy.

Expected output (yours will differ):

```json
{
    "DBSnapshot": {
        "DBSnapshotIdentifier": "suta-t5-snap-manual-20250530-copy",
        "Status": "pending",
        "SourceRegion": "us-east-1",
        "SourceDBSnapshotIdentifier": "arn:aws:rds:us-east-1:..."
    }
}
```

Wait for the copy to finish in the destination region:

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --region $DEST_REGION
```

---

## Step 7 - Share a Snapshot with Another Account

> **Note:** This step requires you to have access to a second AWS account ID. Use a test account. If you do not have a second account, read through this step without executing.

Set the target account ID:

```bash
export TARGET_ACCOUNT_ID="123456789012"
```

Replace `123456789012` with the actual account ID you want to share with.

### Console

1. Go to **RDS > Snapshots > Manual**.
2. Select your snapshot.
3. Click **Actions > Share snapshot**.
4. Under **DB snapshot visibility**, keep it as **Private**.
5. In the **AWS account ID** field, type the target account ID.
6. Click **Add**.
7. Click **Save**.

### CLI

```bash
aws rds modify-db-snapshot-attribute \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --attribute-name restore \
  --values-to-add $TARGET_ACCOUNT_ID \
  --region $AWS_REGION
```

`--attribute-name restore` is the specific permission that allows the other account to restore from this snapshot.
`--values-to-add` is the list of account IDs to grant access.

Verify the share worked:

```bash
aws rds describe-db-snapshot-attributes \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBSnapshotAttributesResult.DBSnapshotAttributes'
```

Expected output (yours will differ):

```json
[
    {
        "AttributeName": "restore",
        "AttributeValues": [
            "123456789012"
        ]
    }
]
```

> **Concept:** The other account must copy the snapshot into their own account before they can restore from it. They cannot restore directly from your shared snapshot.

---

## Step 8 - Delete a Snapshot

### Confirm Before Deleting

Before deleting, verify you are deleting the right snapshot:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBSnapshots[0].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime,Size:AllocatedStorage}'
```

Expected output (yours will differ):

```json
{
    "ID": "suta-t5-snap-manual-20250530",
    "Created": "2025-05-30T08:14:22.000Z",
    "Size": 20
}
```

### Console

1. Go to **RDS > Snapshots > Manual**.
2. Select the snapshot.
3. Click **Actions > Delete snapshot**.
4. Type `delete me` in the confirmation box.
5. Click **Delete**.

### CLI

```bash
aws rds delete-db-snapshot \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

There is no confirmation prompt in the CLI. The snapshot is deleted immediately.

Delete the cross-region copy too:

```bash
aws rds delete-db-snapshot \
  --db-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --region $DEST_REGION
```

---

## Step 9 - Verify Cleanup

Confirm both snapshots are gone:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION 2>&1
```

Expected output:

```
An error occurred (DBSnapshotNotFound) when calling the DescribeDBSnapshots operation:
DBSnapshot suta-t5-snap-manual-20250530 not found.
```

This error message is expected - it confirms the snapshot no longer exists.

---

## Summary

You can now:
- Check what automated backups exist and how far back PITR can reach
- Change the backup retention period
- Create a manual snapshot on demand
- Copy a snapshot to another region for DR
- Share a snapshot with another AWS account
- Delete snapshots safely with verification

**Next:** BUILD 02 - Point-In-Time Recovery
