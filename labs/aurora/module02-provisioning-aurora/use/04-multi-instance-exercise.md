# USE 04 - Multi-Instance Deployment Exercise
## Module 02: Provisioning Aurora

**Estimated time:** 50 minutes
**Type:** Hands-on exercise with requirements
**Prerequisite:** BUILD guides for Module 02 complete

---

## Overview

Production Aurora clusters run multiple instances across multiple Availability Zones. If one AZ goes down, instances in other AZs keep serving traffic. This exercise walks you through deploying a multi-instance cluster, verifying AZ placement, testing reader endpoint distribution, and setting up failover priority.

---

## Part 1 - Deploy a Multi-AZ Aurora Cluster

### Task 1A - Create the Cluster

If you do not already have a cluster running, create one:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --engine-version 16.4 \
  --master-username clusteradmin \
  --master-user-password "YourSecurePassword123!" \
  --database-name devopsdb \
  --db-subnet-group-name devops-lab-subnetgroup \
  --vpc-security-group-ids YOUR_SG_ID \
  --backup-retention-period 7 \
  --storage-encrypted \
  --no-deletion-protection
```

### Task 1B - Add the Writer Instance

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-cluster-writer \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --publicly-accessible
```

### Task 1C - Add Two Reader Instances

Add readers in different AZs. Aurora will automatically spread them across available AZs, but you can also specify:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-1 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --publicly-accessible

aws rds create-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-2 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --publicly-accessible
```

Wait for all three to become available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-writer

aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-reader-1

aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-reader-2
```

---

## Part 2 - Verify AZ Placement

### Task 2A - Check Which AZ Each Instance Is In

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{Instance:DBInstanceIdentifier,AZ:AvailabilityZone,Class:DBInstanceClass,Status:DBInstanceStatus}" \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------------------------
|                       DescribeDBInstances                          |
+-----------+------------------+-----------+-------------------------+
|    AZ     |      Class       | Instance  |        Status           |
+-----------+------------------+-----------+-------------------------+
| us-east-1a| db.r6g.large    | devops-lab-cluster-writer  | available |
| us-east-1b| db.r6g.large    | devops-lab-cluster-reader-1| available |
| us-east-1c| db.r6g.large    | devops-lab-cluster-reader-2| available |
+-----------+------------------+-----------+-------------------------+
```

Fill in this table with your actual results:

| Instance | Availability Zone | Instance Class |
|----------|------------------|----------------|
| writer | | |
| reader-1 | | |
| reader-2 | | |

### Task 2B - Answer These Questions

1. Are all three instances in different AZs? If yes, why is this important?

<details>
<summary>Answer</summary>

Ideally, yes - each instance should be in a different AZ. If an entire AZ goes down (rare but it happens), you lose only one instance. The other two instances in other AZs continue serving traffic. Aurora automatically promotes a reader to writer if the writer's AZ goes down.

</details>

2. If all three instances ended up in the same AZ, how would you fix this?

<details>
<summary>Answer</summary>

You would delete the readers and recreate them with the `--availability-zone` flag to specify a different AZ. For example:

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-1 \
  --db-cluster-identifier devops-lab-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --availability-zone us-east-1b \
  --publicly-accessible
```

</details>

---

## Part 3 - Verify Cluster Membership and Roles

### Task 3A - List Cluster Members

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,PromotionTier:PromotionTier}" \
  --output table
```

Expected output:
```
---------------------------------------------------------------
|                    DescribeDBClusters                        |
+----------------------------------+-----------+---------------+
|           Instance               | IsWriter  | PromotionTier |
+----------------------------------+-----------+---------------+
| devops-lab-cluster-writer        | True      | 1             |
| devops-lab-cluster-reader-1      | False     | 1             |
| devops-lab-cluster-reader-2      | False     | 1             |
+----------------------------------+-----------+---------------+
```

### Task 3B - Set Failover Priority

Set reader-1 as the preferred failover target (tier 0) and reader-2 as secondary (tier 2):

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-1 \
  --promotion-tier 0

aws rds modify-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-2 \
  --promotion-tier 2
```

Verify the change:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,PromotionTier:PromotionTier}" \
  --output table
