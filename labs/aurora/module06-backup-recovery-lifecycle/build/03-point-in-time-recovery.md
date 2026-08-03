# BUILD 03 - Point-In-Time Recovery (PITR)
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Goal:** Check your recovery window, simulate data loss, recover to a specific timestamp via PITR, verify the restored data, and understand what PITR creates.

**Key Rule:** PITR always creates a NEW Aurora cluster. It never modifies your existing cluster in place.

**Prerequisites:**
- BUILD 01 complete (backup retention set to at least 7 days)
- An Aurora PostgreSQL cluster with automated backups enabled
- `psql` installed on your machine

---

## Step 1 - Set Your Variables

```bash
export CLUSTER_ID="devops-lab-cluster"
export RESTORED_CLUSTER="devops-lab-restored"
export RESTORED_INSTANCE="devops-lab-restored-inst"
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="your-subnet-group-name"
export VPC_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

Replace the subnet group and security group with values from your environment. You can find these on your existing cluster's detail page under **Connectivity and security**.

---

## Step 2 - Check the Latest Restorable Time

The "latest restorable time" is the most recent second you can recover to. It lags a few minutes behind real-time because backup data must finish uploading to S3.

### Console

1. Open **RDS > Databases**.
2. Click your cluster name.
3. Click the **Maintenance and backups** tab.
4. Look for **Latest restore time** under the Backup section.

### CLI

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].LatestRestorableTime'
```

Expected output (yours will differ):

```
"2026-06-09T14:37:11.000Z"
```

Note this timestamp. Your PITR target must be at or before this time.

---

## Step 3 - Create Test Data (Simulate Normal Operations)

Get your cluster writer endpoint:

```bash
export CLUSTER_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo $CLUSTER_HOST
```

Expected output (yours will differ):

```
devops-lab-cluster.cluster-c9akkzmtpvxl.us-east-1.rds.amazonaws.com
```

Connect with psql:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres
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
    ('Alpha Corp', 15000.00),
    ('Beta LLC', 8500.50),
    ('Gamma Inc', 22000.00),
    ('Delta Ltd', 5200.75),
    ('Epsilon Co', 31000.00);

SELECT * FROM important_orders;
```

Expected output:

```
 id | customer_name | amount   |          created_at
----+---------------+----------+-------------------------------
  1 | Alpha Corp    | 15000.00 | 2026-06-09 14:40:12.123456+00
  2 | Beta LLC      |  8500.50 | 2026-06-09 14:40:12.123456+00
  3 | Gamma Inc     | 22000.00 | 2026-06-09 14:40:12.123456+00
  4 | Delta Ltd     |  5200.75 | 2026-06-09 14:40:12.123456+00
  5 | Epsilon Co    | 31000.00 | 2026-06-09 14:40:12.123456+00
```

Record the current time. This is your "good state" timestamp.

```sql
SELECT now();
```

Expected output (yours will differ):

```
              now
-------------------------------
 2026-06-09 14:40:15.000000+00
```

Write down this time: `2026-06-09 14:40:15 UTC`

Exit psql:

```sql
\q
```

---

## Step 4 - Simulate Accidental Data Loss

Wait 2-3 minutes after recording your good-state timestamp. Then simulate someone accidentally dropping the table.

Reconnect:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres
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
Mon Jun  9 14:43:22 UTC 2026
```

Your goal: recover to `2026-06-09 14:40:15 UTC` - right after the insert, right before the drop.

---

## Step 5 - Perform PITR

Set your target restore time (use the timestamp you recorded, in ISO 8601 format):

```bash
export RESTORE_TIME="2026-06-09T14:40:15Z"
```

Replace with your actual recorded timestamp.

### Console

1. Go to **RDS > Databases**.
2. Click your cluster name.
3. Click **Actions > Restore to point in time**.
4. Under **Restore time**, select **Custom date and time**.
5. Enter your target date and time (UTC).
6. Under **DB cluster identifier**, enter: `devops-lab-restored`.
7. Set **DB instance class** to the same as your source.
8. Set **VPC**, **Subnet group**, and **VPC security groups** to match your source.
9. Click **Restore to point in time**.

### CLI

```bash
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier $CLUSTER_ID \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --restore-to-time $RESTORE_TIME \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION
```

