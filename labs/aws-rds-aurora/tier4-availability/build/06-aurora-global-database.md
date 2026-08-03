# BUILD 06 - Aurora Global Database: Cross-Region Replication and Failover
## Estimated Time: 50 minutes

---

## What You Will Do

1. Create an Aurora Global Database with a primary region (us-east-1) and a secondary region (us-west-2)
2. Measure cross-region replication lag
3. Perform a managed planned failover
4. Configure write forwarding on the secondary

---

## Before You Start

You need:
- AWS CLI v2 configured with access to both us-east-1 and us-west-2
- An IAM user/role with RDS full access in both regions
- Budget awareness: this lab runs two Aurora clusters simultaneously across two regions

> **Cost warning:** Running two Aurora clusters (each with at least one instance) across two regions costs approximately $0.12-0.24/hr. Delete everything when done.

---

## Step 1 - Create the Primary Aurora Cluster

Create the cluster in us-east-1. This will become the Global Database primary.

```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-global-primary \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-0abc123456789 \
  --region us-east-1
```

Wait for status: creating -> available. Then add the writer instance:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-global-primary-writer \
  --db-cluster-identifier my-global-primary \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.large \
  --region us-east-1
```

`--db-instance-class db.r6g.large` - Global Database requires r6g.large or larger. t3.medium is not supported.

> Note: Global Database requires r-series instances (memory optimized). The minimum is db.r6g.large which costs more than db.t3.medium. Plan accordingly.

Wait for the instance to become available (8-15 minutes).

---

## Step 2 - Get the Cluster ARN and Create the Global Database

Get the ARN of your primary cluster:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-global-primary \
  --query 'DBClusters[0].DBClusterArn' \
  --output text \
  --region us-east-1
```

Expected output (yours will differ):
```
arn:aws:rds:us-east-1:123456789012:cluster:my-global-primary
```

Now create the Global Database using that cluster as the source:

### Console

1. Go to RDS -> Databases
2. Click `my-global-primary`
3. Click "Actions" -> "Add region"
4. Select region: us-west-2
5. Fill in secondary settings:
   - Global database identifier: `my-aurora-global`
   - DB subnet group: select a subnet group in us-west-2
   - DB instance class: db.r6g.large
6. Click "Add region"

### CLI

Create the global database first:

```bash
aws rds create-global-cluster \
  --global-cluster-identifier my-aurora-global \
  --source-db-cluster-identifier arn:aws:rds:us-east-1:123456789012:cluster:my-global-primary \
  --region us-east-1
```

`--global-cluster-identifier` - the name for the global database (spans regions).
`--source-db-cluster-identifier` - the ARN of the primary cluster to use as the base.

Expected output (yours will differ):
```json
{
    "GlobalCluster": {
        "GlobalClusterIdentifier": "my-aurora-global",
        "Status": "creating",
        "Engine": "aurora-postgresql",
        "GlobalClusterMembers": [
            {
                "DBClusterArn": "arn:aws:rds:us-east-1:123456789012:cluster:my-global-primary",
                "IsWriter": true
            }
        ]
    }
}
```

---

## Step 3 - Add the Secondary Region

Create the secondary cluster in us-west-2. Run this command from the us-west-2 region:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-global-secondary \
  --global-cluster-identifier my-aurora-global \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --db-subnet-group-name my-subnet-group-west \
  --vpc-security-group-ids sg-0xyz987654321 \
  --region us-west-2
```

`--global-cluster-identifier my-aurora-global` - links this cluster to the global database.
`--region us-west-2` - this runs in the secondary region.

> Note: You must have a DB subnet group and security group in us-west-2. If you do not have one, create them first in the us-west-2 console.

Now add an instance to the secondary cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-global-secondary-reader \
  --db-cluster-identifier my-global-secondary \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.large \
  --region us-west-2
```

This takes 15-20 minutes. The secondary receives a full copy of the primary data, then starts receiving redo log replication.

---

## Step 4 - Verify the Global Database Status

