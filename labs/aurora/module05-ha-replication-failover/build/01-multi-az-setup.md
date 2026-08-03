# BUILD 01 - Multi-AZ Setup: Configure and Verify AZ Placement
## Estimated Time: 35 minutes

---

## What You Will Do

1. Create an Aurora PostgreSQL cluster with instances in multiple AZs
2. Verify each instance is in a different Availability Zone
3. Examine the cluster endpoints
4. Confirm the shared storage model is active

> **Cost warning:** Running an Aurora cluster with 1 writer and 1 reader (db.t3.medium) costs approximately $0.14/hr. Delete resources when done.

---

## Before You Start

You need:
- AWS CLI v2 configured: `aws configure`
- A VPC with subnets in at least 2 different AZs
- A DB subnet group covering those subnets
- A security group that allows PostgreSQL traffic (port 5432)
- psql installed on your machine or an EC2 instance

---

## Step 1 - Create the Aurora Cluster

**In your terminal:**

Create the cluster first. This creates the logical cluster with shared storage - no compute instances yet.

```bash
aws rds create-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-subnet-group-name my-subnet-group \
  --vpc-security-group-ids sg-0abc123456789 \
  --region us-east-1
```

`--db-cluster-identifier` - the name for your Aurora cluster. You will use this in every command.
`--engine aurora-postgresql` - Aurora PostgreSQL. Use `aurora-mysql` for MySQL.
`--engine-version 16.6` - PostgreSQL 16.6. Use the latest version available.
`--db-subnet-group-name` - replace with your actual subnet group name.
`--vpc-security-group-ids` - replace with your actual security group ID.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "Status": "creating",
        "Engine": "aurora-postgresql",
        "EngineVersion": "16.6",
        "StorageEncrypted": true,
        ...
    }
}
```

Wait for the cluster status to become "available" (about 2-3 minutes):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].Status' \
  --output text \
  --region us-east-1
```

---

## Step 2 - Add the Writer Instance

**In your terminal:**

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-writer \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --availability-zone us-east-1a \
  --region us-east-1
```

`--db-instance-identifier` - the name for this specific instance.
`--db-cluster-identifier` - links this instance to the cluster you just created.
`--db-instance-class db.t3.medium` - Aurora requires at least db.t3.medium (no db.t3.micro support).
`--availability-zone us-east-1a` - place the writer in AZ a.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-writer",
        "DBInstanceStatus": "creating",
        "DBClusterIdentifier": "devops-lab-cluster",
        "AvailabilityZone": "us-east-1a",
        ...
    }
}
```

This takes 8-15 minutes. Wait for the instance to become "available."

---

## Step 3 - Add a Reader in a Different AZ

**In your terminal:**

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --availability-zone us-east-1b \
  --promotion-tier 0 \
  --region us-east-1
```

`--availability-zone us-east-1b` - place the reader in a different AZ from the writer for resilience.
`--promotion-tier 0` - highest failover priority. This reader will be promoted first if the writer fails.

Wait for this instance to become available (8-15 minutes).

---

## Step 4 - Verify AZ Placement

**In your terminal:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,AZ:AvailabilityZone,Class:DBInstanceClass}' \
  --output table \
  --region us-east-1
```

`--filters Name=db-cluster-id` - filter instances by cluster ID instead of listing all instances in your account.

Expected output (yours will differ):
```
--------------------------------------------------------------
|                    DescribeDBInstances                      |
+-----------+---------------------+-----------+---------------+
| AZ        | Class               | Instance  | Status        |
+-----------+---------------------+-----------+---------------+
| us-east-1a| db.t3.medium        | devops-lab-writer   | available |
| us-east-1b| db.t3.medium        | devops-lab-reader-1 | available |
+-----------+---------------------+-----------+---------------+
```

Confirm:
- The writer is in us-east-1a
- The reader is in us-east-1b
- Both are in "available" status
- Both are db.t3.medium

This is your Multi-AZ setup. If us-east-1a has an outage, Aurora promotes the reader in us-east-1b to writer within 20-35 seconds.

---

