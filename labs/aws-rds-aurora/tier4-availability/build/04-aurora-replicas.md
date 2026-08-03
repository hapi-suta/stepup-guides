# BUILD 04 - Aurora Replicas: Add, Prioritize, Test Failover
## Estimated Time: 40 minutes

---

## What You Will Do

1. Add Aurora replicas to your cluster
2. Configure failover priority tiers
3. Test the reader endpoint for load balancing
4. Observe replica lag (near-zero compared to RDS)
5. Trigger an Aurora failover and measure downtime

---

## Before You Start

You need:
- The Aurora cluster from BUILD 03 (`my-aurora-cluster`) in "available" status
- AWS CLI v2 configured
- psql available on your machine or EC2

---

## Step 1 - Check Your Current Cluster

See what instances you have:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].DBClusterMembers' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
----------------------------------------------
|          DescribeDBClusters                |
+------------------------+-------------------+
|  DBInstanceIdentifier  | IsClusterWriter   |
+------------------------+-------------------+
|  my-aurora-writer      | True              |
+------------------------+-------------------+
```

You currently have only one instance (the writer). In this lab you will add two readers.

---

## Step 2 - Add the First Aurora Replica

### Console

1. Go to RDS -> Databases
2. Click your cluster name `my-aurora-cluster`
3. Click "Actions" -> "Add reader"
4. Fill in:
   - DB instance identifier: `my-aurora-reader-1`
   - DB instance class: db.t3.medium (same as writer)
   - Availability Zone: us-east-1b (different from the writer's AZ)
   - Priority: Tier 1
5. Click "Add reader"

### CLI

```bash
aws rds create-db-instance \
  --db-instance-identifier my-aurora-reader-1 \
  --db-cluster-identifier my-aurora-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --availability-zone us-east-1b \
  --promotion-tier 1 \
  --region us-east-1
```

`--db-cluster-identifier` - attaches this instance to the cluster as a reader.
`--availability-zone us-east-1b` - place in a different AZ from the writer for resilience.
`--promotion-tier 1` - failover priority. 0 = highest priority, 15 = lowest.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-aurora-reader-1",
        "DBInstanceStatus": "creating",
        "DBClusterIdentifier": "my-aurora-cluster",
        "PromotionTier": 1,
        ...
    }
}
```

---

## Step 3 - Add the Second Aurora Replica

```bash
aws rds create-db-instance \
  --db-instance-identifier my-aurora-reader-2 \
  --db-cluster-identifier my-aurora-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --availability-zone us-east-1c \
  --promotion-tier 2 \
  --region us-east-1
```

`--availability-zone us-east-1c` - use a third AZ so each instance is in its own AZ.
`--promotion-tier 2` - lower priority than reader-1. If writer fails, reader-1 is promoted first.

---

## Step 4 - Wait for Both Readers to Become Available

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter,Tier:PromotionTier}' \
  --output table \
  --region us-east-1
```

Run this every 2 minutes until all three instances are shown. Then check each instance status:

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=my-aurora-cluster \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,AZ:AvailabilityZone}' \
  --output table \
  --region us-east-1
```

`--filters Name=db-cluster-id` - filter instances by cluster ID instead of listing all instances.

Expected output (yours will differ):
```
-----------------------------------------------
|          DescribeDBInstances                |
+----------------------+----------+-----------+
| AZ                   | Instance | Status    |
+----------------------+----------+-----------+
| us-east-1a           | my-aurora-writer   | available |
| us-east-1b           | my-aurora-reader-1 | available |
| us-east-1c           | my-aurora-reader-2 | available |
+----------------------+----------+-----------+
```

---

## Step 5 - View the Cluster Endpoints

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
-------------------------------------------------------------------
|                      DescribeDBClusters                         |
+--------+----------------------------------------------------------+
| Reader | my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com |
| Writer | my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com    |
+--------+----------------------------------------------------------+
```

---

## Step 6 - Test the Reader Endpoint Load Balancing

Connect to the reader endpoint multiple times and see which instance you land on each time.

Connect once:

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 inet_server_addr | pg_is_in_recovery
------------------+-------------------
 10.0.2.45        | t
```

Connect again in a new session:

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 inet_server_addr | pg_is_in_recovery
------------------+-------------------
 10.0.3.67        | t
```

The IP address is different. You landed on a different reader. This is DNS round-robin load balancing.

`pg_is_in_recovery()` returns `t` (true) on both - confirms these are replicas, not the writer.

---

## Step 7 - Measure Replica Lag on Aurora

Connect to one of the readers:

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Check replica lag using the standard PostgreSQL method:

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS lag;
```

Expected output:
```
        current_time         |       last_replayed         |    lag
-----------------------------+-----------------------------+------------
 2024-01-15 15:00:00.000000 | 2024-01-15 14:59:59.950000 | 00:00:00.05
```

