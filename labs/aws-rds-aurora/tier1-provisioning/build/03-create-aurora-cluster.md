# Build 03 - Create an Aurora PostgreSQL Cluster
## Tier 1: Provisioning and Connectivity

**Estimated time:** 50 minutes
**Difficulty:** Beginner
**Cost:** ~$0.15 for this lab session (Aurora is more expensive than RDS)

---

## What You Will Do

You will create an Aurora PostgreSQL cluster with one writer and one reader. By the end you will:

- Have a running Aurora cluster with two instances
- Understand what each endpoint is for
- Connect to both endpoints and verify which role each one serves
- See how reads can be directed to the reader endpoint

---

## Before You Start

You need a security group and subnet group. If you completed Build 01 and kept those resources, use them. Otherwise, create them now using the CLI:

```bash
# Get your VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

echo "VPC ID: $VPC_ID"
```

```bash
# Get subnet IDs
aws ec2 describe-subnets \
  --filters "Name=vpcId,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" \
  --output text
```

Write down at least two subnet IDs from different Availability Zones.

```bash
# Get your public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "My IP: $MY_IP"
```

```bash
# Create subnet group (replace with your actual subnet IDs)
aws rds create-db-subnet-group \
  --db-subnet-group-name suta-aurora-lab-subnetgroup \
  --db-subnet-group-description "Subnet group for SUTA Aurora lab" \
  --subnet-ids subnet-0abc123 subnet-0def456 subnet-0ghi789
```

```bash
# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name suta-aurora-lab-sg \
  --description "Security group for SUTA Aurora lab" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text)

echo "Security Group ID: $SG_ID"
```

```bash
# Allow PostgreSQL from your IP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr $MY_IP/32
```

---

## Part A - Console Steps (Click-by-Click)

### Step 1 - Open RDS and Start Creating

1. Go to: https://console.aws.amazon.com
2. Search for `RDS` in the top bar and click it.
3. In the left sidebar, click **Databases**.
4. Click **Create database**.

### Step 2 - Choose Standard Create

1. Select **Standard create**.

### Step 3 - Choose Aurora

1. Under "Engine options", click **Amazon Aurora**.
2. Under "Edition", click **Amazon Aurora with PostgreSQL compatibility**.
3. Under "Engine version", leave the default. Aurora will show a version like `Aurora PostgreSQL 16.6`.

> **Concept:** Aurora PostgreSQL is not the same binary as standard PostgreSQL. It is a re-engineered engine that is wire-compatible with PostgreSQL. You connect to it with the same psql client and same drivers, but the internals are different.

### Step 4 - Choose a Template

1. Under "Templates", choose **Production** for this lab.

> We choose Production so you can see the full set of options. The free tier template hides Aurora options.

### Step 5 - Configure the Cluster

1. Under "DB cluster identifier", type: `suta-aurora-lab`
2. Under "Master username", type: `postgres`
3. Under "Credentials management", select **Self managed**.
4. Type and confirm a strong password.

### Step 6 - Configure the Writer Instance

1. Under "Cluster storage configuration", confirm it says **Aurora Standard**.
2. Under "DB instance class", select `db.t3.medium`.

> **Concept:** Aurora does not offer a db.t3.micro option for clusters because Aurora clusters always have at least two instances (writer + reader) and the t3.micro is too small for this setup. The smallest Aurora option is db.t3.medium.

### Step 7 - Availability and Durability

1. Under "Availability & durability", you will see "Create an Aurora Replica or Reader node in a different AZ".
2. Select **Create an Aurora Replica/Reader node in a different AZ (recommended for scaled availability)**.

This creates your reader instance automatically in a different AZ from your writer.

### Step 8 - Connectivity

1. Under "Compute resource", select **Don't connect to an EC2 compute resource**.
2. Under "VPC", leave the default.
3. Under "DB subnet group", select **suta-aurora-lab-subnetgroup** (or your subnet group).
4. Under "Public access", click **Yes**.
5. Under "VPC security group", click **Choose existing**.
6. Remove the default security group and select **suta-aurora-lab-sg**.