## Step 5 - Verify the Cluster Members and Roles

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter,Tier:PromotionTier}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------
|             DescribeDBClusters                     |
+---------------------+--------+--------------------+
| Instance            | Tier   | Writer             |
+---------------------+--------+--------------------+
| devops-lab-writer   | 1      | True               |
| devops-lab-reader-1 | 0      | False              |
+---------------------+--------+--------------------+
```

`IsClusterWriter: True` confirms devops-lab-writer is the current writer.
`PromotionTier: 0` on devops-lab-reader-1 means it has the highest failover priority.

---

## Step 6 - Examine the Cluster Endpoints

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
----------------------------------------------------------------------
|                       DescribeDBClusters                           |
+--------+------------------------------------------------------------+
| Reader | devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com |
| Writer | devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com    |
+--------+------------------------------------------------------------+
```

Note both endpoints. You will use:
- The **Writer** endpoint for all writes and critical reads
- The **Reader** endpoint for read-only queries

---

## Step 7 - Connect and Verify

**In your terminal:**

Connect to the writer endpoint:

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Replace `xxxx` with your actual cluster identifier from Step 6.

**In psql:**

Verify you are on the writer:

```sql
SELECT
    pg_is_in_recovery() AS is_replica,
    inet_server_addr() AS server_ip,
    aurora_version() AS aurora_ver;
```

`pg_is_in_recovery()` - returns `f` (false) on the writer, `t` (true) on a reader.
`inet_server_addr()` - shows the IP address of the server you are connected to.
`aurora_version()` - Aurora-specific function. Only exists on Aurora, not standard RDS.

Expected output (yours will differ):
```
 is_replica | server_ip  | aurora_ver
------------+------------+------------
 f          | 10.0.1.23  | 3.07.1
(1 row)
```

`is_replica = f` confirms you are on the writer.

Exit psql:

```sql
\q
```

---

## Step 8 - Connect to the Reader and Verify

**In your terminal:**

```bash
psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
SELECT
    pg_is_in_recovery() AS is_replica,
    inet_server_addr() AS server_ip;
```

Expected output (yours will differ):
```
 is_replica | server_ip
------------+-----------
 t          | 10.0.2.45
(1 row)
```

`is_replica = t` confirms you are on the reader.

Try a write to confirm it is read-only:

```sql
CREATE TABLE test_write (id int);
```

Expected output:
```
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

This confirms the reader endpoint correctly routes to a read-only instance.

Exit psql:

```sql
\q
```

---

## Step 9 - Verify Shared Storage (No WAL Streaming)

**In your terminal:**

Connect to the writer:

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

Check for WAL streaming connections:

```sql
SELECT * FROM pg_stat_replication;
```

Expected output:
```
 pid | usesysid | usename | application_name | client_addr | ... | state | ...
-----+----------+---------+------------------+-------------+-----+-------+---
(0 rows)
```

Zero rows. This is expected on Aurora. In standard PostgreSQL with streaming replication, you would see rows here showing WAL being sent to replicas. Aurora does not use WAL streaming - replicas read from shared storage directly.

Exit psql:

```sql
\q
```

---

## Key Takeaways

1. Aurora Multi-AZ is achieved by placing instances in different Availability Zones
2. The writer and reader share the same storage - no separate EBS volumes
3. Failover priority (promotion tier 0-15) controls which reader becomes writer
4. `pg_stat_replication` shows no rows on Aurora because there is no WAL streaming
5. The cluster endpoint (writer) and reader endpoint are your application connection targets
6. Always use endpoint hostnames, never hardcoded IPs - IPs change during failover

---

## Clean Up

Keep the cluster running for BUILD 02. If you want to delete everything:

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --skip-final-snapshot \
  --region us-east-1

aws rds delete-db-instance \
  --db-instance-identifier devops-lab-writer \
  --skip-final-snapshot \
  --region us-east-1
```

Wait for both instances to be deleted, then:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --skip-final-snapshot \
  --region us-east-1
```

`--skip-final-snapshot` - skips the backup on deletion. Use only in lab environments.