`--source-db-cluster-identifier` is the original cluster to recover from.
`--db-cluster-identifier` is the name of the NEW cluster that will be created.
`--restore-to-time` is the exact UTC timestamp to recover to (ISO 8601 format).

Expected output (yours will differ):

```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-restored",
        "Status": "creating",
        "Engine": "aurora-postgresql"
    }
}
```

Now add a DB instance to the restored cluster (a cluster without instances cannot be connected to):

```bash
aws rds create-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION
```

`--db-cluster-identifier` associates this instance with the restored cluster.
`--engine aurora-postgresql` must match the cluster engine exactly.

---

## Step 6 - Wait for the Restored Cluster

Wait for the cluster to become available:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $AWS_REGION
```

Wait for the instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

This may take 10-20 minutes. When both return, the cluster is ready.

---

## Step 7 - Get the Restored Cluster Endpoint

```bash
export RESTORED_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo $RESTORED_HOST
```

Expected output (yours will differ):

```
devops-lab-restored.cluster-c9akkzmtpvxl.us-east-1.rds.amazonaws.com
```

---

## Step 8 - Connect and Verify the Data Is Recovered

Connect to the restored cluster:

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
  1 | Alpha Corp    | 15000.00 | 2026-06-09 14:40:12.123456+00
  2 | Beta LLC      |  8500.50 | 2026-06-09 14:40:12.123456+00
  3 | Gamma Inc     | 22000.00 | 2026-06-09 14:40:12.123456+00
  4 | Delta Ltd     |  5200.75 | 2026-06-09 14:40:12.123456+00
  5 | Epsilon Co    | 31000.00 | 2026-06-09 14:40:12.123456+00
(5 rows)
```

The table is back. The drop never happened in this restored cluster.

Confirm the table exists:

```sql
\dt important_orders
```

Expected output:

```
            List of relations
 Schema |       Name        | Type  |  Owner
--------+-------------------+-------+----------
 public | important_orders  | table | postgres
```

Exit:

```sql
\q
```

---

## Step 9 - Understand What You Have Now

You now have TWO clusters:

```
Original: devops-lab-cluster
  - Still running
  - Does NOT have the important_orders table
  - Your application is pointing here

Restored: devops-lab-restored
  - New cluster, created by PITR
  - HAS the important_orders table with 5 rows
  - Nothing is pointing to it yet
```

For this lab, recover just the table by exporting from restored and importing to original:

```bash
pg_dump -h $RESTORED_HOST -U postgres -d postgres \
  -t important_orders \
  -f /tmp/important_orders_recovery.sql
```

`-t important_orders` dumps only that one table (schema + data).
`-f` writes to a file.

Import to the original cluster:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -f /tmp/important_orders_recovery.sql
```

Verify on the original:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT * FROM important_orders;"
```

Expected output:

```
 id | customer_name | amount   |          created_at
----+---------------+----------+-------------------------------
  1 | Alpha Corp    | 15000.00 | 2026-06-09 14:40:12.123456+00
  2 | Beta LLC      |  8500.50 | 2026-06-09 14:40:12.123456+00
  3 | Gamma Inc     | 22000.00 | 2026-06-09 14:40:12.123456+00
  4 | Delta Ltd     |  5200.75 | 2026-06-09 14:40:12.123456+00
  5 | Epsilon Co    | 31000.00 | 2026-06-09 14:40:12.123456+00
```

---

## Step 10 - Cleanup

Delete the restored instance first (must delete instances before cluster):

```bash
aws rds delete-db-instance \
  --db-instance-identifier $RESTORED_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION
```

`--skip-final-snapshot` skips taking a snapshot before deletion (this is a lab cluster).

Wait for instance deletion:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier $RESTORED_INSTANCE \
  --region $AWS_REGION
```

Then delete the restored cluster:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier $RESTORED_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION
```

Remove the dump file:

```bash
rm -f /tmp/important_orders_recovery.sql
```

---

## Summary

You can now:
- Check the latest restorable time before attempting a recovery
- Perform PITR to any second within the retention window
- Create an instance in the restored cluster and connect to it
- Verify the recovered data matches what you expected
- Recover a single table by exporting from restored and importing to original
- Explain that PITR creates a NEW cluster and never modifies the source

**Key concept to remember:** The restored cluster is a complete copy of your database as it existed at the target time. Your original cluster is untouched during the PITR process.

**Next:** BUILD 04 - Cross-Region Backup