```

**Questions:**

1. PromotionTier ranges from 0 to 15. What does tier 0 mean vs tier 15?

<details>
<summary>Answer</summary>

Tier 0 is the highest priority - this reader will be promoted to writer first during a failover. Tier 15 is the lowest priority - this reader will only be promoted if no readers with a lower tier number are available. If two readers have the same tier, Aurora picks the one with the larger instance class. If both are the same class, Aurora picks one at random.

</details>

2. Why would you set different promotion tiers for different readers?

<details>
<summary>Answer</summary>

You might have a reader dedicated to analytics that uses a different instance class or has custom parameter settings. You would not want that analytics reader to become the writer during a failover because it is optimized for reads, not writes. By setting it to a high promotion tier (like 15), you ensure it is the last to be promoted.

</details>

---

## Part 4 - Test Reader Endpoint Distribution

### Task 4A - Create Test Data

Connect to the writer and insert data:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

```sql
CREATE TABLE IF NOT EXISTS az_test (
    id SERIAL PRIMARY KEY,
    region TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO az_test (region)
SELECT 'us-east-1'
FROM generate_series(1, 500);

SELECT count(*) FROM az_test;
```

Expected output: `500`

```sql
\q
```

### Task 4B - Verify Data on Each Reader

Connect to each reader's instance endpoint and confirm the data replicated:

**Reader 1:**

```bash
psql -h YOUR_READER_1_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -c "SELECT count(*) FROM az_test;"
```

**Reader 2:**

```bash
psql -h YOUR_READER_2_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -c "SELECT count(*) FROM az_test;"
```

Both should return `500`.

### Task 4C - Measure Replication Lag on Each Reader

Connect to each reader and check lag:

```bash
psql -h YOUR_READER_1_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -t -A -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"

psql -h YOUR_READER_2_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -t -A -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"
```

Record the lag for each reader:

| Reader | Replication Lag |
|--------|----------------|
| reader-1 | |
| reader-2 | |

**Questions:**

1. Aurora's replication lag is typically under 20 milliseconds. Why is it so much faster than standard RDS read replicas?

<details>
<summary>Answer</summary>

Aurora uses a shared storage layer. The writer and all readers access the same underlying storage volume. When the writer writes data, readers see it almost instantly because they share the same storage - there is no need to ship WAL files across the network and replay them. Standard RDS replicas use asynchronous streaming replication, which involves network transfer and WAL replay, adding seconds of lag.

</details>

---

## Part 5 - Instance Class Mixing

### Task 5A - Check Current Instance Classes

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{Instance:DBInstanceIdentifier,Class:DBInstanceClass}" \
  --output table
```

### Task 5B - Answer These Questions

1. Can you mix instance classes in an Aurora cluster? For example, `db.r6g.large` for the writer and `db.r6g.xlarge` for a reader?

<details>
<summary>Answer</summary>

Yes. Each instance in an Aurora cluster can have a different instance class. This is useful when you want the writer to be smaller (if writes are light) and a reader to be larger (if it handles heavy analytics). However, be careful with failover - if a small reader gets promoted to writer, it may not handle the write workload.

</details>

2. You have a writer on `db.r6g.large` and a reader on `db.t3.medium`. The writer fails and the reader gets promoted. What problem might occur?

<details>
<summary>Answer</summary>

The `db.t3.medium` is a burstable instance with limited CPU credits and less memory than the `db.r6g.large`. Under the write workload, it may throttle (run out of CPU credits) or run out of memory. This causes slow queries, connection failures, and potentially an outage worse than the original failover. This is why the writer-candidate reader should always be the same size or larger than the current writer.

</details>

---

## Cleanup

Drop the test table:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -c "DROP TABLE IF EXISTS az_test;"
```

If you created the cluster specifically for this exercise, delete everything:

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-2 \
  --skip-final-snapshot

aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-1 \
  --skip-final-snapshot

aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-writer \
  --skip-final-snapshot

aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-reader-2

aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-reader-1

aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-writer

aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --skip-final-snapshot
```

---

## Key Takeaways

- Spread instances across multiple AZs for high availability
- Use `--availability-zone` to control placement if Aurora does not spread them automatically
- PromotionTier controls failover order: lower number = higher priority
- Readers share Aurora's storage layer - replication lag is typically under 20ms
- You can mix instance classes, but the failover target should match or exceed the writer's size
- Always verify AZ placement after adding instances - do not assume Aurora placed them optimally
