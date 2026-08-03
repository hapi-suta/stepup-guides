# USE 02 - Endpoint Routing Exercise
## Module 02: Provisioning Aurora

**Estimated time:** 40 minutes
**Type:** Hands-on exercise with a running cluster
**Prerequisite:** BUILD guides for Module 02 complete, running Aurora cluster with 1 writer + 2 readers

---

## Overview

Aurora gives you multiple endpoints. Each endpoint serves a different purpose. Using the wrong endpoint is one of the most common Aurora mistakes - it leads to read-only errors, unbalanced load, or connections hitting a single instance instead of spreading across readers.

In this exercise you will identify all endpoint types, test which instance each endpoint routes to, and verify read/write splitting behavior.

---

## Setup

You need a running Aurora PostgreSQL cluster with:
- 1 writer instance (`devops-lab-cluster-writer`)
- 2 reader instances (`devops-lab-cluster-reader-1`, `devops-lab-cluster-reader-2`)
- Cluster identifier: `devops-lab-cluster`

If your cluster does not have 2 readers yet, add them now:

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

Wait for all instances to be available before starting.

---

## Part 1 - Discover All Endpoints

### Task 1A - Find the Cluster Endpoints

Run this command to find the cluster-level endpoints:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint}" \
  --output table
```

Write down both endpoints.

### Task 1B - Find the Instance Endpoints

Run this command to find the individual instance endpoints:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address,AZ:AvailabilityZone}" \
  --output table
```

Fill in this table:

| Endpoint Type | URL | Purpose |
|--------------|-----|---------|
| Cluster endpoint (writer) | | All write operations |
| Reader endpoint (load-balanced) | | Read-only queries, balanced across readers |
| Writer instance endpoint | | Direct access to writer instance |
| Reader 1 instance endpoint | | Direct access to reader 1 |
| Reader 2 instance endpoint | | Direct access to reader 2 |

---

## Part 2 - Test Each Endpoint's Role

Connect to each of the five endpoints. For each one, run this query:

```sql
SELECT
    pg_is_in_recovery() AS is_reader,
    inet_server_addr() AS server_ip,
    current_database() AS database;
```

Fill in this table:

| Endpoint | pg_is_in_recovery() | inet_server_addr() | Role |
|----------|--------------------|--------------------|------|
| Cluster endpoint | | | writer / reader |
| Reader endpoint | | | writer / reader |
| Writer instance endpoint | | | writer / reader |
| Reader 1 instance endpoint | | | writer / reader |
| Reader 2 instance endpoint | | | writer / reader |

**Questions after filling in the table:**

1. `pg_is_in_recovery()` returns `f` for the writer and `t` for readers. Why is this function called "in recovery"?

<details>
<summary>Answer</summary>

In PostgreSQL terminology, a standby/replica is always "recovering" - it replays WAL (write-ahead log) records from the primary to stay up to date. Aurora readers do the same thing at the storage layer. The function name comes from PostgreSQL's internal architecture where replicas are in a permanent recovery state.

</details>

2. Connect to the reader endpoint three times in a row. Does `inet_server_addr()` always return the same IP?

<details>
<summary>Answer</summary>

No. The reader endpoint uses DNS round-robin to distribute connections across all reader instances. Each new connection may land on a different reader. This is how Aurora balances read traffic. However, DNS caching on your machine may cause consecutive connections to hit the same reader temporarily.

</details>

3. What happens if you try to INSERT data through the reader endpoint?

<details>
<summary>Answer</summary>

You get an error: `ERROR: cannot execute INSERT in a read-only transaction`. Reader instances reject all write operations. This is by design - readers serve read-only queries only.

</details>

---

## Part 3 - Test Write Behavior on Each Endpoint

### Task 3A - Write Through the Cluster Endpoint (Writer)

Connect to the cluster endpoint and insert data:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

```sql
CREATE TABLE IF NOT EXISTS endpoint_test (
    id SERIAL PRIMARY KEY,
    source TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO endpoint_test (source) VALUES ('cluster-endpoint');
SELECT * FROM endpoint_test;
\q
```

This should succeed. The cluster endpoint always routes to the writer.

### Task 3B - Attempt a Write Through the Reader Endpoint

Connect to the reader endpoint:

```bash
psql -h YOUR_READER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

Try to insert:

```sql
INSERT INTO endpoint_test (source) VALUES ('reader-endpoint');
```

Expected error:
```
ERROR:  cannot execute INSERT in a read-only transaction
```

Now verify you CAN read:

```sql
SELECT * FROM endpoint_test;
\q
```

This should show the row you inserted through the writer.

### Task 3C - Attempt a Write Through a Reader Instance Endpoint

Connect directly to reader-1's instance endpoint:

```bash
psql -h YOUR_READER_1_INSTANCE_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

