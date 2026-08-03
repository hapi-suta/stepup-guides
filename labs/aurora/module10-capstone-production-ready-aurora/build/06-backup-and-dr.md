# Module 10 - Build Guide 06: Backup and Disaster Recovery

**Objective:** Implement a complete backup strategy for your Aurora cluster - automated backups, manual snapshots, cross-region snapshot copy, point-in-time recovery testing, and a documented DR runbook.
**Time:** 35 minutes
**Level:** Senior / Staff
**Prerequisites:** Build Guide 03 completed (Aurora cluster deployed).

---

## 1. Verify Automated Backups

Aurora takes automated backups continuously. Verify the configuration matches your architecture document.

**On your local workstation:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[BackupRetentionPeriod,PreferredBackupWindow,PreferredMaintenanceWindow,EarliestRestorableTime,LatestRestorableTime]' \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------------------------------
|                           DescribeDBClusters                                     |
+----+-----------+-------------------+---------------------------+-----------------+
| 14 | 02:00-03:00| sun:03:00-sun:04:00| 2026-05-26T02:00:00Z   | 2026-06-09T12:00:00Z |
+----+-----------+-------------------+---------------------------+-----------------+
```

- `BackupRetentionPeriod: 14` - Automated backups retained for 14 days
- `PreferredBackupWindow: 02:00-03:00` - Backups run daily at 2 AM UTC
- `PreferredMaintenanceWindow: sun:03:00-sun:04:00` - Maintenance runs Sunday 3 AM UTC (after backup window)
- `EarliestRestorableTime` - The oldest point you can restore to
- `LatestRestorableTime` - The most recent point you can restore to (usually within the last 5 minutes)

If any values are incorrect, update them:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --backup-retention-period 14 \
  --preferred-backup-window "02:00-03:00" \
  --preferred-maintenance-window "sun:03:00-sun:04:00" \
  --apply-immediately
```

- `--backup-retention-period 14` - Keep 14 days of automated backups
- `--preferred-backup-window "02:00-03:00"` - Run backups at 2 AM UTC
- `--preferred-maintenance-window "sun:03:00-sun:04:00"` - Maintenance on Sunday after backups
- `--apply-immediately` - Apply these settings now (no restart required)

---

## 2. Create a Manual Snapshot

Manual snapshots persist until you delete them. Use them before major changes.

**On your local workstation:**

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-snapshot-identifier devops-lab-baseline-20260609 \
  --tags Key=Purpose,Value=baseline Key=CreatedBy,Value=capstone-build06
```

- `--db-cluster-snapshot-identifier` - A unique name for this snapshot. Use a naming convention like `{cluster}-{purpose}-{date}`.
- `--tags` - Tag with purpose and creator for tracking

Wait for the snapshot to complete:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier devops-lab-baseline-20260609
```

This command blocks until the snapshot reaches `available` status. For a small cluster, this takes 2-5 minutes.

Verify the snapshot:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier devops-lab-baseline-20260609 \
  --query 'DBClusterSnapshots[0].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime,StorageEncrypted,Engine,EngineVersion]' \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------------------
|               DescribeDBClusterSnapshots                        |
+---------------------+-----------+-----------------+------+------+
| devops-lab-baseline  | available | 2026-06-09T12:05| True | 16.6 |
+---------------------+-----------+-----------------+------+------+
```

---

## 3. Cross-Region Snapshot Copy

Copy the snapshot to your DR region for disaster recovery.

**On your local workstation:**

First, check if your KMS key has a replica in the DR region. Since we created a multi-region key in Build 02, create a replica if it does not exist:

```bash
aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.[KeyId,MultiRegion,MultiRegionConfiguration]' \
  --output json
