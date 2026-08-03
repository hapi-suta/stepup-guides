# BUILD 05 - Global Database: Cross-Region Replication and Failover
## Estimated Time: 50 minutes

---

## What You Will Do

1. Create an Aurora Global Database with primary in us-east-1 and secondary in us-west-2
2. Write data to the primary and verify it appears in the secondary
3. Measure cross-region replication lag
4. Enable write forwarding on the secondary
5. Perform a managed planned failover (switchover)

> **Cost warning:** This lab runs two Aurora clusters across two regions. Each cluster has at least one instance (db.r6g.large minimum). Estimated cost: $0.48/hr total. Delete everything when done.

---

## Before You Start

You need:
- AWS CLI v2 configured with access to both us-east-1 and us-west-2
- A DB subnet group in us-west-2 (create one if needed)
- A security group in us-west-2 that allows port 5432
- psql installed

> **Note:** Global Database requires r-series instances (db.r6g.large minimum). The t3 instances used in earlier labs are not supported. This means higher cost.

---

## Step 1 - Create the Primary Cluster in us-east-1

**In your terminal:**

```bash
aws rds create-db-cluster \
  --db-cluster-identifier devops-global-primary \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-0abc123456789 \
  --region us-east-1
```

Wait for the cluster to become available, then add the writer instance:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-global-primary-writer \
  --db-cluster-identifier devops-global-primary \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.large \
  --region us-east-1
```

`--db-instance-class db.r6g.large` - Global Database requires r-series instances. This is the minimum.

Wait 8-15 minutes for the instance to become available.

---

## Step 2 - Get the Primary Cluster ARN

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-global-primary \
  --query 'DBClusters[0].DBClusterArn' \
  --output text \
  --region us-east-1
```

Expected output (yours will differ):
```
arn:aws:rds:us-east-1:123456789012:cluster:devops-global-primary
```

Copy this ARN. You will use it in the next step.

---

## Step 3 - Create the Global Database

**In your terminal:**

```bash
aws rds create-global-cluster \
  --global-cluster-identifier devops-aurora-global \
  --source-db-cluster-identifier arn:aws:rds:us-east-1:123456789012:cluster:devops-global-primary \
  --region us-east-1
```

`--global-cluster-identifier` - the name for the global database (spans regions).
`--source-db-cluster-identifier` - the ARN of the primary cluster.

Expected output (yours will differ):
```json
{
    "GlobalCluster": {
        "GlobalClusterIdentifier": "devops-aurora-global",
        "Status": "creating",
        "GlobalClusterMembers": [
            {
                "DBClusterArn": "arn:aws:rds:us-east-1:123456789012:cluster:devops-global-primary",
                "IsWriter": true
            }
        ]
    }
}
```

---

## Step 4 - Add the Secondary Region (us-west-2)

**In your terminal:**

Create the secondary cluster. Run this targeting the us-west-2 region:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier devops-global-secondary \
  --global-cluster-identifier devops-aurora-global \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --db-subnet-group-name my-subnet-group-west \
  --vpc-security-group-ids sg-0xyz987654321 \
  --region us-west-2
```

`--global-cluster-identifier devops-aurora-global` - links this cluster to the global database.
`--region us-west-2` - the secondary region.

Replace `my-subnet-group-west` and `sg-0xyz987654321` with your actual us-west-2 resources.

Add an instance to the secondary cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-global-secondary-reader \
  --db-cluster-identifier devops-global-secondary \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.large \
  --region us-west-2
```

This takes 15-20 minutes. The secondary receives a full copy of the primary data.

---

## Step 5 - Verify the Global Database

**In your terminal:**

```bash
aws rds describe-global-clusters \
  --global-cluster-identifier devops-aurora-global \
  --query 'GlobalClusters[0].{Status:Status,Members:GlobalClusterMembers[*].{Cluster:DBClusterArn,Writer:IsWriter}}' \
  --output json \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "Status": "available",
    "Members": [
        {
            "Cluster": "arn:aws:rds:us-east-1:123456789012:cluster:devops-global-primary",
            "Writer": true
        },
        {
            "Cluster": "arn:aws:rds:us-west-2:123456789012:cluster:devops-global-secondary",
            "Writer": false
        }
    ]
}
```

---

## Step 6 - Write Data and Verify Cross-Region Replication

**In your terminal:**

Connect to the primary (us-east-1):

```bash
psql -h devops-global-primary.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

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

Exit psql:

```sql
\q
```

Connect to the secondary (us-west-2):

```bash
psql -h devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
SELECT * FROM global_test;
```

Expected output (yours will differ):
```
 id |  region   |          message          |          created_at
----+-----------+---------------------------+-------------------------------
  1 | us-east-1 | Written in primary region | 2026-06-09 15:00:00.123456+00