### Step 9 - Additional Configuration

1. Click the arrow next to **Additional configuration** to expand it.
2. Under "Initial database name", type: `labdb`
3. Under "Backup retention period", set to **1** day.

### Step 10 - Create

1. Scroll down and click **Create database**.
2. You will see a confirmation page. Click **View DB cluster details**.

### Step 11 - Wait for Both Instances

You will see the cluster `suta-aurora-lab` with two instances under it:

```
suta-aurora-lab          (cluster)
  suta-aurora-lab-instance-1    (writer)   <- Creating...
  suta-aurora-lab-instance-2    (reader)   <- Creating...
```

Wait 10 to 15 minutes until both instances show status **Available**.

### Step 12 - Note All Three Endpoints

Click on the cluster name (not an instance). Under "Connectivity & security", note:

1. **Writer endpoint** - for write operations. Example:
   `suta-aurora-lab.cluster-abc123.us-east-1.rds.amazonaws.com`

2. **Reader endpoint** - for read operations. Example:
   `suta-aurora-lab.cluster-ro-abc123.us-east-1.rds.amazonaws.com`

Also click on each instance to get:

3. **Writer instance endpoint**: `suta-aurora-lab-instance-1.abc123.us-east-1.rds.amazonaws.com`
4. **Reader instance endpoint**: `suta-aurora-lab-instance-2.abc123.us-east-1.rds.amazonaws.com`

Write all four endpoints down.

---

## Part B - AWS CLI Steps (Same Result)

### Step 1 - Create the Aurora Cluster

Replace `YOUR_SG_ID`, `YOUR_PASSWORD`, and subnet IDs with your actual values.

```bash
aws rds create-db-cluster \
  --db-cluster-identifier suta-aurora-lab \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YOUR_PASSWORD \
  --db-subnet-group-name suta-aurora-lab-subnetgroup \
  --vpc-security-group-ids YOUR_SG_ID \
  --database-name labdb \
  --backup-retention-period 1
```

What each flag does:
- `--db-cluster-identifier` - unique name for the cluster
- `--engine aurora-postgresql` - Aurora with PostgreSQL compatibility
- `--engine-version` - which PostgreSQL-compatible version to use
- `--master-username` - admin user for the cluster
- `--master-user-password` - admin password
- `--db-subnet-group-name` - which subnets Aurora can place instances in
- `--vpc-security-group-ids` - firewall rules for the cluster
- `--database-name` - creates an initial database inside the cluster
- `--backup-retention-period 1` - keep automated backups for 1 day

Expected output (truncated):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "suta-aurora-lab",
        "Status": "creating",
        "Engine": "aurora-postgresql",
        ...
    }
}
```

### Step 2 - Create the Writer Instance

```bash
aws rds create-db-instance \
  --db-instance-identifier suta-aurora-lab-writer \
  --db-cluster-identifier suta-aurora-lab \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible
```

What each flag does:
- `--db-instance-identifier` - name for this specific instance
- `--db-cluster-identifier` - which cluster this instance belongs to
- `--db-instance-class` - the server size for this instance
- `--engine aurora-postgresql` - must match the cluster engine
- `--publicly-accessible` - allow connections from outside the VPC

### Step 3 - Create the Reader Instance

```bash
aws rds create-db-instance \
  --db-instance-identifier suta-aurora-lab-reader \
  --db-cluster-identifier suta-aurora-lab \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --publicly-accessible
```

This is identical to the writer instance command except for the `--db-instance-identifier`. Aurora automatically assigns the reader role to the second instance.

### Step 4 - Wait for the Cluster to Be Available

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier suta-aurora-lab
```

This takes 10 to 15 minutes. The cursor sits still while waiting.

### Step 5 - Get All Endpoints

Get the cluster endpoints (writer and reader):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier suta-aurora-lab \
  --query "DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint,Port:Port}" \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------------------------------------------------------------
