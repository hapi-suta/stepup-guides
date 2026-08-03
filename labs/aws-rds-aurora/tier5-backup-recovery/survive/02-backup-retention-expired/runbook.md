# SURVIVE 02 - Backup Retention Expired / No PITR Available
## Runbook: Recovery from Manual Snapshot

**Scenario:** The billing_records table has been truncated. Automated backups are disabled. PITR is not available. Only a manual snapshot exists.

**What the student sees:**
```
ALERT: billing_records table is empty
SELECT COUNT(*) FROM billing_records; --> 0
aws rds describe-db-instances shows: BackupRetentionPeriod: 0
LatestRestorableTime: null
```

---

## Your Objective

Restore the `billing_records` data within **30 minutes** using the only available recovery tool: a manual snapshot.

---

## Step 1 - Confirm the Disaster

Confirm PITR is not available:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{BackupRetention:BackupRetentionPeriod,LatestRestorableTime:LatestRestorableTime}'
```

Expected output:

```json
{
    "BackupRetention": 0,
    "LatestRestorableTime": null
}
```

`BackupRetentionPeriod: 0` means backups are disabled. `LatestRestorableTime: null` confirms PITR is not available.

Confirm the table is empty:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM billing_records;"
```

Expected: `0`

---

## Step 2 - Find the Manual Snapshot

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
  --output table
```

Expected output (yours will differ):

```
---------------------------------------------------------------------------
|                          DescribeDBSnapshots                            |
+-------------------------------+-----------------------------+-----------+
|  Created                      |  ID                         |  Status   |
+-------------------------------+-----------------------------+-----------+
|  2025-05-30T15:22:11.000Z     |  suta-t5-survive02-last-... |  available|
+-------------------------------+-----------------------------+-----------+
```

Record the snapshot ID.

```bash
export SNAPSHOT_ID="suta-t5-survive02-last-good-XXXXXXXXXX"
```

---

## Step 3 - Restore from the Snapshot

This creates a new RDS instance from the snapshot:

```bash
export RESTORED_INSTANCE="suta-t5-survive02-restore"

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $RESTORED_INSTANCE \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Wait for the restored instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

---

## Step 4 - Get the Restored Instance Endpoint

```bash
export RESTORED_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
```

---

## Step 5 - Verify the Billing Records Exist on the Restored Instance

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

## Step 7 - Clear and Reimport to Production

The table exists on production but is empty. Import the data:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -f /tmp/billing_records_recovery.sql
```

---

## Step 8 - Verify Production Recovery

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
SELECT COUNT(*) AS row_count FROM billing_records;
SELECT SUM(amount)::NUMERIC(12,2) AS total_amount FROM billing_records;
SELECT paid, COUNT(*) FROM billing_records GROUP BY paid;
EOF
```

---

## Step 9 - Re-enable Automated Backups

This is critical. Fix the root cause.

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --backup-retention-period 14 \
  --apply-immediately \
  --region $AWS_REGION
```

Verify backups are re-enabled:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].BackupRetentionPeriod'
```

Expected: `14`

---

## Step 10 - Cleanup

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
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

1. When backup retention = 0, PITR is completely unavailable
2. Manual snapshots are your only lifeline when automated backups are disabled
3. Snapshot restores recover to the moment the snapshot was taken - all data written after the snapshot is permanently lost
4. Always have at least one recent manual snapshot before disabling automated backups for any reason
5. The fix is not just restoring the data - it is also fixing the backup configuration that caused the vulnerability
6. Data lost between the snapshot and the truncation cannot be recovered by any AWS tool
