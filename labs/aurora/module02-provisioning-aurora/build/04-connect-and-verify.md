# Build 04 - Connect and Verify
## Module 02 - Provisioning Aurora (CLI + Console)

**Estimated time:** 20 minutes
**Difficulty:** Beginner
**Cost:** No additional cost (using your existing cluster)
**Prerequisite:** Build 02 complete (running Aurora cluster with writer and reader)

---

## What You Will Do

You will connect to both the writer and reader endpoints, verify which role each serves, test that writes are only accepted on the writer, and explore the Aurora-specific status functions. By the end you will:

- Know how to confirm which instance is the writer
- Know how to confirm which instance is the reader
- See that the reader refuses write operations
- Understand how to inspect endpoints via the CLI

---

## Before You Start

You need:
- Your Aurora cluster `devops-lab-cluster` running
- Your writer endpoint (cluster endpoint)
- Your reader endpoint
- psql installed
- Your master password for `labadmin`

If you do not have the endpoints saved, retrieve them now.

**In your terminal** (local machine):

```bash
WRITER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Endpoint" \
  --output text)
```

```bash
READER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].ReaderEndpoint" \
  --output text)
```

```bash
echo "Writer: $WRITER_ENDPOINT"
echo "Reader: $READER_ENDPOINT"
```

Expected output (yours will differ):
```
Writer: devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com
Reader: devops-lab-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com
```

---

## Part A - Connect to the Writer Endpoint

### Step 1 - Connect with psql

**In your terminal** (local machine):

```bash
psql -h $WRITER_ENDPOINT -U labadmin -d labdb -p 5432
```

Type your password when prompted.

### Step 2 - Verify This is the Writer

**In psql** (connected to writer endpoint):

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

`f` (false) means this instance is NOT in recovery mode. It is the primary - the writer. It accepts both reads and writes.

### Step 3 - Check the Server Address

**In psql** (connected to writer endpoint):

```sql
SELECT inet_server_addr();
```

Expected output (yours will differ):
```
 inet_server_addr
------------------
 10.0.1.45
(1 row)
```

This shows the private IP address of the instance you are connected to. Note this IP - you will compare it with the reader's IP in Part B.

### Step 4 - Check Aurora Replica Status

**In psql** (connected to writer endpoint):

```sql
SELECT server_id, session_id, is_current, replica_lag_in_msec
FROM aurora_replica_status();
```

Expected output (yours will differ):
```
       server_id        |            session_id            | is_current | replica_lag_in_msec
------------------------+----------------------------------+------------+--------------------
 devops-lab-writer-1    | aaaaaaaa-bbbb-cccc-dddd-eeeeeeee | t          |
 devops-lab-reader-1    | ffffffff-gggg-hhhh-iiii-jjjjjjjj | f          |              18.5
(2 rows)
```

What each column means:

- `server_id` - the instance identifier
- `session_id` - internal Aurora session ID
- `is_current` - `t` means you are currently connected to this instance
- `replica_lag_in_msec` - replication lag for readers (NULL for the writer because it does not replicate from anyone)

The writer shows `is_current = t` and no lag. The reader shows `is_current = f` and a small lag value (typically under 50 milliseconds).

### Step 5 - Write Some Data

**In psql** (connected to writer endpoint):

```sql
CREATE TABLE connection_test (
    id SERIAL PRIMARY KEY,
    endpoint_used TEXT NOT NULL,
    connected_at TIMESTAMPTZ DEFAULT NOW()
);
```

Expected output:
```
CREATE TABLE
```

```sql
INSERT INTO connection_test (endpoint_used) VALUES
    ('writer endpoint'),
    ('this data should appear on the reader too');
```

Expected output:
```
INSERT 0 2
```

```sql
SELECT * FROM connection_test;
```

Expected output (yours will differ):
```
 id |              endpoint_used               |          connected_at
----+------------------------------------------+-------------------------------
  1 | writer endpoint                          | 2026-06-09 14:30:01.123+00
  2 | this data should appear on the reader too| 2026-06-09 14:30:01.124+00
(2 rows)
```

Exit psql:

```sql
\q
```

---

## Part B - Connect to the Reader Endpoint

### Step 1 - Connect with psql

**In your terminal** (local machine):

```bash
psql -h $READER_ENDPOINT -U labadmin -d labdb -p 5432
```

Type your password when prompted.

### Step 2 - Verify This is a Reader

**In psql** (connected to reader endpoint):

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

`t` (true) means this instance IS in recovery mode. It is a replica - a reader. It accepts reads only.

### Step 3 - Check the Server Address

**In psql** (connected to reader endpoint):