|                                         DescribeDBClusters                                             |
+------+-------------------------------------------+-------------------------------------------+
| Port |              Reader                       |              Writer                       |
+------+-------------------------------------------+-------------------------------------------+
| 5432 |  suta-aurora-lab.cluster-ro-abc.us-east-1.rds.amazonaws.com | suta-aurora-lab.cluster-abc.us-east-1.rds.amazonaws.com |
+------+-------------------------------------------+-------------------------------------------+
```

Get the instance endpoints:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=suta-aurora-lab" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address,Role:ReadReplicaSourceDBInstanceIdentifier}" \
  --output table
```

---

## Part C - Connecting and Verifying Roles

Now connect to each endpoint and verify which role it serves.

### Step 1 - Connect to the Writer Endpoint

Replace `YOUR_WRITER_ENDPOINT` with the cluster writer endpoint.

```bash
psql -h YOUR_WRITER_ENDPOINT -U postgres -d labdb -p 5432
```

Once connected, check if this is the primary (writer):

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

`f` (false) = this is the writer (primary). Not in recovery mode.

Also check the server address:

```sql
SELECT inet_server_addr();
```

This shows the private IP of the instance you are connected to.

Check the Aurora-specific role:

```sql
SELECT server_id, session_id, is_current, replica_lag_in_msec
FROM aurora_replica_status();
```

Expected output (yours will differ):
```
         server_id          | session_id | is_current | replica_lag_in_msec
----------------------------+------------+------------+--------------------
 suta-aurora-lab-writer     | ...        | t          |
 suta-aurora-lab-reader     | ...        | f          | 12.345
(2 rows)
```

Exit psql:
```sql
\q
```

### Step 2 - Connect to the Reader Endpoint

Replace `YOUR_READER_ENDPOINT` with the cluster reader endpoint.

```bash
psql -h YOUR_READER_ENDPOINT -U postgres -d labdb -p 5432
```

Once connected, check if this is a replica:

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

`t` (true) = this is the reader (replica). It is in recovery mode, meaning it is applying changes from the writer.

Try writing to the reader:

```sql
CREATE TABLE should_fail (id INT);
```

Expected output:
```
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

Good. The reader refuses writes. This is correct behavior.

Exit psql:
```sql
\q
```

### Step 3 - Write on Writer, Read on Reader

Connect to the writer and create some data:

```bash
psql -h YOUR_WRITER_ENDPOINT -U postgres -d labdb -p 5432
```

```sql
CREATE TABLE aurora_test (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    note TEXT
);

INSERT INTO aurora_test (note) VALUES
    ('written to writer endpoint'),
    ('replication should carry this to reader'),
    ('Aurora replication is storage-level - very fast');

SELECT * FROM aurora_test;
```

Expected output:
```
 id |          created_at           |                note
----+-------------------------------+----------------------------------------------------
  1 | 2025-01-15 15:00:01.123+00   | written to writer endpoint
  2 | 2025-01-15 15:00:01.124+00   | replication should carry this to reader
  3 | 2025-01-15 15:00:01.125+00   | Aurora replication is storage-level - very fast
(3 rows)
```

Exit psql:
```sql
\q
```

Now connect to the reader and check if the data is there:

```bash
psql -h YOUR_READER_ENDPOINT -U postgres -d labdb -p 5432
```

```sql
SELECT * FROM aurora_test;
```

Expected output (should appear almost immediately):
```
 id |          created_at           |                note
----+-------------------------------+----------------------------------------------------
  1 | 2025-01-15 15:00:01.123+00   | written to writer endpoint
  2 | 2025-01-15 15:00:01.124+00   | replication should carry this to reader
  3 | 2025-01-15 15:00:01.125+00   | Aurora replication is storage-level - very fast
(3 rows)
```

The data is visible on the reader. Aurora's storage-level replication is extremely fast - typically under 100 milliseconds.

Check replication lag:

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

Expected output:
```
 replication_lag
