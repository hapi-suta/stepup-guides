# USE 03 - Backup and Restore

## Objective

Take a manual snapshot, verify it, perform a point-in-time restore, confirm the recovered data, and clean up test resources.

---

## Exercise

You will:
1. Insert test data with known timestamps
2. Take a manual snapshot
3. Insert more data
4. Restore to a specific point in time
5. Verify the restored instance has exactly the expected data
6. Clean up all test resources

---

## Step-by-Step

### 1. Create test data

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
CREATE TABLE backup_exercise (
    id serial PRIMARY KEY,
    phase text NOT NULL,
    value int,
    created_at timestamptz DEFAULT now()
);
```

```sql
INSERT INTO backup_exercise (phase, value) VALUES ('phase1', 100);
```

```sql
INSERT INTO backup_exercise (phase, value) VALUES ('phase1', 200);
```

```sql
INSERT INTO backup_exercise (phase, value) VALUES ('phase1', 300);
```

Record the current time:

```sql
SELECT now() AS snapshot_time;
```

Write this timestamp down. Label it "SNAPSHOT_TIME".

Exit psql:

```sql
\q
```

### 2. Take a manual snapshot

```bash
aws rds create-db-snapshot \
    --db-instance-identifier suta-pg-lab \
    --db-snapshot-identifier backup-exercise-snap
```

Wait for it to complete:

```bash
aws rds wait db-snapshot-available \
    --db-snapshot-identifier backup-exercise-snap
```

### 3. Verify the snapshot

```bash
aws rds describe-db-snapshots \
    --db-snapshot-identifier backup-exercise-snap \
    --query "DBSnapshots[0].{ID:DBSnapshotIdentifier,Status:Status,Time:SnapshotCreateTime,SizeGB:AllocatedStorage,Engine:Engine}" \
    --output table
```

Expected output (yours will differ):

```
-------------------------------------------------------------------
|                     DescribeDBSnapshots                         |
+--------+-----------+----------------------------+-------+-------+
| Engine |    ID     |           Time             | SizeGB| Status|
+--------+-----------+----------------------------+-------+-------+
|postgres| backup-exercise-snap | 2024-01-15T13:00:00Z | 50  | available |
+--------+-----------+----------------------------+-------+-------+
```

### 4. Add more data after the snapshot

Wait 2 minutes (RDS PITR needs a small gap to differentiate timestamps). Then:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
INSERT INTO backup_exercise (phase, value) VALUES ('phase2', 400);
```

```sql
INSERT INTO backup_exercise (phase, value) VALUES ('phase2', 500);
```

Record the time again:

```sql
SELECT now() AS pitr_time;
```

Write this timestamp down. Label it "PITR_TIME".

Now simulate a disaster:

```sql
DROP TABLE backup_exercise;
```

Confirm it is gone:

```sql
SELECT * FROM backup_exercise;
```

Expected output:

```
ERROR:  relation "backup_exercise" does not exist
```

Exit psql:

```sql
\q
```

### 5. Restore to point in time

Use the PITR_TIME from step 4 (the time AFTER phase2 inserts but BEFORE the DROP):

```bash
SG_ID=$(aws ec2 describe-security-groups --group-names suta-rds-sg --query "SecurityGroups[0].GroupId" --output text)
```

```bash
aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier suta-pg-lab \
    --target-db-instance-identifier backup-exercise-pitr \
    --restore-time "2024-01-15T13:10:00Z" \
    --db-instance-class db.t3.medium \
    --vpc-security-group-ids "${SG_ID}" \
    --db-subnet-group-name suta-pg-subnet-group \
    --no-publicly-accessible
```

Replace `2024-01-15T13:10:00Z` with your actual PITR_TIME.

Wait for the restored instance:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier backup-exercise-pitr
```

### 6. Verify restored data

```bash
PITR_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier backup-exercise-pitr --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${PITR_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT * FROM backup_exercise ORDER BY id;
```

Expected output (yours will differ):

```
 id | phase  | value |          created_at
----+--------+-------+-------------------------------
  1 | phase1 |   100 | 2024-01-15 12:55:00.123456+00
  2 | phase1 |   200 | 2024-01-15 12:55:01.234567+00
  3 | phase1 |   300 | 2024-01-15 12:55:02.345678+00
  4 | phase2 |   400 | 2024-01-15 13:05:00.456789+00
  5 | phase2 |   500 | 2024-01-15 13:05:01.567890+00
(5 rows)
```

All 5 rows should be present. The table was not dropped because you restored to a time before the DROP.

Verify the row counts by phase:

```sql
SELECT phase, count(*), sum(value) FROM backup_exercise GROUP BY phase ORDER BY phase;
```

Expected output:

```
 phase  | count | sum
--------+-------+------
 phase1 |     3 |  600
 phase2 |     2 |  900
(2 rows)
```

Exit psql:

```sql
\q
```

### 7. Clean up test resources

Delete the restored instance:

```bash
aws rds delete-db-instance \
    --db-instance-identifier backup-exercise-pitr \
    --skip-final-snapshot \
    --delete-automated-backups
```

Delete the manual snapshot:

```bash
aws rds delete-db-snapshot \
    --db-snapshot-identifier backup-exercise-snap
```

Verify cleanup:

```bash
aws rds describe-db-instances \
    --query "DBInstances[?DBInstanceIdentifier=='backup-exercise-pitr'].DBInstanceStatus" \
    --output text
```

Expected output (after deletion completes):

```
deleting
```

Or no output if already gone.

---

## Key Takeaway

PITR creates a NEW instance - it does not modify the original. The new instance gets a new endpoint. In production, you would need to update your application to point to the new endpoint, or rename the instances to swap them.
