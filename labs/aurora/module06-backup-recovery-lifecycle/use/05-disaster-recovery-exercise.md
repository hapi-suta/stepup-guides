# USE 05 - Disaster Recovery Exercise
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Format:** End-to-end DR scenario combining multiple recovery techniques
**Goal:** Practice a multi-step disaster recovery scenario that requires you to choose the right recovery technique for each situation.

---

## Scenario

You are the on-call DBA for [COMPANY]. It is Saturday morning. You receive three incidents in sequence. Each one requires a different recovery approach. Work through them in order.

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
export CLUSTER_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

---

## Incident 1 - Accidental UPDATE (Data Corruption)

**Alert at 09:15 AM:**
```
@oncall - URGENT: A developer ran an UPDATE without a WHERE clause.
All customer contract values are now set to 0.
The bad UPDATE ran at approximately 09:10 AM UTC.
```

### Step 1.1 - Confirm the Damage

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres
```

First, create and then corrupt the data to simulate the incident:

```sql
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    company_name TEXT NOT NULL,
    contract_value NUMERIC(12,2),
    tier TEXT
);

DELETE FROM customers;

INSERT INTO customers (company_name, contract_value, tier)
SELECT
    'Company ' || i,
    (random() * 100000)::NUMERIC(12,2),
    (ARRAY['bronze','silver','gold','platinum'])[floor(random()*4+1)]
FROM generate_series(1, 100) AS s(i);

-- Record the correct total before corruption
SELECT SUM(contract_value)::NUMERIC(12,2) AS correct_total FROM customers;
```

Write down the `correct_total`. Now simulate the bad UPDATE:

```sql
-- THE BAD UPDATE (simulating the developer's mistake)
UPDATE customers SET contract_value = 0;

-- Confirm the damage
SELECT SUM(contract_value) AS corrupted_total FROM customers;
```

Expected: `0.00`

Exit:

```sql
\q
```

### Step 1.2 - Choose Your Recovery Strategy

<details>
<summary>Click to reveal your options</summary>

**Option A - PITR (Recommended for this scenario)**
PITR can recover to 1 minute before the bad UPDATE. The data was not deleted, just corrupted, so you need the correct values from a point in time before the UPDATE ran.

**Option B - Snapshot restore**
If you have a recent snapshot taken before the UPDATE, you could restore from that. But it may be hours old, missing other legitimate changes.

**Option C - Application-level fix**
If you have audit logs or the original data source, you could reconstruct the correct values. This avoids any database restore but requires knowing the correct values.

For this drill, use **Option A - PITR**.
</details>

### Step 1.3 - Execute the Recovery

Set a target time 5 minutes before the bad UPDATE:

```bash
export RESTORE_TIME="2026-06-09T09:05:00Z"
export PITR_CLUSTER="devops-lab-pitr-fix"
export PITR_INSTANCE="devops-lab-pitr-fix-inst"
```

Replace with a time 5 minutes before you ran the bad UPDATE.

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier $CLUSTER_ID \
  --db-cluster-identifier $PITR_CLUSTER \
  --restore-to-time $RESTORE_TIME \
  --region $AWS_REGION

aws rds create-db-instance \
  --db-instance-identifier $PITR_INSTANCE \
  --db-cluster-identifier $PITR_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION

aws rds wait db-cluster-available \
  --db-cluster-identifier $PITR_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $PITR_INSTANCE \
  --region $AWS_REGION
```

Export the correct data from the restored cluster:

```bash
export PITR_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $PITR_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

pg_dump -h $PITR_HOST -U postgres -d postgres \
  -t customers \
  --data-only \
  --column-inserts \
  -f /tmp/customers_fix.sql
```

Reimport to production:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "TRUNCATE customers;"

psql -h $CLUSTER_HOST -U postgres -d postgres \
  -f /tmp/customers_fix.sql
```

Verify:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT SUM(contract_value)::NUMERIC(12,2) AS restored_total FROM customers;"
```

This should match your `correct_total` from Step 1.1.

### Step 1.4 - Cleanup Incident 1

```bash
aws rds delete-db-instance \
  --db-instance-identifier $PITR_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $PITR_INSTANCE \
  --region $AWS_REGION

aws rds delete-db-cluster \
  --db-cluster-identifier $PITR_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION

rm -f /tmp/customers_fix.sql
```

---

## Incident 2 - Maintenance Window During Peak Hours

**Alert at 10:30 AM:**
```
AWS Email: Pending maintenance for devops-lab-cluster
Scheduled window: Monday 14:00-14:30 UTC
Your maintenance window is set to business hours!
```

### Step 2.1 - Confirm the Problem

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].PreferredMaintenanceWindow'
```

### Step 2.2 - Fix the Maintenance Window

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --preferred-maintenance-window "sun:04:00-sun:04:30" \
  --region $AWS_REGION
```

Verify:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].PreferredMaintenanceWindow'
```

Expected: `"sun:04:00-sun:04:30"`

### Step 2.3 - Check for Pending Actions

```bash
aws rds describe-pending-maintenance-actions \
  --region $AWS_REGION \
  --output json
```

---

## Incident 3 - Verify Backup Readiness

**Alert at 11:00 AM:**
```
@oncall - AUDIT: Compliance team needs proof that we can recover
to any point in the last 14 days and that we have a cross-region
backup. Provide evidence by end of day.
```

### Step 3.1 - Prove PITR Coverage

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{BackupRetention:BackupRetentionPeriod,LatestRestorableTime:LatestRestorableTime,EarliestRestorableTime:EarliestRestorableTime}'
```

### Step 3.2 - Prove Snapshot Exists

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier $CLUSTER_ID \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[*].{ID:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
  --output table
```

### Step 3.3 - Write the Compliance Evidence

```
BACKUP COMPLIANCE EVIDENCE
============================
Date: [DATE]
Cluster: devops-lab-cluster
Prepared by: [YOUR NAME]

1. PITR COVERAGE
   Retention period: [X] days
   Earliest restorable time: [TIMESTAMP]
   Latest restorable time: [TIMESTAMP]
   PITR window: [X] days covered

2. MANUAL SNAPSHOTS
   Total manual snapshots: [COUNT]
   Most recent: [SNAPSHOT_ID] created [TIMESTAMP]
   Oldest: [SNAPSHOT_ID] created [TIMESTAMP]

3. CROSS-REGION COPIES
   Destination region: [REGION]
   Most recent copy: [SNAPSHOT_ID] created [TIMESTAMP]

4. BACKUP VERIFICATION
   Last restore test date: [DATE]
   Restore test result: PASS / FAIL

SIGNED: [YOUR NAME], [DATE]
```

---

## Post-Drill Summary

Record your results:

```
DISASTER RECOVERY DRILL RESULTS
==================================
Date: [DATE]

Incident 1 - Data Corruption Recovery
  Recovery method: PITR
  Time to recover: [X] minutes
  Data verified: YES / NO

Incident 2 - Maintenance Window Fix
  Window corrected: YES / NO
  New window: [WINDOW]

Incident 3 - Compliance Evidence
  PITR coverage confirmed: YES / NO
  Snapshots verified: YES / NO
  Cross-region verified: YES / NO

Overall readiness: READY / NEEDS IMPROVEMENT
Areas for improvement: [LIST]
```

---

## Key Takeaways

- Different incidents require different recovery tools - know when to use PITR vs snapshot vs manual fix
- Data corruption (bad UPDATE) is recoverable via PITR without deleting the cluster
- Maintenance window fixes are non-disruptive - changing the schedule does not cause a restart
- Compliance audits require documented evidence - prepare templates in advance
- Regular DR drills reveal gaps before real incidents do
