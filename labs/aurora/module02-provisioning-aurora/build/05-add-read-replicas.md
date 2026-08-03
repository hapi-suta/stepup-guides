# Build 05 - Add Read Replicas
## Module 02 - Provisioning Aurora (CLI + Console)

**Estimated time:** 30 minutes
**Difficulty:** Beginner
**Cost:** ~$0.082/hour for the additional reader instance (db.t3.medium)
**Prerequisite:** Build 04 complete (running Aurora cluster with writer and one reader)

---

## What You Will Do

You will add a second reader instance to your Aurora cluster, verify that the reader endpoint load-balances across both readers, and check replication lag using CloudWatch metrics. By the end you will:

- Have a three-instance cluster (1 writer, 2 readers)
- Understand how the reader endpoint distributes connections
- Know how to check the AuroraReplicaLag metric
- Understand promotion tiers

> **Cost warning:** Adding a third db.t3.medium instance adds approximately $0.082/hour to your costs. Delete it when you finish this lab.

---

## Before You Start

You need:
- Your Aurora cluster `devops-lab-cluster` running with `devops-lab-writer-1` and `devops-lab-reader-1`
- Your reader endpoint saved as `$READER_ENDPOINT`
- AWS CLI configured
- psql installed

If you do not have the reader endpoint saved:

**In your terminal** (local machine):

```bash
READER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].ReaderEndpoint" \
  --output text)
```

```bash
echo "Reader endpoint: $READER_ENDPOINT"
```

---

## Part A - Add a Second Reader Instance

### Step 1 - Create the Second Reader

**In your terminal** (local machine):

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-reader-2 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible
```

What each flag does:

- `--db-instance-identifier devops-lab-reader-2` - unique name for this second reader.
- `--db-cluster-identifier devops-lab-cluster` - the cluster to add this instance to. Since the cluster already has a writer, this new instance is automatically assigned the reader role.
- `--db-instance-class db.t3.medium` - same instance class as the other instances. Readers can use a different class than the writer if needed.
- `--engine aurora-postgresql` - must match the cluster engine.
- `--publicly-accessible` - allows connections from outside the VPC.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-reader-2",
        "DBInstanceClass": "db.t3.medium",
        "Engine": "aurora-postgresql",
        "DBInstanceStatus": "creating",
        ...
    }
}
```

### Step 2 - Wait for the New Reader to Be Available

**In your terminal** (local machine):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-reader-2
```

This takes 5 to 10 minutes. The cursor sits still while waiting.

### Step 3 - Verify the Cluster Now Has Three Members

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,PromotionTier:PromotionTier}" \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------
|                  DescribeDBClusters                      |
+---------------------+----------+----------------+
|      Instance       | IsWriter | PromotionTier  |
+---------------------+----------+----------------+
|  devops-lab-writer-1|  True    |  1             |
|  devops-lab-reader-1|  False   |  1             |
|  devops-lab-reader-2|  False   |  1             |
+---------------------+----------+----------------+
```

Three instances: one writer, two readers. All at promotion tier 1.

### Step 4 - Check Instance AZs

**In your terminal** (local machine):

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,AZ:AvailabilityZone,Class:DBInstanceClass,Status:DBInstanceStatus}" \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------------------------
|                      DescribeDBInstances                            |
+------------+-----------------+---------------------+-----------+
|     AZ     |     Class       |         ID          |  Status   |
+------------+-----------------+---------------------+-----------+
| us-east-1a | db.t3.medium    | devops-lab-writer-1 | available |
| us-east-1b | db.t3.medium    | devops-lab-reader-1 | available |
| us-east-1c | db.t3.medium    | devops-lab-reader-2 | available |
+------------+-----------------+---------------------+-----------+
```

Aurora placed each instance in a different AZ. With three instances across three AZs, your cluster can survive any single AZ failure.

---

## Part B - Verify Reader Endpoint Load-Balancing

The reader endpoint uses DNS-based round-robin. Each time a new connection is made, DNS resolves to one of the available readers. Let's test this.

### Step 1 - Connect Multiple Times and Check the IP

**In your terminal** (local machine):

Run this command several times:

```bash
psql -h $READER_ENDPOINT -U labadmin -d labdb -p 5432 -c "SELECT inet_server_addr();"
```

Expected output - first run (yours will differ):
```
 inet_server_addr