```sql
SELECT inet_server_addr();
```

Expected output (yours will differ):
```
 inet_server_addr
------------------
 10.0.2.78
(1 row)
```

This is a different IP than the writer. Confirms you are on a different instance.

### Step 4 - Read the Data Written on the Writer

**In psql** (connected to reader endpoint):

```sql
SELECT * FROM connection_test;
```

Expected output (yours will differ):
```
 id |              endpoint_used               |          connected_at
----+------------------------------------------+-------------------------------
  1 | writer endpoint                          | 2026-06-09 14:30:01.123+00
  2 | this data should appear on the reader too| 2026-06-09 14:30:01.124+00
(2 rows)
```

The data you inserted on the writer is visible on the reader. Aurora's storage-level replication makes this available almost instantly (typically under 100 milliseconds).

### Step 5 - Try to Write on the Reader (Should Fail)

**In psql** (connected to reader endpoint):

```sql
INSERT INTO connection_test (endpoint_used) VALUES ('from reader - should fail');
```

Expected output:
```
ERROR:  cannot execute INSERT in a read-only transaction
```

This is correct behavior. The reader refuses all write operations. Try another write operation:

```sql
CREATE TABLE should_fail (id INT);
```

Expected output:
```
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

DDL is also refused on readers. Only SELECT queries work.

Exit psql:

```sql
\q
```

---

## Part C - Inspect Endpoints via CLI

### Step 1 - List All Endpoints for the Cluster

**In your terminal** (local machine):

```bash
aws rds describe-db-cluster-endpoints \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusterEndpoints[*].{Type:EndpointType,Endpoint:Endpoint,Status:Status}" \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------------------------------------
|                           DescribeDBClusterEndpoints                                   |
+------------+--------------------------------------------------------------+-----------+
|  Endpoint  |                                                              |  Status   |
|  Type      |                     Endpoint                                 |           |
+------------+--------------------------------------------------------------+-----------+
|  WRITER    | devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com| available |
|  READER    | devops-lab-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com| available |
+------------+--------------------------------------------------------------+-----------+
```

This shows the cluster-level endpoints. The `EndpointType` tells you which is for writes and which is for reads.

### Step 2 - Get Instance Endpoints with Roles

**In your terminal** (local machine):

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address,AZ:AvailabilityZone,Status:DBInstanceStatus}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------------------------------------------------
|                                   DescribeDBInstances                                         |
+------------+------------------------------------------------------------+------------+---------+
|     AZ     |                      Endpoint                              |     ID     | Status  |
+------------+------------------------------------------------------------+------------+---------+
| us-east-1a | devops-lab-writer-1.abc123.us-east-1.rds.amazonaws.com     | devops-lab-writer-1 | available |
| us-east-1b | devops-lab-reader-1.abc123.us-east-1.rds.amazonaws.com     | devops-lab-reader-1 | available |
+------------+------------------------------------------------------------+------------+---------+
```

### Step 3 - DNS Resolution of Endpoints

You can verify what IP address each endpoint resolves to.

**In your terminal** (local machine):

```bash
dig +short $WRITER_ENDPOINT
```

Expected output (yours will differ):
```
54.234.189.12
```

```bash
dig +short $READER_ENDPOINT
```

Expected output (yours will differ):
```
54.198.77.33
```

The writer and reader endpoints resolve to different IP addresses because they point to different instances. During a failover, these DNS records update automatically.

---

## Part D - Summary of What You Verified

| Check | Writer Endpoint | Reader Endpoint |
|-------|----------------|-----------------|
| `pg_is_in_recovery()` | `f` (false - primary) | `t` (true - replica) |
| `inet_server_addr()` | Private IP of writer instance | Private IP of reader instance |
| SELECT queries | Work | Work |
| INSERT/UPDATE/DELETE | Work | ERROR: read-only transaction |
| CREATE TABLE | Work | ERROR: read-only transaction |
| Replication lag | N/A (source of truth) | Typically < 100ms |

---

## Key Takeaways

1. **Always use the cluster (writer) endpoint for writes.** It automatically follows failovers.

2. **Use the reader endpoint for read-heavy queries.** It load-balances across all readers.

3. **Never hardcode instance endpoints in your application.** Instance endpoints do not follow failovers. Use them only for debugging and maintenance.

4. **`pg_is_in_recovery()` is the definitive check.** If it returns `false`, you are on the writer. If `true`, you are on a reader.

5. **`aurora_replica_status()` shows all instances.** It is Aurora-specific and shows replication lag for each reader.

**Next:** [Build 05 - Add Read Replicas](05-add-read-replicas.md).
