# BUILD 02 - RDS Read Replicas: Create, Monitor, Promote
## Estimated Time: 45 minutes

---

## What You Will Do

1. Create a read replica from an existing RDS instance
2. Connect to the replica and verify it is read-only
3. Measure replica lag
4. Create a cross-region read replica
5. Promote a replica to a standalone database

---

## Before You Start

You need:
- An existing RDS PostgreSQL instance in "available" status
- The instance must NOT use encrypted storage, OR have a KMS key available if encrypted
- AWS CLI v2 configured: `aws configure`
- psql installed on your EC2 instance or Cloud Shell

> **Note:** You cannot create a read replica from an instance with Multi-AZ disabled AND no automated backups. Enable automated backups first if needed:
>
> ```bash
> aws rds modify-db-instance \
>   --db-instance-identifier my-postgres \
>   --backup-retention-period 1 \
>   --apply-immediately \
>   --region us-east-1
> ```
>
> `--backup-retention-period 1` - keeps 1 day of automated backups. This is the minimum needed to create replicas.

---

## Step 1 - Create a Read Replica

### Console

1. Go to RDS -> Databases
2. Click your primary instance name
3. Click "Actions" -> "Create read replica"
4. Fill in the form:
   - DB instance identifier: `my-postgres-replica-1`
   - DB instance class: same as primary (db.t3.micro for this lab)
   - Destination Region: same region (us-east-1)
   - Multi-AZ deployment: No (for this lab)
   - Leave everything else as default
5. Click "Create read replica"

### CLI

```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier my-postgres-replica-1 \
  --source-db-instance-identifier my-postgres \
  --db-instance-class db.t3.micro \
  --availability-zone us-east-1b \
  --region us-east-1
```

`--db-instance-identifier` - the name for your new replica.
`--source-db-instance-identifier` - the name of the primary instance to replicate from.
`--availability-zone` - put the replica in a different AZ than the primary for better resilience.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-replica-1",
        "DBInstanceStatus": "creating",
        "ReadReplicaSourceDBInstanceIdentifier": "my-postgres",
        "MultiAZ": false,
        ...
    }
}
```

Creating a replica takes 5-20 minutes. AWS takes a snapshot of the primary and restores it to the replica, then starts streaming replication.

---

## Step 2 - Wait for the Replica to Become Available

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres-replica-1 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
  --output table \
  --region us-east-1
```

Run this every 2 minutes until Status shows "available."

Expected output (yours will differ):
```
-------------------------------------------------------------------
|                      DescribeDBInstances                        |
+----------+--------------------------------------------------------+
| Endpoint | my-postgres-replica-1.xxxx.us-east-1.rds.amazonaws.com |
| Status   | available                                              |
+----------+--------------------------------------------------------+
```

---

## Step 3 - Connect to the Replica and Verify Read-Only Status

Get the replica endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres-replica-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region us-east-1
```

Connect to the replica:

```bash
psql -h my-postgres-replica-1.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Run this query to confirm it is a standby (replica):

```sql
SELECT pg_is_in_recovery();
```

Expected output:
```
 pg_is_in_recovery
-------------------
 t
(1 row)
```

`pg_is_in_recovery()` returns `t` (true) when the server is in recovery mode, which is the state for read replicas. If it returns `f`, you are connected to the primary.

Now try to write something:

```sql
CREATE TABLE test (id int);
```

Expected output:
```
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

This confirms the replica is in read-only mode. All write statements will fail.

---

## Step 4 - Write Data on Primary and Read It on the Replica

Open a second terminal and connect to the PRIMARY:

```bash
psql -h my-postgres.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

On the primary, create a table and insert data:

```sql
CREATE TABLE replication_test (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO replication_test (message)
VALUES ('row 1'), ('row 2'), ('row 3');
```

Expected output:
```
CREATE TABLE
INSERT 0 3
```

Switch back to your replica terminal and query the table:

```sql
SELECT * FROM replication_test;
```

Expected output:
```
 id | message |          created_at
----+---------+-------------------------------
  1 | row 1   | 2024-01-15 14:30:00.123456+00
  2 | row 2   | 2024-01-15 14:30:00.234567+00
  3 | row 3   | 2024-01-15 14:30:00.345678+00
(3 rows)
```

The data replicated from primary to replica within milliseconds.

---

## Step 5 - Measure Replica Lag

### Method 1: Query on the Replica

Connect to the replica and run:

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

`pg_last_xact_replay_timestamp()` - returns the timestamp of the last transaction that was replayed on this replica.

Expected output:
```
        current_time         |       last_replayed        | replication_lag
-----------------------------+----------------------------+-----------------
 2024-01-15 14:35:00.000000 | 2024-01-15 14:34:59.850000 | 00:00:00.15
```

Healthy same-region lag is under 1 second. Often it is under 100 milliseconds.

### Method 2: CloudWatch Metric

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=my-postgres-replica-1 \
  --start-time 2024-01-15T14:00:00Z \
  --end-time 2024-01-15T15:00:00Z \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

