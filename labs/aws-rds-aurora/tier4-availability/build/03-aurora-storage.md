# BUILD 03 - Aurora Storage Architecture: Observe and Compare
## Estimated Time: 30 minutes

---

## What You Will Do

1. Create an Aurora PostgreSQL cluster (if you do not have one)
2. Observe Aurora storage metrics in CloudWatch
3. Compare Aurora storage behavior to RDS EBS storage
4. Understand the 6-copy, 3-AZ replication model

---

## Before You Start

You need:
- AWS CLI v2 configured
- A VPC with at least 3 subnets in 3 different AZs
- A DB subnet group covering those subnets

> **Concept:** Aurora storage is fundamentally different from RDS. RDS uses EBS volumes attached to EC2 instances. Aurora uses a distributed, shared storage layer that lives outside of any individual instance.

---

## Step 1 - Create an Aurora PostgreSQL Cluster

### Console

1. Go to RDS -> Databases -> Create database
2. Choose "Standard create"
3. Engine: Aurora (PostgreSQL compatible)
4. Engine version: PostgreSQL 16.x (latest)
5. Templates: Dev/Test
6. DB cluster identifier: `my-aurora-cluster`
7. Master username: `postgres`
8. Master password: `YourPassword123`
9. DB instance class: db.t3.medium (smallest Aurora supports)
10. Availability and durability: "Aurora Replica in a different AZ" - SKIP for now (choose "Don't create an Aurora Replica")
11. VPC: your VPC
12. DB subnet group: your subnet group
13. Public access: No
14. Click "Create database"

### CLI

Create the cluster first:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-0abc123456789 \
  --region us-east-1
```

`--engine aurora-postgresql` - Aurora PostgreSQL. Use `aurora-mysql` for MySQL.
`--db-subnet-group-name` - replace with your actual subnet group name.
`--vpc-security-group-ids` - replace with your security group ID.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "my-aurora-cluster",
        "Status": "creating",
        "Engine": "aurora-postgresql",
        "EngineVersion": "16.6",
        "StorageEncrypted": true,
        ...
    }
}
```

Now add the writer instance to the cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-aurora-writer \
  --db-cluster-identifier my-aurora-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --region us-east-1
```

`--db-cluster-identifier` - links this instance to the cluster you just created.
`--db-instance-class db.t3.medium` - Aurora requires at least t3.medium (no t3.micro support).

Wait 8-15 minutes for the cluster and instance to become available.

---

## Step 2 - Explore the Cluster Storage (No Provisioning Needed)

### Console

1. Click your cluster `my-aurora-cluster`
2. Look at the "Configuration" tab
3. Notice: there is NO "Allocated storage" value shown
4. Notice: there is NO "Storage type" to choose

This is different from RDS. With RDS, you choose "20 GB gp3" at creation time. With Aurora, storage grows automatically.

### CLI

Describe the cluster:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].{Engine:Engine,Storage:AllocatedStorage,Encrypted:StorageEncrypted,ClusterVolume:ClusterScalabilityType}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------
|            DescribeDBClusters                |
+------------------+---------------------------+
| AllocatedStorage | 1                         |
| Encrypted        | True                      |
| Engine           | aurora-postgresql          |
+------------------+---------------------------+
```

The `AllocatedStorage` shows `1` - this is a placeholder. Aurora manages the actual storage internally.

---

## Step 3 - Connect and Check Aurora-Specific Storage Info

Get the cluster endpoint:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1
```

Connect:

```bash
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Run these queries to see Aurora storage-related information:

```sql
-- Check storage used by the current database
SELECT
    pg_database.datname AS database_name,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
ORDER BY pg_database_size(pg_database.datname) DESC;
```

Expected output:
```
 database_name | size
---------------+-------
 postgres      | 7657 kB
 rdsadmin      | 4753 kB
 template1     | 7513 kB
 template0     | 7369 kB
(4 rows)
```

```sql
-- Check if we are on Aurora (Aurora adds aurora_version())
SELECT aurora_version();
```

Expected output (yours will differ):
```
 aurora_version
----------------
 3.04.1
(1 row)
```

This function only exists on Aurora, not on standard RDS PostgreSQL.

```sql
-- Check replication status (no standby WAL receiver on Aurora writer)
SELECT * FROM pg_stat_replication;
```

Expected output:
```
 pid | usesysid | usename | application_name | client_addr | ... | state | ...
-----+----------+---------+------------------+-------------+-----+-------+---
(0 rows)
```

On standard PostgreSQL with streaming replication, you would see rows here showing the WAL streaming to replicas. Aurora does not use WAL streaming between instances. Replicas read from the shared storage layer directly - so `pg_stat_replication` shows no rows.

---

## Step 4 - Monitor Storage Metrics in CloudWatch

### Console