------------------
 10.0.2.78
(1 row)
```

Run the same command again:

```bash
psql -h $READER_ENDPOINT -U labadmin -d labdb -p 5432 -c "SELECT inet_server_addr();"
```

Expected output - second run (yours will differ):
```
 inet_server_addr
------------------
 10.0.3.92
(1 row)
```

If you see different IPs, the reader endpoint is load-balancing across your two readers. If you see the same IP both times, run the command a few more times - DNS round-robin does not guarantee alternation on every connection.

### Step 2 - Verify with DNS Resolution

**In your terminal** (local machine):

```bash
dig +short $READER_ENDPOINT
```

Expected output (yours will differ):
```
10.0.2.78
10.0.3.92
```

You may see one or two IPs. DNS caching means you might not see both on every query. The reader endpoint rotates through the available reader IPs.

### Step 3 - Check Which Instance You Connected To

**In your terminal** (local machine):

```bash
psql -h $READER_ENDPOINT -U labadmin -d labdb -p 5432 -c "SELECT server_id, is_current FROM aurora_replica_status();"
```

Expected output (yours will differ):
```
       server_id        | is_current
------------------------+------------
 devops-lab-writer-1    | f
 devops-lab-reader-1    | t
 devops-lab-reader-2    | f
(3 rows)
```

The `is_current = t` row tells you which instance you landed on. Run it again and you may land on the other reader.

---

## Part C - Check Replication Lag

### Step 1 - Check Lag via aurora_replica_status()

**In your terminal** (local machine):

```bash
psql -h $READER_ENDPOINT -U labadmin -d labdb -p 5432
```

**In psql** (connected to reader endpoint):

```sql
SELECT server_id, replica_lag_in_msec
FROM aurora_replica_status()
WHERE replica_lag_in_msec IS NOT NULL;
```

Expected output (yours will differ):
```
       server_id        | replica_lag_in_msec
------------------------+--------------------
 devops-lab-reader-1    |              15.234
 devops-lab-reader-2    |              22.456
(2 rows)
```

Both readers show lag under 50 milliseconds. This is typical for Aurora. The writer does not appear because it has no lag (it is the source).

Exit psql:

```sql
\q
```

### Step 2 - Check Lag via CloudWatch (AuroraReplicaLag Metric)

The `AuroraReplicaLag` CloudWatch metric is the recommended way to monitor replication lag in production.

**In your terminal** (local machine):

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "AuroraReplicaLag" \
  --dimensions "Name=DBInstanceIdentifier,Value=devops-lab-reader-1" \
  --start-time "$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 60 \
  --statistics Average \
  --query "Datapoints | sort_by(@, &Timestamp) | [-3:].{Time:Timestamp,AvgLagMs:Average}" \
  --output table
```

> **Note:** On Linux, replace `-v-10M` with `-d '10 minutes ago'` in the date command. The `-v-10M` syntax is macOS-specific.

What each flag does:

- `--namespace "AWS/RDS"` - CloudWatch metrics for RDS are in this namespace.
- `--metric-name "AuroraReplicaLag"` - the specific metric for Aurora replication lag.
- `--dimensions` - filter to a specific reader instance.
- `--start-time` / `--end-time` - the time range to query (last 10 minutes).
- `--period 60` - group data into 60-second intervals.
- `--statistics Average` - show the average lag per interval.

Expected output (yours will differ):
```
--------------------------------------
|       GetMetricStatistics          |
+-------------+---------------------+
|  AvgLagMs   |       Time          |
+-------------+---------------------+
|  18.234     |  2026-06-09T14:35:00Z |
|  15.789     |  2026-06-09T14:36:00Z |
|  21.456     |  2026-06-09T14:37:00Z |
+-------------+---------------------+
```

Lag values under 100 milliseconds are normal for Aurora. If you see lag over 1000 milliseconds consistently, investigate the writer's workload.

### Step 3 - Check Lag for the Second Reader