```sql
INSERT INTO endpoint_test (source) VALUES ('reader-1-direct');
```

Expected: same read-only error as 3B.

```sql
\q
```

---

## Part 4 - Verify Reader Endpoint Load Distribution

### Task 4A - Connect Multiple Times and Track Where You Land

Run this loop to connect to the reader endpoint 10 times and see which server IP you get:

```bash
READER_EP="YOUR_READER_ENDPOINT"

for i in $(seq 1 10); do
  IP=$(psql -h "$READER_EP" -U clusteradmin -d devopsdb -p 5432 \
    -t -A -c "SELECT inet_server_addr()" 2>/dev/null)
  echo "Connection $i: $IP"
done
```

Expected output (yours will differ):
```
Connection 1: 10.0.1.45
Connection 2: 10.0.2.78
Connection 3: 10.0.1.45
Connection 4: 10.0.2.78
Connection 5: 10.0.1.45
...
```

You should see two different IPs alternating (one for each reader). If you see only one IP, DNS caching may be involved - wait a minute and try again.

### Task 4B - Answer These Questions

1. If you have 2 readers and the reader endpoint distributes connections, what happens when one reader is deleted?

<details>
<summary>Answer</summary>

The reader endpoint automatically stops routing to the deleted reader. All new connections go to the remaining reader. Existing connections to the deleted reader will be dropped. No application configuration change is needed.

</details>

2. If you add a third reader, do you need to update anything in your application?

<details>
<summary>Answer</summary>

No. The reader endpoint automatically includes the new reader in its DNS round-robin rotation. Your application keeps connecting to the same reader endpoint and Aurora handles the distribution.

</details>

3. A developer's application connects to the reader endpoint once at startup and reuses that connection for hours. Is load balancing happening?

<details>
<summary>Answer</summary>

No. Load balancing happens at connection time, not at query time. A single long-lived connection stays on the same reader for its entire lifetime. To get distribution, the application needs to open new connections periodically, or use a connection pool that rotates connections.

</details>

---

## Part 5 - Scenario-Based Endpoint Selection

For each scenario below, choose the correct endpoint and explain why.

### Scenario 1
The application needs to INSERT new orders into the `orders` table.

Which endpoint? ________________

<details>
<summary>Answer</summary>

**Cluster endpoint (writer)**. INSERT is a write operation. Only the writer accepts writes. The cluster endpoint always routes to the current writer, even after a failover.

</details>

### Scenario 2
An analytics dashboard runs hourly reports that scan millions of rows but never modify data.

Which endpoint? ________________

<details>
<summary>Answer</summary>

**Reader endpoint**. This is a read-only workload. Using the reader endpoint keeps the heavy analytics queries off the writer and distributes them across readers.

</details>

### Scenario 3
A monitoring script needs to check replication lag on a specific reader instance.

Which endpoint? ________________

<details>
<summary>Answer</summary>

**Reader instance endpoint (direct)**. You need to connect to a specific reader to check its replication lag. The load-balanced reader endpoint might send you to a different reader each time.

</details>

### Scenario 4
After a failover, the application needs to reconnect to the new writer.

Which endpoint? ________________

<details>
<summary>Answer</summary>

**Cluster endpoint (writer)**. The cluster endpoint DNS record is updated automatically during failover to point to the new writer. If your application uses the cluster endpoint, it reconnects to the correct writer without any configuration change. If it uses an instance endpoint, it would connect to the old writer (now a reader) and get read-only errors.

</details>

### Scenario 5
A batch job needs to write 1 million rows and then immediately read them back for validation.

Which endpoint? ________________

<details>
<summary>Answer</summary>

**Cluster endpoint (writer)** for both operations. Even though the read could go to a reader, there is a small replication delay. Reading from the writer guarantees you see the data you just wrote. This is called "read-after-write consistency."

</details>

---

## Cleanup

If you added readers specifically for this exercise, delete them:

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-2 \
  --skip-final-snapshot

aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-1 \
  --skip-final-snapshot
```

Drop the test table through the writer:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -c "DROP TABLE IF EXISTS endpoint_test;"
```

---

## Key Takeaways

- Aurora has 2 cluster endpoints (writer, reader) plus 1 instance endpoint per instance
- The cluster endpoint always routes to the current writer - use it for all writes
- The reader endpoint load-balances across readers using DNS round-robin
- Load balancing happens at connection time, not at query time
- After a failover, the cluster endpoint automatically points to the new writer
- Never hardcode instance endpoints in application code for write operations
- `pg_is_in_recovery()` is the definitive way to check if you are on a writer or reader