```

If the key has no replica in us-west-2, create one:

```bash
KMS_KEY_ID=$(aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.KeyId' \
  --output text)
```

```bash
aws kms replicate-key \
  --key-id $KMS_KEY_ID \
  --replica-region us-west-2 \
  --description "DR replica of Aurora CMK" \
  --region us-east-1
```

- `--key-id` - The primary key to replicate
- `--replica-region us-west-2` - The destination region

Now copy the snapshot:

```bash
DR_KMS_KEY_ARN=$(aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.Arn' \
  --output text \
  --region us-west-2)
```

```bash
aws rds copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier arn:aws:rds:us-east-1:$(aws sts get-caller-identity --query Account --output text):cluster-snapshot:devops-lab-baseline-20260609 \
  --target-db-cluster-snapshot-identifier devops-lab-baseline-20260609-dr \
  --kms-key-id $DR_KMS_KEY_ARN \
  --source-region us-east-1 \
  --region us-west-2
```

- `--source-db-cluster-snapshot-identifier` - Must be the full ARN when copying cross-region
- `--target-db-cluster-snapshot-identifier` - Name for the copy in the DR region
- `--kms-key-id` - KMS key in the DR region for re-encryption
- `--source-region us-east-1` - Where the source snapshot lives
- `--region us-west-2` - Where to create the copy

Wait for the copy to complete (this can take 5-15 minutes depending on snapshot size):

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier devops-lab-baseline-20260609-dr \
  --region us-west-2
```

Verify the copy exists in the DR region:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier devops-lab-baseline-20260609-dr \
  --query 'DBClusterSnapshots[0].[DBClusterSnapshotIdentifier,Status,StorageEncrypted]' \
  --output table \
  --region us-west-2
```

Expected output (yours will differ):
```
-------------------------------------------------
|       DescribeDBClusterSnapshots              |
+-----------------------------+-----------+-----+
| devops-lab-baseline-20260609-dr | available | True |
+-----------------------------+-----------+-----+
```

---

## 4. Point-in-Time Recovery (PITR) Test

A backup you have never tested is not a backup. Perform a PITR test now.

### 4.1 Insert Test Data

Connect to your cluster and insert identifiable test data.

**On your local workstation (via bastion tunnel or psql):**

```sql
INSERT INTO app.users (email, display_name, password_hash)
VALUES ('pitr-test@example.com', 'PITR Test User', 'hash_placeholder');
```

Record the current time:

```bash
date -u '+%Y-%m-%dT%H:%M:%SZ'
```

Expected output (yours will differ):
```
2026-06-09T12:30:00Z
```

Save this timestamp - you will restore to a point BEFORE or AFTER this insert to verify PITR works.

### 4.2 Restore to a Point in Time

Wait 5 minutes after the insert, then restore to the time AFTER the insert.

**On your local workstation:**

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier devops-lab-cluster \
  --db-cluster-identifier devops-lab-pitr-test \
  --restore-to-time "2026-06-09T12:30:00Z" \
  --db-subnet-group-name devops-lab-db-subnet-group \
  --vpc-security-group-ids sg-YOUR-AURORA-SG-ID \
  --engine aurora-postgresql \
  --tags Key=Purpose,Value=pitr-test Key=DeleteAfter,Value=2026-06-10
```

- `--source-db-cluster-identifier` - The cluster to restore from
- `--restore-to-time` - The timestamp from step 4.1
- `--db-cluster-identifier devops-lab-pitr-test` - Name for the restored cluster
- Replace `sg-YOUR-AURORA-SG-ID` with your Aurora security group ID

Wait for the cluster to become available:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier devops-lab-pitr-test
```

Create an instance in the restored cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-pitr-test-w1 \
  --db-cluster-identifier devops-lab-pitr-test \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql
```

Wait for the instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-pitr-test-w1
```

### 4.3 Verify the Restored Data

Get the endpoint:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-pitr-test \
  --query 'DBClusters[0].Endpoint' \
  --output text
```

Connect and verify the test user exists:

```sql
SELECT email, display_name, created_at
FROM app.users
WHERE email = 'pitr-test@example.com';
```

Expected output (yours will differ):
```
        email         |  display_name  |          created_at
----------------------+----------------+----------------------------
 pitr-test@example.com| PITR Test User | 2026-06-09 12:29:45+00
(1 row)
```

If the row exists, PITR is working correctly. Record the results:
- PITR test date: 2026-06-09
- Restore point: 2026-06-09T12:30:00Z
- Restore time (total): note how many minutes from start to connected
- Data verified: yes

### 4.4 Clean Up the Test Cluster

**On your local workstation:**

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-pitr-test-w1 \
  --skip-final-snapshot
```

Wait for the instance to be deleted:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-pitr-test-w1
```

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-pitr-test \
  --skip-final-snapshot
```

---

## 5. Automate Cross-Region Snapshot Copy

Create a Lambda function that copies the latest automated snapshot to the DR region daily. For this lab, we will use a simpler approach - an EventBridge rule that triggers a Step Functions workflow.

For simplicity, set up a cron-based script that you can run or schedule:

**On your local workstation:**

```bash
vi ~/capstone-aurora/scripts/cross-region-snapshot-copy.sh
```

Add this content:

```bash
#!/usr/bin/env bash
# Copies the latest automated Aurora snapshot to the DR region.
# Usage: bash cross-region-snapshot-copy.sh

set -euo pipefail

SOURCE_CLUSTER="devops-lab-cluster"
SOURCE_REGION="us-east-1"
DR_REGION="us-west-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Finding latest automated snapshot for $SOURCE_CLUSTER..."

LATEST_SNAPSHOT_ARN=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier "$SOURCE_CLUSTER" \
  --snapshot-type automated \
  --query 'DBClusterSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBClusterSnapshotArn' \
  --output text \
  --region "$SOURCE_REGION")

if [[ "$LATEST_SNAPSHOT_ARN" == "None" || -z "$LATEST_SNAPSHOT_ARN" ]]; then
  echo "ERROR: No automated snapshots found."
  exit 1
fi

echo "Latest snapshot: $LATEST_SNAPSHOT_ARN"

TARGET_SNAPSHOT_ID="${SOURCE_CLUSTER}-dr-$(date +%Y%m%d)"

DR_KMS_KEY_ARN=$(aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.Arn' \
  --output text \
  --region "$DR_REGION" 2>/dev/null || echo "")

if [[ -z "$DR_KMS_KEY_ARN" ]]; then
  echo "ERROR: KMS key not found in DR region $DR_REGION."
  exit 1
fi

echo "Copying to $DR_REGION as $TARGET_SNAPSHOT_ID..."

aws rds copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier "$LATEST_SNAPSHOT_ARN" \
  --target-db-cluster-snapshot-identifier "$TARGET_SNAPSHOT_ID" \
  --kms-key-id "$DR_KMS_KEY_ARN" \
  --source-region "$SOURCE_REGION" \
  --region "$DR_REGION" \
  --tags Key=Purpose,Value=dr-copy Key=SourceCluster,Value="$SOURCE_CLUSTER"

echo "Copy initiated. Waiting for completion..."

aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "$TARGET_SNAPSHOT_ID" \
  --region "$DR_REGION"

echo "DONE: Snapshot $TARGET_SNAPSHOT_ID is available in $DR_REGION."

# Clean up old DR snapshots (keep last 7)
echo "Cleaning up old DR snapshots..."

OLD_SNAPSHOTS=$(aws rds describe-db-cluster-snapshots \
  --snapshot-type manual \
  --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier, '${SOURCE_CLUSTER}-dr-')] | sort_by(@, &SnapshotCreateTime) | [:-7].DBClusterSnapshotIdentifier" \
  --output text \
  --region "$DR_REGION")

for SNAP_ID in $OLD_SNAPSHOTS; do
  echo "  Deleting old snapshot: $SNAP_ID"
  aws rds delete-db-cluster-snapshot \
    --db-cluster-snapshot-identifier "$SNAP_ID" \
    --region "$DR_REGION"
done

echo "Cross-region snapshot copy complete."
```

Make it executable:

```bash
chmod +x ~/capstone-aurora/scripts/cross-region-snapshot-copy.sh
```

This script:
1. Finds the latest automated snapshot
2. Copies it to us-west-2 with the DR region KMS key
3. Waits for the copy to complete
4. Cleans up old DR snapshots, keeping the last 7

---

## 6. Verify All Backup Components

Run a final verification.

**On your local workstation:**

```bash
echo "=== Backup Verification ==="

echo ""
echo "1. Automated backups:"
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[BackupRetentionPeriod,EarliestRestorableTime,LatestRestorableTime]' \
  --output table

echo ""
echo "2. Manual snapshots (primary region):"
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type manual \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table

echo ""
echo "3. DR snapshots (us-west-2):"
aws rds describe-db-cluster-snapshots \
  --snapshot-type manual \
  --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier, 'devops-lab')].[DBClusterSnapshotIdentifier,Status]" \
  --output table \
  --region us-west-2

echo ""
echo "4. KMS key in DR region:"
aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.[KeyId,KeyState]' \
  --output table \
  --region us-west-2
```

---

## Summary

Your Aurora cluster now has a complete backup and DR strategy:

- **Automated backups** with 14-day retention, running daily at 2 AM UTC
- **Manual snapshot** taken as a baseline (persists until deleted)
- **Cross-region snapshot copy** to us-west-2 with KMS re-encryption
- **PITR test** verified - you have confirmed restore works and documented the time it takes
- **Automated copy script** for daily cross-region snapshot replication with cleanup
- **DR KMS key** replicated to us-west-2 for snapshot decryption

The RTO for a region failure is 2-4 hours (restore from snapshot + create instances + validate). The RPO is the age of the latest cross-region snapshot (up to 24 hours with daily copies).

**Next:** [Build 07 - Security Hardening](./07-security-hardening.md)