(1 row)
```

The data replicated from us-east-1 to us-west-2 in under 1 second.

Exit psql:

```sql
\q
```

---

## Step 7 - Measure Cross-Region Replication Lag

**In your terminal:**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=devops-global-secondary \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region us-west-2
```

`--metric-name AuroraGlobalDBReplicationLag` - Global Database specific metric in milliseconds.
`--region us-west-2` - check the metric in the secondary region.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2026-06-09T15:05:00Z",
            "Maximum": 450.0,
            "Unit": "Milliseconds"
        }
    ]
}
```

450ms between us-east-1 and us-west-2. This is typical. AWS guarantees under 1 second for normal conditions.

---

## Step 8 - Enable Write Forwarding

**In your terminal:**

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-global-secondary \
  --enable-global-write-forwarding \
  --apply-immediately \
  --region us-west-2
```

`--enable-global-write-forwarding` - allows writes on the secondary to be forwarded to the primary.

Wait 2-3 minutes, then verify:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-global-secondary \
  --query 'DBClusters[0].GlobalWriteForwardingStatus' \
  --output text \
  --region us-west-2
```

Expected output:
```
enabled
```

Test write forwarding by connecting to the secondary and writing:

```bash
psql -h devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
SET aurora_replica_read_consistency = 'EVENTUAL';

INSERT INTO global_test (region, message)
VALUES ('us-west-2', 'Written via write forwarding');
```

Expected output:
```
INSERT 0 1
```

The write was forwarded to us-east-1 and committed there, then replicated back to us-west-2.

Exit psql:

```sql
\q
```

---

## Step 9 - Perform a Managed Planned Failover (Switchover)

This switches which region is the primary. It is non-destructive with zero data loss.

**In your terminal:**

First, confirm replication lag is near zero:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=devops-global-secondary \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region us-west-2
```

If lag is under 1 second, proceed with the switchover:

```bash
aws rds switchover-global-cluster \
  --global-cluster-identifier devops-aurora-global \
  --target-db-cluster-identifier arn:aws:rds:us-west-2:123456789012:cluster:devops-global-secondary \
  --region us-east-1
```

`--target-db-cluster-identifier` - the cluster you want to become the new primary.

Expected output (yours will differ):
```json
{
    "GlobalCluster": {
        "GlobalClusterIdentifier": "devops-aurora-global",
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
  --global-cluster-identifier devops-aurora-global \
  --query 'GlobalClusters[0].GlobalClusterMembers[*].{Cluster:DBClusterArn,Writer:IsWriter}' \
  --output table \
  --region us-east-1
```

Expected output after switchover:
```
-----------------------------------------------------------------------------------
|                           DescribeGlobalClusters                                |
+--------+------------------------------------------------------------------------+
| Writer | Cluster                                                                 |
+--------+------------------------------------------------------------------------+
| False  | arn:aws:rds:us-east-1:123456789012:cluster:devops-global-primary        |
| True   | arn:aws:rds:us-west-2:123456789012:cluster:devops-global-secondary      |
+--------+------------------------------------------------------------------------+
```

us-west-2 is now the writer. us-east-1 is now the secondary.

---

## Key Takeaways

1. Global Database replication is storage-level - typical lag under 1 second cross-region
2. Planned failover (switchover) is non-destructive with zero data loss
3. Unplanned failover requires manual `remove-from-global-cluster` - it is NOT automatic
4. Write forwarding adds cross-region round-trip latency but simplifies application code
5. Global Database requires r-series instances (db.r6g.large minimum)
6. You can have up to 5 secondary regions

---

## Clean Up

Delete in this order:

```bash
aws rds remove-from-global-cluster \
  --global-cluster-identifier devops-aurora-global \
  --db-cluster-identifier arn:aws:rds:us-east-1:123456789012:cluster:devops-global-primary \
  --region us-west-2

aws rds delete-db-instance \
  --db-instance-identifier devops-global-primary-writer \
  --skip-final-snapshot \
  --region us-east-1

aws rds delete-db-cluster \
  --db-cluster-identifier devops-global-primary \
  --skip-final-snapshot \
  --region us-east-1

aws rds remove-from-global-cluster \
  --global-cluster-identifier devops-aurora-global \
  --db-cluster-identifier arn:aws:rds:us-west-2:123456789012:cluster:devops-global-secondary \
  --region us-west-2

aws rds delete-db-instance \
  --db-instance-identifier devops-global-secondary-reader \
  --skip-final-snapshot \
  --region us-west-2

aws rds delete-db-cluster \
  --db-cluster-identifier devops-global-secondary \
  --skip-final-snapshot \
  --region us-west-2

aws rds delete-global-cluster \
  --global-cluster-identifier devops-aurora-global \
  --region us-east-1
```