```bash
aws rds describe-global-clusters \
  --global-cluster-identifier my-aurora-global \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "GlobalClusters": [
        {
            "GlobalClusterIdentifier": "my-aurora-global",
            "Status": "available",
            "Engine": "aurora-postgresql",
            "DeletionProtection": false,
            "GlobalClusterMembers": [
                {
                    "DBClusterArn": "arn:aws:rds:us-east-1:123456789012:cluster:my-global-primary",
                    "Readers": [],
                    "IsWriter": true
                },
                {
                    "DBClusterArn": "arn:aws:rds:us-west-2:123456789012:cluster:my-global-secondary",
                    "Readers": ["arn:aws:rds:us-west-2:123456789012:db:my-global-secondary-reader"],
                    "IsWriter": false
                }
            ]
        }
    ]
}
```

---

## Step 5 - Write Data to Primary and Confirm It Appears in Secondary

Connect to the primary (us-east-1):

```bash
psql -h my-global-primary.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Create a test table and insert data:

```sql
CREATE TABLE global_test (
    id SERIAL PRIMARY KEY,
    region TEXT,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO global_test (region, message)
VALUES ('us-east-1', 'Written in primary region');
```

Expected output:
```
CREATE TABLE
INSERT 0 1
```

Connect to the secondary (us-west-2):

```bash
psql -h my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

```sql
SELECT * FROM global_test;
```

Expected output:
```
 id | region    | message                   |          created_at
----+-----------+---------------------------+-------------------------------
  1 | us-east-1 | Written in primary region | 2024-01-15 15:00:00.123456+00
(1 row)
```

The data replicated from us-east-1 to us-west-2. Sub-second replication across regions.

---

## Step 6 - Measure Cross-Region Replication Lag

Check the lag using CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=my-global-secondary \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region us-west-2
```

`--metric-name AuroraGlobalDBReplicationLag` - Global Database specific metric, in milliseconds.
`--region us-west-2` - check the metric in the secondary region.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2024-01-15T15:05:00Z",
            "Maximum": 450.0,
            "Unit": "Milliseconds"
        }
    ]
}
```

450 milliseconds from us-east-1 to us-west-2. This is typical for cross-region replication. AWS guarantees less than 1 second under normal conditions.

Also check from the secondary database directly:

```sql
-- On the secondary
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

Expected output:
```
        current_time         |       last_replayed         |   replication_lag
-----------------------------+-----------------------------+--------------------
 2024-01-15 15:10:00.000000 | 2024-01-15 15:09:59.550000 | 00:00:00.45
```

---

## Step 7 - Enable Write Forwarding

Write forwarding allows applications in the secondary region to send writes to the secondary endpoint. Aurora forwards them to the primary region automatically.

### Console

1. Go to RDS -> Databases
2. Click `my-global-secondary` (the secondary cluster)
3. Click "Modify"
4. Under "Read replica write forwarding", enable it
5. Click "Continue" -> "Modify cluster"

### CLI

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier my-global-secondary \
  --enable-global-write-forwarding \
  --apply-immediately \
  --region us-west-2
```

`--enable-global-write-forwarding` - turns on write forwarding for this secondary cluster.

Expected output:
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "my-global-secondary",
        "GlobalWriteForwardingRequested": true,
        "GlobalWriteForwardingStatus": "enabling",
        ...
    }
}
```

Wait 2-3 minutes for `GlobalWriteForwardingStatus` to become `enabled`.

Check status:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-global-secondary \
  --query 'DBClusters[0].{WFStatus:GlobalWriteForwardingStatus,WFRequested:GlobalWriteForwardingRequested}' \
  --output table \
  --region us-west-2
```

Expected output:
```
-------------------------------------
|       DescribeDBClusters          |
+----------------+------------------+
| WFRequested    | True             |
| WFStatus       | enabled          |
+----------------+------------------+
```

---

## Step 8 - Test Write Forwarding

Connect to the SECONDARY cluster endpoint:

```bash
psql -h my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Set the session to allow write forwarding:

```sql
SET aurora_replica_read_consistency = 'EVENTUAL';
```

Now try a write (this will be forwarded to the primary):

```sql
INSERT INTO global_test (region, message)
VALUES ('us-west-2', 'Written via write forwarding from secondary');
```

Expected output:
```
INSERT 0 1
```

Check on the primary that the row arrived:

```sql
-- On the primary (us-east-1)
SELECT * FROM global_test ORDER BY id;
```

Expected output:
```
 id | region    | message                                         |          created_at
