# BUILD 02 - Aurora PostgreSQL Cluster

## What You Will Build

By the end of this guide you will have a running Aurora PostgreSQL cluster with one writer and one reader instance. You will understand how Aurora differs from standard RDS, how its shared storage works, and how to use cluster endpoints.

---

## Prerequisites

- Completed BUILD 01 (subnet group and security group already created)
- AWS CLI v2 configured
- psql client installed

---

## Aurora vs Standard RDS

Before building, understand the key differences:

| Feature | Standard RDS | Aurora PostgreSQL |
|---------|-------------|-------------------|
| Storage | EBS volume per instance | Shared distributed storage |
| Max Storage | 64 TB | 128 TB |
| Replication | Async streaming | Storage-level (faster) |
| Replicas | Up to 5 | Up to 15 |
| Failover | 60-120 seconds | Usually under 30 seconds |
| Cost | Lower base cost | Higher base, but better at scale |
| Backtrack | Not available | Rewind to past point in time |

Aurora stores data across 6 copies in 3 AZs automatically. Replicas share the same storage volume - they do not need to stream WAL from the primary.

---

## Step 1 - Create an Aurora Cluster Parameter Group

Aurora has two types of parameter groups: cluster-level and instance-level. Cluster parameters apply to all instances. Instance parameters apply to individual instances.

Create the cluster parameter group:

```bash
aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name suta-aurora-pg15-cluster-params \
    --db-parameter-group-family aurora-postgresql15 \
    --description "Cluster params for SUTA Aurora PostgreSQL 15"
```

The `--db-parameter-group-family` for Aurora uses the prefix `aurora-postgresql` instead of just `postgres`.

Expected output (yours will differ):

```json
{
    "DBClusterParameterGroup": {
        "DBClusterParameterGroupName": "suta-aurora-pg15-cluster-params",
        "DBParameterGroupFamily": "aurora-postgresql15",
        "Description": "Cluster params for SUTA Aurora PostgreSQL 15"
    }
}
```

Set useful parameters on the cluster group:

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name suta-aurora-pg15-cluster-params \
    --parameters \
        "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
        "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate" \
        "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

These are the same parameters from BUILD 01. The `ApplyMethod` rules are identical.

---

## Step 2 - Create an Instance Parameter Group

This controls instance-specific settings:

```bash
aws rds create-db-parameter-group \
    --db-parameter-group-name suta-aurora-pg15-instance-params \
    --db-parameter-group-family aurora-postgresql15 \
    --description "Instance params for SUTA Aurora PostgreSQL 15"
```

Expected output (yours will differ):

```json
{
    "DBParameterGroup": {
        "DBParameterGroupName": "suta-aurora-pg15-instance-params",
        "DBParameterGroupFamily": "aurora-postgresql15",
        "Description": "Instance params for SUTA Aurora PostgreSQL 15"
    }
}
```

---

## Step 3 - Create the Aurora Cluster

The cluster is the logical container. It manages the shared storage and endpoints.

```bash
aws rds create-db-cluster \
    --db-cluster-identifier suta-aurora-pg-lab \
    --engine aurora-postgresql \
    --engine-version 15.4 \
    --master-username sutaadmin \
    --master-user-password 'ChangeMe-2024!' \
    --db-subnet-group-name suta-pg-subnet-group \
    --vpc-security-group-ids "${SG_ID}" \
    --db-cluster-parameter-group-name suta-aurora-pg15-cluster-params \
    --backup-retention-period 7 \
    --preferred-backup-window "03:00-04:00" \
    --preferred-maintenance-window "Sun:05:00-Sun:06:00" \
    --storage-encrypted \
    --copy-tags-to-snapshot \
    --tags Key=Environment,Value=lab Key=Project,Value=suta
```

Flag breakdown:
- `--db-cluster-identifier` - unique name for the Aurora cluster
- `--engine aurora-postgresql` - Aurora engine (not `postgres`)
- `--engine-version 15.4` - Aurora PostgreSQL version
- `--master-username` / `--master-user-password` - same as standard RDS
- `--db-subnet-group-name` - reuse the subnet group from BUILD 01
- `--vpc-security-group-ids` - reuse the security group from BUILD 01
- `--db-cluster-parameter-group-name` - the cluster parameter group from Step 1
- `--storage-encrypted` - encrypts all 6 copies of your data

Note: You do NOT specify `--allocated-storage` for Aurora. Storage is auto-managed and grows automatically from 10 GB up to 128 TB.