-----------------
 00:00:00.045
(1 row)
```

45 milliseconds lag. This is typical for Aurora.

> **Note:** `pg_last_xact_replay_timestamp()` can return NULL if no transactions have replayed yet on this reader since it started. If you see NULL, it does not mean replication is broken - it just means no WAL has been applied yet in this session. Aurora's preferred methods for checking lag are the `aurora_replica_status()` function (queried above) or the CloudWatch `AuroraReplicaLag` metric, both of which are more reliable on Aurora than this PostgreSQL-native function.

Exit psql:
```sql
\q
```

### Step 4 - Understand the Cluster Endpoint vs Reader Endpoint

The cluster (writer) endpoint always points to the current writer. If the writer fails and a reader is promoted, the cluster endpoint automatically updates to point to the new writer. This is one of the key advantages of Aurora over standard RDS.

```
Before failover:
  cluster endpoint -> Writer Instance A  (doing writes)
  reader endpoint  -> Reader Instance B  (doing reads)

During failover (writer fails):
  Aurora promotes Reader Instance B
  cluster endpoint -> Writer Instance B  (new writer!)
  reader endpoint  -> ... (no readers until a new one is added)

After failover:
  cluster endpoint -> Writer Instance B
  (optionally add a new reader)
```

Your applications should always connect to the cluster endpoint for writes, not the instance endpoint. The cluster endpoint is the stable address that survives failovers.

---

## Part D - Cluster Status and Monitoring

### Check Cluster Status via CLI

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier suta-aurora-lab \
  --query "DBClusters[0].{Status:Status,Members:DBClusterMembers}" \
  --output json
```

Expected output:
```json
{
    "Status": "available",
    "Members": [
        {
            "DBInstanceIdentifier": "suta-aurora-lab-writer",
            "IsClusterWriter": true,
            "DBClusterParameterGroupStatus": "in-sync",
            "PromotionTier": 1
        },
        {
            "DBInstanceIdentifier": "suta-aurora-lab-reader",
            "IsClusterWriter": false,
            "DBClusterParameterGroupStatus": "in-sync",
            "PromotionTier": 1
        }
    ]
}
```

Notice `IsClusterWriter: true` for the writer and `false` for the reader.

### Check the PromotionTier

The `PromotionTier` (1-15) controls which reader gets promoted to writer during a failover. Lower number = promoted first. If all readers have the same tier, Aurora picks one at random.

---

## Cleanup

Aurora is more expensive than RDS. Delete when done.

### Console cleanup

1. Go to RDS > Databases.
2. Click on each instance under `suta-aurora-lab` and delete it (no final snapshot needed for the lab).
3. Then delete the cluster `suta-aurora-lab`.

### CLI cleanup

Delete instances first, then the cluster:

```bash
aws rds delete-db-instance \
  --db-instance-identifier suta-aurora-lab-reader \
  --skip-final-snapshot
```

```bash
aws rds delete-db-instance \
  --db-instance-identifier suta-aurora-lab-writer \
  --skip-final-snapshot
```

Wait for instances to be deleted:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier suta-aurora-lab-reader
```

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier suta-aurora-lab-writer
```

Delete the cluster:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier suta-aurora-lab \
  --skip-final-snapshot
```

---

## Summary

| Concept | Key Point |
|---------|-----------|
| Cluster endpoint | Always points to the current writer. Use for writes. |
| Reader endpoint | Load-balances across all readers. Use for reads. |
| Instance endpoint | Points to one specific instance. Use for maintenance. |
| pg_is_in_recovery() | Returns false on writer, true on reader. |
| Aurora replication | Storage-level, typically < 100ms lag. |
| Writer | Accepts reads and writes. Only one per cluster. |
| Reader | Accepts reads only. Up to 15 per cluster. |

**Next:** Build 04 is a deep dive into connectivity - endpoints, subnet groups, security groups, and troubleshooting.
