# BUILD 02 - Manual Snapshots
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 35 minutes
**Goal:** Create a manual cluster snapshot, copy it to another region, share it with another account, and delete it safely.

**Prerequisites:**
- BUILD 01 complete (backup retention configured)
- An Aurora PostgreSQL cluster in `available` state
- AWS CLI configured with rds permissions

---

## Step 1 - Set Your Variables

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
export DEST_REGION="us-west-2"
export SNAPSHOT_ID="devops-lab-snap-manual-$(date +%Y%m%d)"
```

`$(date +%Y%m%d)` appends today's date so snapshot names are unique each day.

---

## Step 2 - View Existing Manual Snapshots

Before creating a new snapshot, check if any manual snapshots already exist:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier $CLUSTER_ID \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[*].{SnapshotId:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
  --output table
```

`--snapshot-type manual` filters to show only your manually created snapshots.

If no manual snapshots exist, the table will be empty.

---

## Step 3 - Create a Manual Snapshot

A manual snapshot is a full backup you trigger on demand. It is kept until you delete it.

### Console

1. Click your cluster in the RDS console.
2. Click **Actions** (top right).
3. Click **Take snapshot**.
4. Enter a name: `devops-lab-snap-manual-20260609` (replace the date).
5. Click **Take snapshot**.
6. The snapshot status shows `creating` then changes to `available` (2-5 minutes for small clusters).

### CLI

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

`--db-cluster-identifier` is the source cluster to snapshot.
`--db-cluster-snapshot-identifier` is the name you choose for this snapshot.

Expected output (yours will differ):

```json
{
    "DBClusterSnapshot": {
        "DBClusterSnapshotIdentifier": "devops-lab-snap-manual-20260609",
        "DBClusterIdentifier": "devops-lab-cluster",
        "Status": "creating",
        "AllocatedStorage": 20
    }
}
```

Wait for the snapshot to become available:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

`aws rds wait` blocks until the snapshot reaches `available` status. It polls every 30 seconds and times out after 20 minutes.

This command returns nothing when done. You will get your prompt back.

Verify the snapshot:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,Engine:Engine,EngineVersion:EngineVersion}' \
  --output table
```

Expected output (yours will differ):

```
-------------------------------------------------------------------
|                 DescribeDBClusterSnapshots                      |
+----------+-----------------------------------------------------+
|  Created |  2026-06-09T14:22:11.000Z                           |
|  Engine  |  aurora-postgresql                                   |
|  EngineV.|  16.4                                                |
|  ID      |  devops-lab-snap-manual-20260609                     |
|  Status  |  available                                           |
+----------+-----------------------------------------------------+
```

---

## Step 4 - Copy the Snapshot to Another Region

Copying to another region creates an independent copy for geographic disaster recovery.

### Console

1. Go to **RDS > Snapshots** in the left menu.
2. Click **Manual** tab to see your manual snapshot.
3. Select the snapshot checkbox.
4. Click **Actions > Copy snapshot**.
5. Set **Destination Region** to `us-west-2`.
6. Set a name for the copy: `devops-lab-snap-manual-20260609-copy`.
7. Leave encryption as default.
8. Click **Copy snapshot**.
9. Switch your console region to `us-west-2` to see the copy arrive.

### CLI

```bash
aws rds copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster-snapshot:${SNAPSHOT_ID}" \
  --target-db-cluster-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --region $DEST_REGION
```

`--source-db-cluster-snapshot-identifier` must be the full ARN when copying cross-region.
`--target-db-cluster-snapshot-identifier` is the name for the new copy in the destination region.

Expected output (yours will differ):

```json
{
    "DBClusterSnapshot": {
        "DBClusterSnapshotIdentifier": "devops-lab-snap-manual-20260609-copy",
        "Status": "copying",
        "SourceDBClusterSnapshotArn": "arn:aws:rds:us-east-1:..."
    }
}
```

Wait for the copy to finish in the destination region:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --region $DEST_REGION
```

Verify the copy exists in the destination region:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --region $DEST_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status,Region:AvailabilityZones[0]}' \
  --output table
```

---

## Step 5 - Share a Snapshot with Another Account

> **Note:** This step requires a second AWS account ID. If you do not have one, read through without executing.

Set the target account ID:

```bash
export TARGET_ACCOUNT_ID="123456789012"
```

Replace `123456789012` with the actual account ID you want to share with.

### Console

1. Go to **RDS > Snapshots > Manual**.
2. Select your snapshot.
3. Click **Actions > Share snapshot**.
4. Under **DB cluster snapshot visibility**, keep it as **Private**.
5. In the **AWS account ID** field, type the target account ID.
6. Click **Add**.
7. Click **Save**.

### CLI

```bash
aws rds modify-db-cluster-snapshot-attribute \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --attribute-name restore \
  --values-to-add $TARGET_ACCOUNT_ID \
  --region $AWS_REGION
```

`--attribute-name restore` grants the other account permission to restore from this snapshot.
`--values-to-add` is the list of account IDs to grant access.

Verify the share worked:

```bash
aws rds describe-db-cluster-snapshot-attributes \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshotAttributesResult.DBClusterSnapshotAttributes'
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

## Step 6 - Delete a Snapshot

### Confirm Before Deleting

Before deleting, verify you are deleting the right snapshot:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Engine:Engine}'
```

Expected output (yours will differ):

```json
{
    "ID": "devops-lab-snap-manual-20260609",
    "Created": "2026-06-09T14:22:11.000Z",
    "Engine": "aurora-postgresql"
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
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

There is no confirmation prompt in the CLI. The snapshot is deleted immediately.

Delete the cross-region copy too:

```bash
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${SNAPSHOT_ID}-copy" \
  --region $DEST_REGION
```

---

## Step 7 - Verify Cleanup

Confirm both snapshots are gone:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION 2>&1
```

Expected output:

```
An error occurred (DBClusterSnapshotNotFoundFault) when calling the
DescribeDBClusterSnapshots operation: DBClusterSnapshot
devops-lab-snap-manual-20260609 not found.
```

This error message is expected - it confirms the snapshot no longer exists.

---

## Summary

You can now:
- View existing manual snapshots for an Aurora cluster
- Create a manual snapshot on demand
- Copy a snapshot to another region for geographic DR
- Share a snapshot with another AWS account
- Delete snapshots safely with verification
- Explain the difference between automated backups and manual snapshots

**Next:** BUILD 03 - Point-In-Time Recovery