**In your terminal** (local machine):

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "AuroraReplicaLag" \
  --dimensions "Name=DBInstanceIdentifier,Value=devops-lab-reader-2" \
  --start-time "$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 60 \
  --statistics Average \
  --query "Datapoints | sort_by(@, &Timestamp) | [-3:].{Time:Timestamp,AvgLagMs:Average}" \
  --output table
```

Both readers should show similar lag values. If one reader consistently shows much higher lag than the other, it may be on a busier instance class or AZ.

---

## Part D - Understand Promotion Tiers

The `PromotionTier` controls which reader is promoted to writer during a failover. Lower tier numbers are promoted first.

### Step 1 - View Current Promotion Tiers

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,Tier:PromotionTier}" \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------
|              DescribeDBClusters                   |
+---------------------+----------+--------+
|      Instance       | IsWriter |  Tier  |
+---------------------+----------+--------+
|  devops-lab-writer-1|  True    |  1     |
|  devops-lab-reader-1|  False   |  1     |
|  devops-lab-reader-2|  False   |  1     |
+---------------------+----------+--------+
```

All instances are at tier 1. During a failover, Aurora would pick either reader (essentially random when tiers are equal).

### Step 2 - Set a Preferred Failover Target

If you want `devops-lab-reader-1` to be promoted first during a failover, set it to a lower tier.

**In your terminal** (local machine):

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --promotion-tier 0 \
  --apply-immediately
```

The `--promotion-tier 0` flag sets this instance as the highest priority for promotion. Valid values are 0 to 15, where 0 is the highest priority.

Now set the second reader to a lower priority:

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-reader-2 \
  --promotion-tier 2 \
  --apply-immediately
```

### Step 3 - Verify the New Tiers

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,Tier:PromotionTier}" \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------
|              DescribeDBClusters                   |
+---------------------+----------+--------+
|      Instance       | IsWriter |  Tier  |
+---------------------+----------+--------+
|  devops-lab-writer-1|  True    |  1     |
|  devops-lab-reader-1|  False   |  0     |
|  devops-lab-reader-2|  False   |  2     |
+---------------------+----------+--------+
```

Now during a failover:
- `devops-lab-reader-1` (tier 0) would be promoted first
- `devops-lab-reader-2` (tier 2) would only be promoted if reader-1 is unavailable

---

## Part E - Verify from the Writer Side

Let's confirm the writer can see all readers and their lag.

**In your terminal** (local machine):

```bash
WRITER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Endpoint" \
  --output text)
```

```bash
psql -h $WRITER_ENDPOINT -U labadmin -d labdb -p 5432
```

**In psql** (connected to writer endpoint):

```sql
SELECT server_id, is_current, replica_lag_in_msec
FROM aurora_replica_status()
ORDER BY server_id;
```

Expected output (yours will differ):
```
       server_id        | is_current | replica_lag_in_msec
------------------------+------------+--------------------
 devops-lab-reader-1    | f          |              12.345
 devops-lab-reader-2    | f          |              19.678
 devops-lab-writer-1    | t          |
(3 rows)
```

From the writer, you can see all three instances and the replication lag for each reader. The writer shows `is_current = t` and no lag.

Exit psql:

```sql
\q
```

---

## Summary

| What You Did | Result |
|-------------|--------|
| Added second reader | `devops-lab-reader-2` in a third AZ |
| Verified load-balancing | Reader endpoint rotates across both readers |
| Checked replication lag | `aurora_replica_status()` and CloudWatch AuroraReplicaLag |
| Configured promotion tiers | reader-1 at tier 0 (promoted first), reader-2 at tier 2 |
| Confirmed three-instance setup | 1 writer + 2 readers across 3 AZs |

### Key Numbers to Remember

| Metric | Healthy Value |
|--------|--------------|
| AuroraReplicaLag | Under 100 ms |
| Max readers per cluster | 15 |
| Promotion tier range | 0 (highest priority) to 15 (lowest) |
| Failover time | Under 30 seconds |

**Next:** [Build 06 - Cleanup and Cost Control](06-cleanup-and-cost-control.md).
