# BUILD 02 - Point-In-Time Recovery (PITR)
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Goal:** Check your recovery window, simulate data loss, recover to a specific timestamp via PITR, verify the restored data, and understand what PITR creates.

**Key Rule:** PITR always creates a NEW instance. It never modifies your existing database in place.

**Prerequisites:**
- BUILD 01 complete (backup retention set to at least 7 days)
- An RDS PostgreSQL instance with automated backups enabled
- `psql` installed on your machine

---

## Step 1 - Set Your Variables

```bash
export DB_INSTANCE="suta-t5-primary-hfa"
export RESTORED_INSTANCE="suta-t5-restored-hfa"
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="your-subnet-group-name"
export VPC_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

Replace the subnet group and security group with values from your environment. You can find these on your existing instance's detail page under **Connectivity and security**.

---

## Step 2 - Check the Latest Restorable Time

The "latest restorable time" is the most recent second you can recover to. It lags a few minutes behind real-time because WAL must finish uploading to S3 before it is usable.

### Console

1. Open **RDS > Databases**.
2. Click your instance name.
3. Click the **Maintenance and backups** tab.
4. Look for **Latest restore time** under the Backup section.

### CLI

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].LatestRestorableTime'
```

Expected output (yours will differ):

```
"2025-05-30T14:37:11.000Z"
```

Note this timestamp. Your PITR target must be at or before this time.

---

## Step 3 - Create Test Data (Simulate Normal Operations)

Connect to your database and create a table with test data.

First, get your database endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

Expected output (yours will differ):

```
suta-t5-primary-hfa.c9akkzmtpvxl.us-east-1.rds.amazonaws.com
```

Store the endpoint:

```bash
export DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
```

Connect with psql:

```bash
psql -h $DB_HOST -U postgres -d postgres
```

You will be prompted for the password. Enter it.

Inside psql, create a test table and insert rows:

```sql
CREATE TABLE important_orders (
    id SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO important_orders (customer_name, amount) VALUES
    ('Alice Corp', 15000.00),
    ('Bob LLC', 8500.50),
    ('Carol Inc', 22000.00);

SELECT * FROM important_orders;
```

Expected output:

```
 id | customer_name | amount   |          created_at
----+---------------+----------+-------------------------------
  1 | Alice Corp    | 15000.00 | 2025-05-30 14:40:12.123456+00
  2 | Bob LLC       |  8500.50 | 2025-05-30 14:40:12.123456+00
  3 | Carol Inc     | 22000.00 | 2025-05-30 14:40:12.123456+00
```

Record the current time. This is your "good state" timestamp. You will recover to just before the deletion below.

```sql
SELECT now();
```

Expected output (yours will differ):

```
              now
-------------------------------
 2025-05-30 14:40:15.000000+00
```

Write down this time: `2025-05-30 14:40:15 UTC`

Exit psql:

```sql
\q
```

---

## Step 4 - Simulate Accidental Data Loss

Wait 2-3 minutes after recording your good-state timestamp. Then simulate someone accidentally dropping the table.

Reconnect:

```bash
psql -h $DB_HOST -U postgres -d postgres
```

Drop the table:

```sql
DROP TABLE important_orders;

SELECT * FROM important_orders;
```

Expected output:

```
ERROR:  relation "important_orders" does not exist
```

Exit:

```sql
\q
```

Note the time of the drop:

```bash
date -u
```

Expected output (yours will differ):

```
Fri May 30 14:43:22 UTC 2025
```

Your goal: recover to `2025-05-30 14:40:15 UTC` - right after the insert, right before the drop.

---

## Step 5 - Perform PITR

You will restore to a timestamp 1 minute before the table was dropped. Use the "good state" time you recorded in Step 3.

Set your target restore time (use the timestamp you recorded, in this format):

```bash
export RESTORE_TIME="2025-05-30T14:40:15Z"
```

Replace with your actual recorded timestamp.

### Console

1. Go to **RDS > Automated backups**.
2. Select your instance.
3. Click **Actions > Restore to point in time**.
4. Under **Restore time**, select **Custom date and time**.
5. Enter your target date and time (UTC).
6. Under **DB instance identifier**, enter: `suta-t5-restored-hfa`.
7. Set **DB instance class** to the same as your source (db.t3.micro).
8. Set **VPC**, **Subnet group**, and **VPC security groups** to match your source.
9. Under **Additional configuration**, set the same parameter group if you used a custom one.
10. Click **Restore to point in time**.

### CLI

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier $DB_INSTANCE \
  --target-db-instance-identifier $RESTORED_INSTANCE \
  --restore-time $RESTORE_TIME \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION \
  --no-publicly-accessible