50 milliseconds of lag. This is typical for Aurora. Compare this to RDS read replicas which often have 100-500ms of lag or more under load.

Also check the CloudWatch Aurora-specific metric:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=my-aurora-reader-1 \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region us-east-1
```

`--metric-name AuroraReplicaLag` - Aurora-specific replica lag in milliseconds.
`--statistics Maximum` - use maximum to see the worst lag in the period.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2024-01-15T15:00:00Z",
            "Maximum": 52.3,
            "Unit": "Milliseconds"
        }
    ]
}
```

52.3 milliseconds maximum lag. Aurora replicas are much closer to the writer than RDS read replicas because they share the same storage layer.

---

## Step 8 - Configure Failover Priority Tiers

Let's verify and update the priority tiers. The writer should not have priority set (it is the writer). Readers should be 0-15.

Check current tiers:

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=my-aurora-cluster \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,Tier:PromotionTier,Writer:MultiAZ}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------
|              DescribeDBInstances                   |
+--------------------+--------+--------------------+
| Instance           | Tier   | ...                |
+--------------------+--------+--------------------+
| my-aurora-writer   | 1      | ...                |
| my-aurora-reader-1 | 1      | ...                |
| my-aurora-reader-2 | 2      | ...                |
+--------------------+--------+--------------------+
```

Set reader-1 to tier 0 (highest priority - will be promoted first if writer fails):

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-aurora-reader-1 \
  --promotion-tier 0 \
  --apply-immediately \
  --region us-east-1
```

`--promotion-tier 0` - tier 0 is the highest priority. This reader will become writer first.

Set reader-2 to tier 1 (backup promotion candidate):

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-aurora-reader-2 \
  --promotion-tier 1 \
  --apply-immediately \
  --region us-east-1
```

---

## Step 9 - Trigger an Aurora Failover and Measure Downtime

Before triggering failover, open a terminal and run a connection loop. This will show when connections fail and when they recover.

In one terminal, run this loop:

```bash
while true; do
  psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -c "SELECT now(), inet_server_addr();" 2>&1
  sleep 1
done
```

In a second terminal, trigger the failover:

### Console

1. Go to RDS -> Databases
2. Select `my-aurora-cluster`
3. Click "Actions" -> "Failover"
4. Confirm by clicking "Failover"

### CLI

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --target-db-instance-identifier my-aurora-reader-1 \
  --region us-east-1
```

`--target-db-instance-identifier my-aurora-reader-1` - force failover to this specific reader. Aurora will promote it.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "my-aurora-cluster",
        "Status": "failing-over",
        ...
    }
}
```

Watch your first terminal. You will see:

```
        now          | inet_server_addr
---------------------+-----------------
 2024-01-15 15:05:00 | 10.0.1.23
psql: error: connection to server at "my-aurora-cluster..." failed
psql: error: connection to server at "my-aurora-cluster..." failed
        now          | inet_server_addr
---------------------+-----------------
 2024-01-15 15:05:28 | 10.0.2.45
```

Count the errors. Each error = 1 second of downtime (because of the `sleep 1`).

Typical Aurora failover time: 20-35 seconds.

After failover, verify the new writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------
|           DescribeDBClusters                       |
+--------------------+-------------------------------+
| Instance           | Writer                        |
+--------------------+-------------------------------+
| my-aurora-writer   | False                         |
| my-aurora-reader-1 | True                          |
| my-aurora-reader-2 | False                         |
+--------------------+-------------------------------+
```

`my-aurora-reader-1` is now the writer. The original writer is now a reader.

---

## Key Takeaways

1. Aurora replicas share storage with the writer - no WAL streaming means near-zero lag
2. The reader endpoint distributes new connections across all readers via DNS round-robin
3. Failover priority (tier 0-15) controls which reader becomes writer when the writer fails
4. Aurora failover is faster than RDS Multi-AZ: 20-35 seconds vs 60-120 seconds
5. After failover, the old writer becomes a reader - the cluster continues with all instances
6. You can force failover to a specific target with `--target-db-instance-identifier`

---

## Clean Up

Keep the cluster running for BUILD 05 (Endpoints). Or delete if you are done:

```bash
# Delete instances (must delete all readers before the cluster)
aws rds delete-db-instance \
  --db-instance-identifier my-aurora-reader-2 \
  --skip-final-snapshot \
  --region us-east-1

aws rds delete-db-instance \
  --db-instance-identifier my-aurora-reader-1 \
  --skip-final-snapshot \
  --region us-east-1

aws rds delete-db-instance \
  --db-instance-identifier my-aurora-writer \
  --skip-final-snapshot \
  --region us-east-1

# Wait for all instances to be deleted, then delete the cluster
aws rds delete-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --skip-final-snapshot \
  --region us-east-1
```