----+-----------+-------------------------------------------------+-------------------------------
  1 | us-east-1 | Written in primary region                       | 2024-01-15 15:00:00.123456+00
  2 | us-west-2 | Written via write forwarding from secondary     | 2024-01-15 15:15:00.987654+00
```

The write from us-west-2 traveled to us-east-1 and was committed there, then replicated back to us-west-2.

---

## Step 9 - Perform a Managed Planned Failover

A managed planned failover switches the primary region. This is used for planned migration or maintenance. It is non-destructive with no data loss.

> **Before you start:** Make sure replication lag is near-zero. Check CloudWatch `AuroraGlobalDBReplicationLag` in us-west-2. If it is above 1 second, wait for it to drop.

### Console

1. Go to RDS -> Global databases
2. Click `my-aurora-global`
3. Click "Actions" -> "Switch over or fail over global database"
4. Select "Switch over" (planned, no data loss)
5. Select the target region: us-west-2
6. Click "Confirm"

### CLI

```bash
aws rds switchover-global-cluster \
  --global-cluster-identifier my-aurora-global \
  --target-db-cluster-identifier arn:aws:rds:us-west-2:123456789012:cluster:my-global-secondary \
  --region us-east-1
```

`--target-db-cluster-identifier` - the cluster you want to become the new primary.

Expected output (yours will differ):
```json
{
    "GlobalCluster": {
        "GlobalClusterIdentifier": "my-aurora-global",
        "Status": "switching-over",
        ...
    }
}
```

This takes 5-20 minutes. During switchover:
1. Replication lag is drained to zero
2. Primary (us-east-1) becomes read-only
3. Secondary (us-west-2) is promoted to primary
4. DNS endpoints are updated
5. Old primary (us-east-1) becomes the secondary

Check completion:

```bash
aws rds describe-global-clusters \
  --global-cluster-identifier my-aurora-global \
  --query 'GlobalClusters[0].GlobalClusterMembers[*].{Cluster:DBClusterArn,Writer:IsWriter}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
-----------------------------------------------------------------------------------
|                           DescribeGlobalClusters                                |
+--------+------------------------------------------------------------------------+
| Writer | Cluster                                                                 |
+--------+------------------------------------------------------------------------+
| False  | arn:aws:rds:us-east-1:123456789012:cluster:my-global-primary            |
| True   | arn:aws:rds:us-west-2:123456789012:cluster:my-global-secondary           |
+--------+------------------------------------------------------------------------+
```

us-west-2 is now the writer (IsWriter: True). us-east-1 is now the secondary.

---

## Step 10 - Use the Global Database Writer Endpoint

Starting October 2024, Aurora Global Database provides a **writer endpoint** at the global level. Previously, you had to track which region was the primary and update your application's connection string after every failover. The writer endpoint eliminates that.

### Console

1. Go to RDS -> Global databases.
2. Click `my-aurora-global`.
3. In the "Connectivity and security" section, look for **Global cluster writer endpoint**.
4. The endpoint looks like: `my-aurora-global.global-xxxx.rds.amazonaws.com`

### CLI

```bash
aws rds describe-global-clusters \
  --global-cluster-identifier my-aurora-global \
  --query 'GlobalClusters[0].{Endpoint:Endpoint,Status:Status}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
----------------------------------------------------------------------
|                     DescribeGlobalClusters                         |
+------------+-------------------------------------------------------+
| Endpoint   | my-aurora-global.global-xxxx.rds.amazonaws.com        |
| Status     | available                                              |
+------------+-------------------------------------------------------+
```

### How the Writer Endpoint Works

The global writer endpoint always resolves to the current primary cluster's writer endpoint, regardless of which region is the primary.

```
Before failover:
  my-aurora-global.global-xxxx.rds.amazonaws.com -> us-east-1 primary

After failover to us-west-2:
  my-aurora-global.global-xxxx.rds.amazonaws.com -> us-west-2 primary
```

Your application connects to the global writer endpoint once and never needs to change connection strings after a failover or switchover. DNS propagation typically completes within 30-60 seconds after a switchover.

### Test the Writer Endpoint

Connect using the global writer endpoint:

```bash
psql -h my-aurora-global.global-xxxx.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Verify you are on the primary:

