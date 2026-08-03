# BUILD 04 - Cross-Region Backup
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 35 minutes
**Goal:** Copy an Aurora cluster snapshot to another AWS region, restore a cluster from the cross-region copy, verify the data, and clean up.

**Prerequisites:**
- BUILD 02 complete (you know how to create manual snapshots)
- An Aurora PostgreSQL cluster with data
- AWS CLI configured with rds permissions

---

## Step 1 - Set Your Variables

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
export DEST_REGION="us-west-2"
export SNAPSHOT_ID="devops-lab-xregion-$(date +%Y%m%d)"
export COPY_SNAPSHOT_ID="${SNAPSHOT_ID}-copy"
export RESTORED_CLUSTER="devops-lab-xregion-restore"
export RESTORED_INSTANCE="devops-lab-xregion-inst"
```

---

## Step 2 - Create a Snapshot in the Source Region

If you already have a recent manual snapshot, you can skip this step and use that snapshot instead.

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

Wait for it to become available:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

Verify the snapshot:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status,Storage:AllocatedStorage}' \
  --output table
```

Expected output (yours will differ):

```
----------------------------------------------------------
|              DescribeDBClusterSnapshots                |
+---------+------+---------------------------------------+
|  ID     |Status|  Storage                              |
+---------+------+---------------------------------------+
|  devops-lab-xregion-20260609 | available | 20          |
+---------+------+---------------------------------------+
```

---

## Step 3 - Get the Snapshot ARN

Cross-region copies require the full ARN of the source snapshot:

```bash
export SNAPSHOT_ARN=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].DBClusterSnapshotArn' \
  --output text)

echo "Snapshot ARN: $SNAPSHOT_ARN"
```

Expected output (yours will differ):

```
Snapshot ARN: arn:aws:rds:us-east-1:123456789012:cluster-snapshot:devops-lab-xregion-20260609
```

---

## Step 4 - Copy the Snapshot to the Destination Region

### Console

1. Go to **RDS > Snapshots** in the source region (us-east-1).
2. Click **Manual** tab.
3. Select your snapshot.
4. Click **Actions > Copy snapshot**.
5. Set **Destination Region** to `us-west-2`.
6. Enter a name: `devops-lab-xregion-20260609-copy`.
7. Click **Copy snapshot**.
8. Switch your console region to `us-west-2` to monitor the copy.

### CLI

```bash
aws rds copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier $SNAPSHOT_ARN \
  --target-db-cluster-snapshot-identifier $COPY_SNAPSHOT_ID \
  --region $DEST_REGION
```

`--source-db-cluster-snapshot-identifier` must be the full ARN for cross-region copies.
`--region` is the destination region where the copy will be created.

Expected output (yours will differ):

```json
{
    "DBClusterSnapshot": {
        "DBClusterSnapshotIdentifier": "devops-lab-xregion-20260609-copy",
        "Status": "copying",
        "SourceDBClusterSnapshotArn": "arn:aws:rds:us-east-1:..."
    }
}
```

Wait for the copy to finish in the destination region:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $COPY_SNAPSHOT_ID \
  --region $DEST_REGION
```

This may take several minutes depending on the snapshot size.

---

## Step 5 - Verify the Copy in the Destination Region

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $COPY_SNAPSHOT_ID \
  --region $DEST_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status,Engine:Engine,EngineVersion:EngineVersion,Storage:AllocatedStorage}' \
  --output table
```

Expected output (yours will differ):

```
------------------------------------------------------------------
|              DescribeDBClusterSnapshots                        |
+---------+-----------+---------+----------------+---------------+
|  Engine |EngineVers.|  ID     |  Status        | Storage       |
+---------+-----------+---------+----------------+---------------+
|  aurora-postgresql | 16.4    | devops-lab...  | available     | 20 |
+---------+-----------+---------+----------------+---------------+
```

The snapshot now exists independently in `us-west-2`. Even if `us-east-1` goes completely down, this copy is safe.

---

## Step 6 - Restore a Cluster from the Cross-Region Copy

This simulates a regional disaster recovery scenario. You restore the cluster in the secondary region.

### Prerequisites for the Destination Region

You need a DB subnet group and VPC security group in the destination region. If you do not have these, create them or use defaults.

```bash
export DEST_SUBNET_GROUP="your-dest-subnet-group"
export DEST_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

### Restore the Cluster

```bash
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --snapshot-identifier $COPY_SNAPSHOT_ID \
  --engine aurora-postgresql \
  --db-subnet-group-name $DEST_SUBNET_GROUP \
  --vpc-security-group-ids $DEST_SG_ID \
  --region $DEST_REGION
```

`--snapshot-identifier` is the name of the snapshot copy in the destination region.
`--engine` must be specified when restoring from a snapshot.

Add an instance to the restored cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $DEST_REGION
```

Wait for both to become available:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $DEST_REGION
```

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $DEST_REGION
```

---

## Step 7 - Verify Data in the Destination Region

Get the restored cluster endpoint:

```bash
export RESTORED_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $DEST_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo $RESTORED_HOST
```

Connect and verify your data:

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
```

Check row counts:

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;"
```

The data should match what existed at the time the source snapshot was taken.

---

## Step 8 - Cleanup

Delete the restored instance in the destination region:

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $DEST_REGION
```

Wait for deletion:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $DEST_REGION
```

Delete the restored cluster:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --skip-final-snapshot \
  --region $DEST_REGION
```

Delete the snapshot copy in the destination region:

```bash
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier $COPY_SNAPSHOT_ID \
  --region $DEST_REGION
```

Delete the source snapshot:

```bash
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

---

## Summary

You can now:
- Create a manual snapshot and get its ARN for cross-region operations
- Copy a cluster snapshot to another AWS region using the full ARN
- Wait for the cross-region copy to complete
- Restore a full Aurora cluster from a cross-region snapshot copy
- Verify data integrity in the restored cluster
- Clean up all resources in both regions

**Key concept:** Cross-region copies are independent - if the source region goes down, the copy in the destination region is unaffected. This is the foundation of geographic disaster recovery.

**Next:** BUILD 05 - Blue/Green Deployments
