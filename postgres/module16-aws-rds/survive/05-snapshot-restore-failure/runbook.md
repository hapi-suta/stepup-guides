# SURVIVE 05 - Snapshot Restore Failure

## Symptom

Data in the `critical_orders` table has been corrupted. Amounts are zeroed out, rows are missing, and statuses show "CORRUPTED". You need to restore from a good snapshot.

---

## Diagnosis

### Step 1 - Assess the damage

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT * FROM critical_orders ORDER BY id;
```

You should see corrupted data - amounts are 0 and statuses say "CORRUPTED". Some rows may be missing.

Exit psql:

```sql
\q
```

### Step 2 - List available snapshots

```bash
aws rds describe-db-snapshots \
    --db-instance-identifier suta-pg-lab \
    --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Time:SnapshotCreateTime,Type:SnapshotType}" \
    --output table
```

You will see multiple snapshots. The one taken BEFORE the corruption is the good one. Check the timestamps carefully.

### Step 3 - Identify the correct snapshot

Look at the snapshot names and timestamps. The snapshot taken earlier (before the corruption) contains the good data. The one taken later contains the corrupted data.

Check a snapshot's details:

```bash
aws rds describe-db-snapshots \
    --db-snapshot-identifier suta-good-snap-20240115 \
    --query "DBSnapshots[0].{ID:DBSnapshotIdentifier,Time:SnapshotCreateTime,Status:Status,SizeGB:AllocatedStorage}" \
    --output table
```

Replace the snapshot identifier with the actual name from Step 2.

---

## Fix

### Step 4 - Restore from the good snapshot

```bash
SG_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text)
```

```bash
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier suta-pg-lab-restored \
    --db-snapshot-identifier suta-good-snap-20240115 \
    --db-instance-class db.t3.medium \
    --vpc-security-group-ids "${SG_ID}" \
    --db-subnet-group-name suta-pg-subnet-group \
    --no-publicly-accessible
```

Replace the snapshot identifier with the good snapshot from Step 3.

### Step 5 - Wait for the restored instance

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab-restored
```

This typically takes 10-20 minutes.

### Step 6 - Verify the restored data

```bash
RESTORED_EP=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab-restored --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RESTORED_EP}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT * FROM critical_orders ORDER BY id;
```

Expected output (the uncorrupted data):

```
 id |   customer   |  amount  | status |          created_at
----+--------------+----------+--------+-------------------------------
  1 | Acme Corp    | 15000.00 | active | 2024-01-15 14:30:00.123+00
  2 | Beta Inc     | 22500.00 | active | 2024-01-15 14:30:00.234+00
  3 | Gamma LLC    |  8750.00 | active | 2024-01-15 14:30:00.345+00
  4 | Delta Co     | 31200.00 | active | 2024-01-15 14:30:00.456+00
  5 | Epsilon Ltd  | 12800.00 | active | 2024-01-15 14:30:00.567+00
(5 rows)
```

All 5 rows should be present with correct amounts and "active" status.

Verify the totals:

```sql
SELECT count(*) AS row_count, sum(amount) AS total_amount FROM critical_orders;
```

Expected output:

```
 row_count | total_amount
-----------+--------------
         5 |     90250.00
(1 row)
```

Exit psql:

```sql
\q
```

### Step 7 - Plan the swap (production pattern)

In production, you would:
1. Rename the corrupted instance: `suta-pg-lab` to `suta-pg-lab-corrupted`
2. Rename the restored instance: `suta-pg-lab-restored` to `suta-pg-lab`
3. Update application connection strings if not using DNS/CNAME

RDS does not support renaming the endpoint directly, but you can rename the instance identifier:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab-restored \
    --new-db-instance-identifier suta-pg-lab-clean \
    --apply-immediately
```

---

## Clean Up

Delete the restored instance:

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-pg-lab-restored \
    --skip-final-snapshot \
    --delete-automated-backups
```

Delete the test snapshots:

```bash
aws rds delete-db-snapshot \
    --db-snapshot-identifier suta-corrupted-snap-20240115
```

Restore the original data on the live instance:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
DROP TABLE IF EXISTS critical_orders;
```

```sql
\q
```

---

## Discussion Questions

1. How do you identify which snapshot contains the "good" data?
2. Why does restoring always create a new instance instead of overwriting?
3. What is the impact of the new endpoint on application connections?
4. How would you automate snapshot validation (checking data integrity)?