1. Go to CloudWatch -> Metrics -> RDS
2. Select "Per-Database Metrics"
3. Find your cluster identifier
4. Look for these metrics:
   - `AuroraVolumeBytesLeftTotal` - how much space is left
   - `VolumeBytesUsed` - how much space is in use
   - `VolumeWriteIOPs` - write operations per second to the storage layer
   - `VolumeReadIOPs` - read operations per second from the storage layer

### CLI - Check Storage Used

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions Name=DBClusterIdentifier,Value=my-aurora-cluster \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

`--metric-name VolumeBytesUsed` - total bytes used by the Aurora cluster volume.
`--dimensions Name=DBClusterIdentifier` - filter by cluster, not instance.
`--period 300` - one data point every 5 minutes.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2024-01-15T14:30:00Z",
            "Average": 22020096.0,
            "Unit": "Bytes"
        }
    ]
}
```

22020096 bytes = about 21 MB. A fresh Aurora cluster uses very little space.

---

## Step 5 - Load Data and Watch Storage Grow

Create a test table and load some data to see storage change:

```sql
CREATE TABLE storage_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO storage_test (data)
SELECT md5(random()::text)
FROM generate_series(1, 100000);
```

`generate_series(1, 100000)` - generates 100,000 rows in one INSERT. This is a quick way to load data.
`md5(random()::text)` - creates a random 32-character string for each row.

Expected output:
```
INSERT 0 100000
```

Check storage size again:

```sql
SELECT pg_size_pretty(pg_database_size('postgres'));
```

Expected output (yours will differ):
```
 pg_size_pretty
----------------
 19 MB
(1 row)
```

Wait 5 minutes, then check CloudWatch again - you will see `VolumeBytesUsed` has increased.

---

## Step 6 - Compare Aurora to RDS EBS Storage

This is a conceptual comparison. You do not need to run all commands if you do not have an RDS instance.

### RDS EBS Storage Characteristics

With RDS:
- You choose storage size upfront (e.g., 20 GB)
- If you run out, you must manually scale (or enable autoscaling)
- Autoscaling for RDS has a 6-hour cool-down between expansions
- Each instance has its own separate volume
- Primary and standby each have their own full copy

```bash
# On RDS, you see FreeStorageSpace decrease as data grows
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=my-postgres \
  --start-time 2024-01-15T14:00:00Z \
  --end-time 2024-01-15T15:00:00Z \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

### Aurora Storage Characteristics

With Aurora:
- No size to choose - starts at 10 GB, grows in 10 GB increments
- Growth is automatic and immediate
- You pay per GB used, not per GB provisioned
- All instances in the cluster share one volume
- 6 copies across 3 AZs always (you cannot reduce this)

```bash
# On Aurora, you see VolumeBytesUsed increase as data grows
# AuroraVolumeBytesLeftTotal shows remaining capacity (128 TB max)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraVolumeBytesLeftTotal \
  --dimensions Name=DBClusterIdentifier,Value=my-aurora-cluster \
  --start-time 2024-01-15T14:00:00Z \
  --end-time 2024-01-15T15:00:00Z \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

---

## Step 7 - Understand the 6-Copy Model in Practice

You cannot directly observe the 6 storage nodes from SQL. But you can verify the resilience by looking at Aurora's behavior during a storage node failure.

Run this query repeatedly while loading data:

```bash
# In one terminal - continuous writes
for i in $(seq 1 1000); do
  psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -c "INSERT INTO storage_test (data) VALUES (md5(random()::text));"
  sleep 0.1
done
```

In a real Aurora deployment, AWS can lose 2 of the 6 storage nodes without any interruption to your reads or writes. You would not see any errors. This is the value of the 6-copy model - it is transparent to you.

---

## Key Takeaways

1. Aurora storage is not EBS - it is a distributed, shared storage layer
2. You never provision storage size for Aurora - it grows automatically
3. Aurora maintains 6 copies across 3 AZs automatically - you cannot change this
4. Aurora writes only redo log records to storage (not full pages) - this makes writes faster
5. `pg_stat_replication` shows no rows on Aurora because replicas do not receive WAL streams
6. Use CloudWatch `VolumeBytesUsed` (not `FreeStorageSpace`) to monitor Aurora storage
7. Aurora storage cannot shrink - space is reclaimed internally but the volume size stays the same

---

## Clean Up

Keep the Aurora cluster running if you are continuing to BUILD 04. If you want to delete it:

```bash
# Delete the instance first
aws rds delete-db-instance \
  --db-instance-identifier my-aurora-writer \
  --skip-final-snapshot \
  --region us-east-1

# Wait for instance to be deleted, then delete the cluster
aws rds delete-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --skip-final-snapshot \
  --region us-east-1
```

`--skip-final-snapshot` - skips the backup snapshot on deletion. Use only in lab environments.