```

`--source-db-instance-identifier` is the original instance to recover from.
`--target-db-instance-identifier` is the name of the NEW instance that will be created.
`--restore-time` is the exact UTC timestamp to recover to (ISO 8601 format).
`--no-publicly-accessible` keeps the new instance private (recommended).

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "suta-t5-restored-hfa",
        "DBInstanceStatus": "creating",
        "DBInstanceClass": "db.t3.micro",
        "RestoreTime": "2025-05-30T14:40:15.000Z"
    }
}
```

> **Concept:** At this point, AWS is taking the last full snapshot before your target time and replaying WAL records up to exactly your target timestamp. This can take 10-30 minutes depending on instance size and how much WAL needs to be replayed.

---

## Step 6 - Wait for the Restored Instance

Monitor the restore progress:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
  --output table
```

Run this every 2-3 minutes. Status progression:

```
creating -> backing-up -> modifying -> available
```

Or use the wait command (blocks until available, polls every 30 seconds):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

This may take up to 20 minutes. When it returns, the instance is ready.

---

## Step 7 - Get the Restored Instance Endpoint

```bash
export RESTORED_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo $RESTORED_HOST
```

Expected output (yours will differ):

```
suta-t5-restored-hfa.c9akkzmtpvxl.us-east-1.rds.amazonaws.com
```

---

## Step 8 - Connect and Verify the Data Is Recovered

Connect to the restored instance:

```bash
psql -h $RESTORED_HOST -U postgres -d postgres
```

Verify the table exists and the data is there:

```sql
SELECT * FROM important_orders;
```

Expected output:

```
 id | customer_name | amount   |          created_at
----+---------------+----------+-------------------------------
  1 | Alice Corp    | 15000.00 | 2025-05-30 14:40:12.123456+00
  2 | Bob LLC       |  8500.50 | 2025-05-30 14:40:12.123456+00
  3 | Carol Inc     | 22000.00 | 2025-05-30 14:40:12.123456+00
(3 rows)
```

The table is back. The drop never happened in this restored instance.

Confirm the drop happened on the original and not the restored:

```sql
-- On the restored instance - table exists:
\dt important_orders
```

Expected output:

```
            List of relations
 Schema |      Name       | Type  |  Owner
--------+-----------------+-------+----------
 public | important_orders | table | postgres
```

Exit:

```sql
\q
```

---

## Step 9 - Understand What You Have Now

You now have TWO instances:

```
Original: suta-t5-primary-hfa
  - Still running
  - Does NOT have the important_orders table
  - Your application is pointing here

Restored: suta-t5-restored-hfa
  - New instance, created by PITR
  - HAS the important_orders table with 3 rows
  - Nothing is pointing to it yet
```

In a real recovery scenario, your next steps would be:
1. Verify the restored data is complete and correct
2. Export the recovered data with `pg_dump` and import it to the original (if you want to fix just one table)
3. OR update your application's connection string to point to the restored instance (if you want a full cutover)
4. Decommission the old instance once the cutover is confirmed

For this lab, use option 2. Export and reimport just the table:

```bash
pg_dump -h $RESTORED_HOST -U postgres -d postgres \
  -t important_orders \
  --data-only \
  -f /tmp/important_orders_recovery.sql
```

`-t important_orders` dumps only that one table.
`--data-only` skips the CREATE TABLE statement (the table already existed, it was just dropped).
`-f` writes to a file.

Reimport to the original:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "CREATE TABLE important_orders (id SERIAL PRIMARY KEY, customer_name TEXT NOT NULL, amount NUMERIC(10,2) NOT NULL, created_at TIMESTAMPTZ DEFAULT now());"

psql -h $DB_HOST -U postgres -d postgres \
  -f /tmp/important_orders_recovery.sql
```

Verify on the original:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT * FROM important_orders;"
```

Expected output:

```
 id | customer_name | amount   |          created_at
----+---------------+----------+-------------------------------
  1 | Alice Corp    | 15000.00 | 2025-05-30 14:40:12.123456+00
  2 | Bob LLC       |  8500.50 | 2025-05-30 14:40:12.123456+00
  3 | Carol Inc     | 22000.00 | 2025-05-30 14:40:12.123456+00
```

---

## Step 10 - Cleanup

Delete the restored instance when you are done:

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION
```

`--skip-final-snapshot` skips taking a snapshot before deletion (this is a lab instance, so that is acceptable).

---

## Summary

You can now:
- Check the latest restorable time before attempting a recovery
- Perform PITR to any second within the retention window
- Connect to the restored instance and verify the recovered data
- Recover a single table by exporting from restored and importing to original
- Explain that PITR creates a NEW instance and never modifies the source

**Key concept to remember:** The restored instance is a full copy of your database as it existed at the target time. Your original instance is untouched during the PITR process.

**Next:** BUILD 03 - Aurora Fast Cloning
