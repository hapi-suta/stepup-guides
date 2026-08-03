# USE 02 - Snapshot Management Exercise
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 35 minutes
**Format:** Hands-on exercise with an Aurora PostgreSQL cluster
**Goal:** Practice a complete snapshot lifecycle - create, verify, copy cross-region, restore, and clean up - simulating a real operational workflow.

**Prerequisites:**
- An Aurora PostgreSQL cluster with data (from BUILD guides)
- AWS CLI configured with rds permissions

---

## Scenario

You are the DBA for [COMPANY]. The engineering team is planning a major data migration this weekend. Your job is to:
1. Take a pre-migration snapshot
2. Verify it is complete and restorable
3. Copy it to a secondary region as insurance
4. Prove you can restore from both copies
5. Document the process for the team

---

## Step 1 - Set Variables

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
export DEST_REGION="us-west-2"
export SNAPSHOT_ID="devops-lab-pre-migration-$(date +%Y%m%d)"
```

---

## Step 2 - Baseline the Cluster

Before taking a snapshot, record what data exists. This is your verification checklist.

```bash
export CLUSTER_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres << 'EOF'
-- Record table inventory
SELECT schemaname, tablename, n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY tablename;

-- Record total database size
SELECT pg_size_pretty(pg_database_size('postgres')) AS db_size;

-- Record a checksum value for verification
SELECT SUM(hashtext(tablename::text))::BIGINT AS schema_fingerprint
FROM pg_tables
WHERE schemaname = 'public';
EOF
```

Write down these values. You will verify them after restore.

---

## Step 3 - Create the Pre-Migration Snapshot

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

Wait for the snapshot to complete:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION
```

Verify the snapshot details:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,Engine:Engine,EngineVersion:EngineVersion,Storage:AllocatedStorage}' \
  --output table
```

Expected output (yours will differ):

```
-------------------------------------------------------------------
|              DescribeDBClusterSnapshots                         |
+---------+-------------------------------------------------------+
|  Created|  2026-06-09T15:00:11.000Z                             |
|  Engine |  aurora-postgresql                                     |
|  ID     |  devops-lab-pre-migration-20260609                     |
|  Status |  available                                             |
|  Storage|  20                                                    |
+---------+-------------------------------------------------------+
```

---

## Step 4 - Copy to the Secondary Region

Get the snapshot ARN:

```bash
export SNAPSHOT_ARN=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].DBClusterSnapshotArn' \
  --output text)
```

Copy to us-west-2:

```bash
aws rds copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier $SNAPSHOT_ARN \
  --target-db-cluster-snapshot-identifier "${SNAPSHOT_ID}-dr" \
  --region $DEST_REGION
```

Wait for the copy:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${SNAPSHOT_ID}-dr" \
  --region $DEST_REGION
```

---

## Step 5 - Verify Both Snapshots Exist

Check the source region:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status}' \
  --output table
```

Check the destination region:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier "${SNAPSHOT_ID}-dr" \
  --region $DEST_REGION \
  --query 'DBClusterSnapshots[0].{ID:DBClusterSnapshotIdentifier,Status:Status}' \
  --output table
```

Both should show `available`.

---

## Step 6 - Restore from the Source Region Snapshot

```bash
export RESTORE_CLUSTER="devops-lab-restore-test"
export RESTORE_INSTANCE="devops-lab-restore-test-inst"

aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier $RESTORE_CLUSTER \
  --snapshot-identifier $SNAPSHOT_ID \
  --engine aurora-postgresql \
  --region $AWS_REGION

aws rds create-db-instance \
  --db-instance-identifier $RESTORE_INSTANCE \
  --db-cluster-identifier $RESTORE_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION

aws rds wait db-cluster-available \
  --db-cluster-identifier $RESTORE_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $RESTORE_INSTANCE \
  --region $AWS_REGION
```

---

## Step 7 - Verify the Restored Data

```bash
export RESTORE_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $RESTORE_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

psql -h $RESTORE_HOST -U postgres -d postgres << 'EOF'
-- Same queries as Step 2 - compare results
SELECT schemaname, tablename, n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY tablename;

SELECT pg_size_pretty(pg_database_size('postgres')) AS db_size;

SELECT SUM(hashtext(tablename::text))::BIGINT AS schema_fingerprint
FROM pg_tables
WHERE schemaname = 'public';
EOF
```

Compare these values with what you recorded in Step 2. They must match.

---

## Step 8 - Write the Migration Safety Report

Fill out this template and share it with the engineering team:

```
PRE-MIGRATION BACKUP REPORT
==============================
Date: [DATE]
Prepared by: [YOUR NAME]
Cluster: devops-lab-cluster

SNAPSHOTS CREATED
-----------------
Source snapshot: devops-lab-pre-migration-20260609 (us-east-1) - VERIFIED
DR copy: devops-lab-pre-migration-20260609-dr (us-west-2) - VERIFIED

RESTORE TEST
-------------
Restore tested: [ ] Yes  [ ] No
Restore time: [X] minutes
Data verified: [ ] Yes  [ ] No
Row counts match: [ ] Yes  [ ] No
Schema fingerprint match: [ ] Yes  [ ] No

ROLLBACK PROCEDURE
------------------
If the migration fails:
1. Restore from snapshot: devops-lab-pre-migration-20260609
2. Estimated restore time: [X] minutes
3. Update application connection string
4. Verify data integrity

CONTACTS
--------
DBA on call: [NAME]
Engineering lead: [NAME]
Incident channel: [SLACK CHANNEL]
```

---

## Step 9 - Cleanup

Delete the restored test cluster:

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORE_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $RESTORE_INSTANCE \
  --region $AWS_REGION

aws rds delete-db-cluster \
  --db-cluster-identifier $RESTORE_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION
```

Keep the snapshots until AFTER the migration is complete. Delete them one week after a successful migration:

```bash
# Run ONLY after migration is confirmed successful:
# aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier $SNAPSHOT_ID --region $AWS_REGION
# aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "${SNAPSHOT_ID}-dr" --region $DEST_REGION
```

---

## Key Takeaways

- Always verify a snapshot by restoring and checking data before relying on it
- Cross-region copies are independent - if the source region fails, the copy is safe
- Document the restore procedure BEFORE you need it
- Keep pre-migration snapshots for at least one week after a successful migration
- The restore test is not optional - an untested backup is not a backup