`--metric-name ReplicaLag` - the CloudWatch metric for replica lag in seconds.
`--period 60` - return one data point per 60 seconds.
`--statistics Average` - use the average value for each period.

Replace the `--start-time` and `--end-time` with values that cover the last hour.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2024-01-15T14:30:00Z",
            "Average": 0.15,
            "Unit": "Seconds"
        }
    ]
}
```

---

## Step 6 - Create a Cross-Region Read Replica

> **Concept:** A cross-region replica lets you serve reads from another AWS Region and provides disaster recovery if your primary region fails.

This step creates a replica in us-west-2 from your primary in us-east-1.

First, get the ARN of your primary instance:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].DBInstanceArn' \
  --output text \
  --region us-east-1
```

`DBInstanceArn` - the Amazon Resource Name, a unique ID for the instance across all regions and accounts.

Expected output (yours will differ):
```
arn:aws:rds:us-east-1:123456789012:db:my-postgres
```

Copy that ARN. Now create the cross-region replica. Note: run this in the DESTINATION region (us-west-2):

```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier my-postgres-replica-west \
  --source-db-instance-identifier arn:aws:rds:us-east-1:123456789012:db:my-postgres \
  --db-instance-class db.t3.micro \
  --region us-west-2
```

`--source-db-instance-identifier` - for cross-region, you must use the full ARN (not just the name).
`--region us-west-2` - this is the target region for the new replica.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-replica-west",
        "DBInstanceStatus": "creating",
        "ReadReplicaSourceDBInstanceIdentifier": "arn:aws:rds:us-east-1:123456789012:db:my-postgres",
        ...
    }
}
```

Cross-region replicas take longer to create (15-30 minutes). Skip waiting for this one and move to Step 7.

---

## Step 7 - Promote a Replica (Destructive - Read This First)

> **WARNING:** Promotion is permanent. Once you promote a replica, it becomes a standalone database. It stops receiving replication from the primary. You cannot reverse this. Do NOT promote a replica you need for replication.

For this lab, promote `my-postgres-replica-1` (the same-region replica you created in Step 1).

### What Happens During Promotion

```
Before:
  [my-postgres] ---streaming WAL---> [my-postgres-replica-1]

During promotion:
  [my-postgres-replica-1] applies all remaining WAL
  Replication stops

After:
  [my-postgres]                      [my-postgres-replica-1]
  (still running)                    (now standalone r/w database)
  (no connection between them)
```

### Console

1. Go to RDS -> Databases
2. Click `my-postgres-replica-1`
3. Click "Actions" -> "Promote read replica"
4. In the dialog:
   - Backup retention period: 1 day
   - Preferred backup window: leave default
5. Click "Promote read replica"

### CLI

```bash
aws rds promote-read-replica \
  --db-instance-identifier my-postgres-replica-1 \
  --backup-retention-period 1 \
  --region us-east-1
```

`--backup-retention-period 1` - after promotion, set automated backup retention.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-replica-1",
        "DBInstanceStatus": "modifying",
        "ReadReplicaSourceDBInstanceIdentifier": "",
        ...
    }
}
```

Note that `ReadReplicaSourceDBInstanceIdentifier` is now empty. The link to the primary is broken.

---

## Step 8 - Verify the Promoted Replica Is Now Read-Write

Wait for the status to return to "available" (2-5 minutes).

Connect to the promoted instance:

```bash
psql -h my-postgres-replica-1.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Check if it is still in recovery mode:

```sql
SELECT pg_is_in_recovery();
```

Expected output:
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

`f` means false - this is no longer a replica. It is a standalone primary.

Try a write:

```sql
INSERT INTO replication_test (message) VALUES ('written after promotion');
SELECT * FROM replication_test ORDER BY id DESC LIMIT 3;
```

Expected output:
```
 id | message                 |          created_at
----+-------------------------+-------------------------------
  4 | written after promotion | 2024-01-15 15:00:00.123456+00
  3 | row 3                   | 2024-01-15 14:30:00.345678+00
  2 | row 2                   | 2024-01-15 14:30:00.234567+00
```

Writes work. The promoted replica is now an independent database.

---

## Key Takeaways

1. Read replicas use async replication - expect some lag, especially under heavy write load
2. Always check `pg_is_in_recovery()` to confirm you are on a replica vs primary
3. Replica lag is measured with `pg_last_xact_replay_timestamp()` or CloudWatch `ReplicaLag`
4. Cross-region replicas need the source ARN, not just the name
5. Promotion is permanent - plan carefully before promoting
6. After promotion, the replica is completely independent - changes on original primary do NOT flow to it

---

## Clean Up

Delete the promoted replica (it is now a standalone instance, not connected to anything):

```bash
aws rds delete-db-instance \
  --db-instance-identifier my-postgres-replica-1 \
  --skip-final-snapshot \
  --region us-east-1
```

`--skip-final-snapshot` - skip the final backup. Only use this in lab environments.

If you created the cross-region replica, delete it too:

```bash
aws rds delete-db-instance \
  --db-instance-identifier my-postgres-replica-west \
  --skip-final-snapshot \
  --region us-west-2
```
