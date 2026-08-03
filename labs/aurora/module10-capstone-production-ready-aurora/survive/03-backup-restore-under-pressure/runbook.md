# SURVIVE Scenario 03: Backup Restore Under Pressure - Runbook

## Scenario

A critical table has been dropped. You need to restore it using point-in-time recovery. The business is waiting.

---

## Step 1: Confirm the Data Loss

**On your local workstation:**

```bash
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c \
  "SELECT count(*) FROM app.critical_data;"
```

Expected: ERROR - relation does not exist.

---

## Step 2: Check the Latest Restorable Time

**On your local workstation:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].[EarliestRestorableTime,LatestRestorableTime]' \
  --output table \
  --region us-east-1
```

The safe restore time from inject.sh must be between Earliest and Latest.

---

## Step 3: Perform Point-in-Time Restore

Replace `SAFE_RESTORE_TIME` with the timestamp from inject.sh output.

**On your local workstation:**

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier devops-lab-cluster \
  --db-cluster-identifier devops-lab-pitr-recovery \
  --restore-to-time "SAFE_RESTORE_TIME" \
  --db-subnet-group-name devops-lab-db-subnet-group \
  --vpc-security-group-ids $(aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text) \
  --engine aurora-postgresql \
  --region us-east-1
```

---

## Step 4: Wait for the Restored Cluster

**On your local workstation:**

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier devops-lab-pitr-recovery \
  --region us-east-1
```

---

## Step 5: Create an Instance in the Restored Cluster

**On your local workstation:**

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-pitr-recovery-w1 \
  --db-cluster-identifier devops-lab-pitr-recovery \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --region us-east-1
```

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-pitr-recovery-w1 \
  --region us-east-1
```

---

## Step 6: Verify the Data Exists

Get the restored cluster endpoint:

```bash
RESTORED_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-pitr-recovery \
  --query 'DBClusters[0].Endpoint' --output text --region us-east-1)
```

```bash
PGPASSWORD="$DB_PASSWORD" psql -h "$RESTORED_HOST" -U "$DB_USER" -d postgres -c \
  "SELECT count(*) FROM app.critical_data;"
```

Expected: 1000 rows.

---

## Step 7: Clean Up

After verifying the data, delete the restored cluster:

**On your local workstation:**

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-pitr-recovery-w1 \
  --skip-final-snapshot \
  --region us-east-1
```

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-pitr-recovery-w1 \
  --region us-east-1
```

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-pitr-recovery \
  --skip-final-snapshot \
  --region us-east-1
```