Expected output (yours will differ):

```json
{
    "DBCluster": {
        "DBClusterIdentifier": "suta-aurora-pg-lab",
        "Status": "creating",
        "Engine": "aurora-postgresql",
        "EngineVersion": "15.4",
        ...
    }
}
```

---

## Step 4 - Create the Writer Instance

The cluster alone has no compute. You need to add instances to it.

```bash
aws rds create-db-instance \
    --db-instance-identifier suta-aurora-pg-writer \
    --db-instance-class db.r6g.large \
    --engine aurora-postgresql \
    --db-cluster-identifier suta-aurora-pg-lab \
    --db-parameter-group-name suta-aurora-pg15-instance-params \
    --tags Key=Environment,Value=lab Key=Role,Value=writer
```

Flag breakdown:
- `--db-instance-identifier` - unique name for this specific instance
- `--db-instance-class db.r6g.large` - 2 vCPUs, 16 GB RAM (Graviton2 ARM)
- `--engine aurora-postgresql` - must match the cluster engine
- `--db-cluster-identifier` - attaches this instance to the cluster
- `--db-parameter-group-name` - instance-level parameter group from Step 2

Note: You do NOT specify storage, subnet group, or security group. Those come from the cluster.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "suta-aurora-pg-writer",
        "DBInstanceClass": "db.r6g.large",
        "DBInstanceStatus": "creating",
        ...
    }
}
```

Wait for the writer to become available:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-aurora-pg-writer
```

This polls every 30 seconds. Aurora instances typically take 5-10 minutes.

---

## Step 5 - Create a Reader Instance

```bash
aws rds create-db-instance \
    --db-instance-identifier suta-aurora-pg-reader1 \
    --db-instance-class db.r6g.large \
    --engine aurora-postgresql \
    --db-cluster-identifier suta-aurora-pg-lab \
    --db-parameter-group-name suta-aurora-pg15-instance-params \
    --tags Key=Environment,Value=lab Key=Role,Value=reader
```

Aurora automatically makes the first instance the writer and subsequent instances readers. The reader shares the same storage - no data copying occurs.

Wait for it:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-aurora-pg-reader1
```

---

## Step 6 - Understand Cluster Endpoints

Aurora provides multiple endpoints:

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier suta-aurora-pg-lab \
    --query "DBClusters[0].{WriterEndpoint:Endpoint,ReaderEndpoint:ReaderEndpoint,Port:Port}"
```

Expected output (yours will differ):

```json
{
    "WriterEndpoint": "suta-aurora-pg-lab.cluster-c9abcdef12gh.us-east-1.rds.amazonaws.com",
    "ReaderEndpoint": "suta-aurora-pg-lab.cluster-ro-c9abcdef12gh.us-east-1.rds.amazonaws.com",
    "Port": 5432
}
```

There are four endpoint types:

| Endpoint | DNS Pattern | Routes To |
|----------|-------------|-----------|
| Cluster (writer) | `*.cluster-*.rds.amazonaws.com` | Current writer instance |
| Reader | `*.cluster-ro-*.rds.amazonaws.com` | Load-balanced across readers |
| Instance | `<instance-id>.*.rds.amazonaws.com` | Specific instance |
| Custom | You define it | Subset of instances you choose |

**Always use the cluster endpoint for writes.** After a failover, the cluster endpoint automatically points to the new writer. If you hardcode an instance endpoint, your writes will break after failover.

**Use the reader endpoint for read queries.** It load-balances across all reader instances.

Save the endpoints:

```bash
WRITER_EP=$(aws rds describe-db-clusters --db-cluster-identifier suta-aurora-pg-lab --query "DBClusters[0].Endpoint" --output text)
```

```bash
READER_EP=$(aws rds describe-db-clusters --db-cluster-identifier suta-aurora-pg-lab --query "DBClusters[0].ReaderEndpoint" --output text)
```

---

## Step 7 - Connect to the Writer

```bash
psql -h "${WRITER_EP}" -U sutaadmin -d postgres -p 5432
```

Enter your password when prompted.

Expected output (yours will differ):

```
Password for user sutaadmin:
psql (15.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Create a test table and insert data:

```sql
CREATE TABLE endpoint_test (id serial PRIMARY KEY, source text, created_at timestamptz DEFAULT now());
```

```sql
INSERT INTO endpoint_test (source) VALUES ('writer');
```

```sql
SELECT * FROM endpoint_test;
```

Expected output:

```
 id | source |          created_at