```sql
SELECT NOT pg_is_in_recovery() AS is_primary,
       current_setting('server_version') AS version,
       inet_server_addr() AS server_ip;
```

Expected output:
```
 is_primary | version |  server_ip
------------+---------+------------
 t          | 16.6    | 10.0.1.45
(1 row)
```

> **Recommendation:** For new applications, always use the global writer endpoint instead of the regional cluster endpoint. It removes the need for application-side failover logic. For existing applications, update your connection string from the regional endpoint to the global endpoint during your next maintenance window.

---

## Step 11 - Switchover vs Failover - Know the Difference

These terms are often confused. Here is the distinction:

| Operation | Switchover | Failover (Detach and Promote) |
|-----------|-----------|-------------------------------|
| When to use | Planned maintenance, region migration | Unplanned outage, primary region down |
| Data loss | Zero | Possible (depends on replication lag at time of failure) |
| CLI command | `aws rds switchover-global-cluster` | `aws rds failover-global-cluster` |
| Duration | 5-20 minutes | 1-5 minutes |
| Primary status | Demoted to secondary | Detached and must be re-added manually |
| Automation | Fully managed | Semi-manual (you choose the target) |
| RPO | 0 (lag drained before switch) | Depends on lag (typically < 1 second) |
| RTO | 5-20 minutes | 1-5 minutes |

**Switchover** (used in Step 9 above): AWS drains all replication lag to zero before switching. No data loss. Both clusters remain in the Global Database. Use for planned maintenance.

**Failover** (detach and promote): Used when the primary region is unreachable. AWS promotes a secondary to an independent cluster. Any data not yet replicated is lost. You must manually re-add the old primary as a secondary after it recovers.

### RPO Management

To minimize data loss risk during an unplanned failover:
1. Monitor `AuroraGlobalDBReplicationLag` with a CloudWatch alarm
2. Set the alarm threshold to 1000ms (1 second)
3. If lag consistently exceeds your RPO target, investigate storage throughput or network latency

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name global-db-lag-high \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=my-global-secondary \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions [YOUR-SNS-TOPIC-ARN] \
  --region us-west-2
```

This alarm fires if replication lag exceeds 1 second for 3 consecutive minutes.

---

## Key Takeaways

1. Global Database replication is storage-level - typical lag is under 1 second cross-region
2. Planned failover (switchover) is non-destructive - use it for maintenance and migration
3. Unplanned failover requires manual detach-and-promote - it is not automatic
4. Write forwarding adds latency (round trip to primary) but simplifies application code
5. Global Database requires r-series instances (db.r6g.large minimum) - budget accordingly
6. You can have up to 5 secondary regions
7. The global writer endpoint (Oct 2024) eliminates the need to update connection strings after failover
8. Always monitor `AuroraGlobalDBReplicationLag` - it determines your RPO in an unplanned failover

---

## Clean Up

Delete in this order:

```bash
# 1. Remove secondary region from global database
aws rds remove-from-global-cluster \
  --global-cluster-identifier my-aurora-global \
  --db-cluster-identifier arn:aws:rds:us-west-2:123456789012:cluster:my-global-secondary \
  --region us-east-1

# 2. Delete secondary instance
aws rds delete-db-instance \
  --db-instance-identifier my-global-secondary-reader \
  --skip-final-snapshot \
  --region us-west-2

# 3. Delete secondary cluster
aws rds delete-db-cluster \
  --db-cluster-identifier my-global-secondary \
  --skip-final-snapshot \
  --region us-west-2

# 4. Delete primary instance
aws rds delete-db-instance \
  --db-instance-identifier my-global-primary-writer \
  --skip-final-snapshot \
  --region us-east-1

# 5. Delete primary cluster
aws rds delete-db-cluster \
  --db-cluster-identifier my-global-primary \
  --skip-final-snapshot \
  --region us-east-1

# 6. Delete global database
aws rds delete-global-cluster \
  --global-cluster-identifier my-aurora-global \
  --region us-east-1
```

`aws rds remove-from-global-cluster` - detaches a secondary cluster before deletion.
