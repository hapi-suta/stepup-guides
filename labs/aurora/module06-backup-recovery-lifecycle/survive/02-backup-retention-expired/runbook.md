# SURVIVE 02 - Backup Retention Expired / PITR Insufficient
## Runbook: Recovery from Manual Snapshot

**Scenario:** The billing_records table has been truncated. The backup retention window is too short to reach the needed recovery point via PITR. Only a manual snapshot exists.

**What the student sees:**
```
ALERT: billing_records table is empty
SELECT COUNT(*) FROM billing_records; --> 0
Backup retention is 1 day.
The data loss happened before the PITR window can reach.
```

---

## Your Objective

Restore the `billing_records` data within **30 minutes** using the manual snapshot as your recovery tool.

---

## Step 1 - Confirm the Disaster

Confirm the PITR window is insufficient:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{BackupRetention:BackupRetentionPeriod,LatestRestorableTime:LatestRestorableTime,EarliestRestorableTime:EarliestRestorableTime}'
```

The `EarliestRestorableTime` does not reach far enough back to recover the original data.

Confirm the table is empty:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM billing_records;"
```

Expected: `0`

---

## Step 2 - Find the Manual Snapshot

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier $CLUSTER_ID \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[*].{ID:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
  --output table
```

Record the snapshot ID:

```bash
export SNAPSHOT_ID="devops-lab-survive02-last-good-XXXXXXXXXX"
```

---

## Step 3 - Restore from the Snapshot

```bash
export RESTORED_CLUSTER="devops-lab-survive02-restore"
export RESTORED_INSTANCE="devops-lab-survive02-inst"

aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --snapshot-identifier $SNAPSHOT_ID \
  --engine aurora-postgresql \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION
```

Add an instance to the restored cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION
```

Wait for both:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

---

## Step 4 - Get the Restored Cluster Endpoint

```bash
export RESTORED_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

---

## Step 5 - Verify Billing Records Exist on the Restored Cluster

```bash
psql -h $RESTORED_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) AS row_count, SUM(amount)::NUMERIC(12,2) AS total FROM billing_records;"
```

Expected: 500 rows with a non-zero sum.

---

## Step 6 - Export the Table Data

```bash
pg_dump -h $RESTORED_HOST -U postgres -d postgres \
  -t billing_records \
  --data-only \
  --column-inserts \
  -f /tmp/billing_records_recovery.sql
```

---

## Step 7 - Reimport to Production

The table exists on production but is empty. Import the data:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -f /tmp/billing_records_recovery.sql
```

---

## Step 8 - Verify Production Recovery

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres << 'EOF'
SELECT COUNT(*) AS row_count FROM billing_records;
SELECT SUM(amount)::NUMERIC(12,2) AS total_amount FROM billing_records;
SELECT paid, COUNT(*) FROM billing_records GROUP BY paid;
EOF
```

---

## Step 9 - Fix the Root Cause: Increase Retention

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --backup-retention-period 14 \
  --apply-immediately \
  --region $AWS_REGION
```

Verify:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].BackupRetentionPeriod'
```

Expected: `14`

---

## Step 10 - Cleanup

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION

aws rds delete-db-cluster \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION

rm -f /tmp/billing_records_recovery.sql
```

---

## Run Validate Script

```bash
bash validate.sh
```

---

## Key Lessons

1. When PITR cannot reach far enough back, manual snapshots are your only lifeline
2. Snapshot restores recover to the moment the snapshot was taken - data written after is lost
3. Always have recent manual snapshots before reducing retention or making risky changes
4. The fix is not just restoring data - also fix the backup configuration that caused the gap
5. Aurora does not allow retention = 0, but 1 day is still dangerously short for production
6. Schedule regular manual snapshots (weekly minimum) as insurance beyond the PITR window