----+--------+-------------------------------
  1 | writer | 2024-01-15 12:30:45.123456+00
(1 row)
```

Exit psql:

```sql
\q
```

---

## Step 8 - Connect to the Reader

```bash
psql -h "${READER_EP}" -U sutaadmin -d postgres -p 5432
```

Verify the data is visible (Aurora replication is nearly instant):

```sql
SELECT * FROM endpoint_test;
```

Expected output:

```
 id | source |          created_at
----+--------+-------------------------------
  1 | writer | 2024-01-15 12:30:45.123456+00
(1 row)
```

Try to write on the reader:

```sql
INSERT INTO endpoint_test (source) VALUES ('reader');
```

Expected output:

```
ERROR:  cannot execute INSERT in a read-only transaction
```

This confirms the reader is read-only. Exit psql:

```sql
\q
```

---

## Step 9 - Check Replication Status

List all instances in the cluster and their roles:

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier suta-aurora-pg-lab \
    --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}" \
    --output table
```

Expected output (yours will differ):

```
-----------------------------------------------
|            DescribeDBClusters               |
+---------------------------+-----------------+
|         Instance          |    IsWriter     |
+---------------------------+-----------------+
|  suta-aurora-pg-writer    |  True           |
|  suta-aurora-pg-reader1   |  False          |
+---------------------------+-----------------+
```

Check replication lag on the reader:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name AuroraReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=suta-aurora-pg-reader1 \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    --query "Datapoints | sort_by(@, &Timestamp) | [-1].Average"
```

This fetches the average AuroraReplicaLag over the last hour. Aurora typically shows lag under 20 milliseconds.

Expected output (yours will differ):

```
12.5
```

The value is in milliseconds. Under 100ms is healthy.

---

## Step 10 - Add Another Reader (Scaling Out)

```bash
aws rds create-db-instance \
    --db-instance-identifier suta-aurora-pg-reader2 \
    --db-instance-class db.r6g.large \
    --engine aurora-postgresql \
    --db-cluster-identifier suta-aurora-pg-lab \
    --db-parameter-group-name suta-aurora-pg15-instance-params \
    --tags Key=Environment,Value=lab Key=Role,Value=reader
```

Because Aurora uses shared storage, adding a reader does NOT copy any data. The new instance starts reading from the shared storage volume immediately. This is much faster than standard RDS read replicas.

---

## Step 11 - Remove a Reader (Scaling In)

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-aurora-pg-reader2 \
    --skip-final-snapshot
```

Removing a reader does NOT affect the storage or other instances. The `--skip-final-snapshot` flag is appropriate because the data still exists in the shared cluster storage.

---

## Step 12 - Check Storage Usage

Aurora auto-scales storage, but you can check current usage:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name VolumeBytesUsed \
    --dimensions Name=DBClusterIdentifier,Value=suta-aurora-pg-lab \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average \
    --query "Datapoints | sort_by(@, &Timestamp) | [-1].Average"
```

This metric is reported at the cluster level (not instance level). The value is in bytes.

---

## Summary

You created:
- Cluster and instance parameter groups for Aurora PostgreSQL 15
- An Aurora cluster with shared distributed storage
- A writer instance and a reader instance
- Verified writer/reader endpoint routing
- Confirmed read-only enforcement on readers
- Scaled out and in by adding/removing readers

Key takeaways:
- Aurora uses shared storage - replicas do not copy data
- Always use cluster endpoints, never instance endpoints in application code
- Adding/removing readers is fast because no data copying occurs
- Replication lag is typically under 20ms

---

## Clean Up (if needed)

Delete instances first, then the cluster:

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-aurora-pg-reader1 \
    --skip-final-snapshot
```

```bash
aws rds delete-db-instance \
    --db-instance-identifier suta-aurora-pg-writer \
    --skip-final-snapshot
```

Wait for both to be deleted, then delete the cluster:

```bash
aws rds delete-db-cluster \
    --db-cluster-identifier suta-aurora-pg-lab \
    --skip-final-snapshot
```

```bash
aws rds delete-db-cluster-parameter-group \
    --db-cluster-parameter-group-name suta-aurora-pg15-cluster-params
```

```bash
aws rds delete-db-parameter-group \
    --db-parameter-group-name suta-aurora-pg15-instance-params
```
