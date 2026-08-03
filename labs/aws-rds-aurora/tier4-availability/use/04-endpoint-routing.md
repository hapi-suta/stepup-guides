# USE 04 - Endpoint Routing: Send Traffic to the Right Place
## Apply What You Learned | Tier 4

---

## What You Will Practice

- Verifying application connections go to the correct endpoint
- Testing read/write splitting at the database connection level
- Configuring endpoint routing for different workload types
- Diagnosing routing mistakes

---

## The Routing Problem

Many applications connect to only one database endpoint. That is fine for small apps. But as you scale, you want:

- Writes -> Writer endpoint only
- Reads -> Reader endpoint (distributes load)
- Analytics -> Custom endpoint (isolated reader)

Sending all traffic to the writer wastes your readers. Sending writes to a reader causes errors.

---

## Exercise 1 - Verify Your Connection Is Going to the Right Place

**Part A - Test the Writer Endpoint**

Connect using the cluster (writer) endpoint:

```bash
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

Run this check:

```sql
SELECT
    inet_server_addr() AS server_ip,
    pg_is_in_recovery() AS is_replica,
    CASE
        WHEN pg_is_in_recovery() THEN 'READER (read-only)'
        ELSE 'WRITER (read-write)'
    END AS connection_type;
```

Expected output:
```
 server_ip  | is_replica | connection_type
------------+------------+--------------------
 10.0.1.23  | f          | WRITER (read-write)
```

`pg_is_in_recovery()` = false means you are on the writer.

**Part B - Test the Reader Endpoint**

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
SELECT
    inet_server_addr() AS server_ip,
    pg_is_in_recovery() AS is_replica,
    CASE
        WHEN pg_is_in_recovery() THEN 'READER (read-only)'
        ELSE 'WRITER (read-write)'
    END AS connection_type;
```

Expected output:
```
 server_ip  | is_replica | connection_type
------------+------------+--------------------
 10.0.2.45  | t          | READER (read-only)
```

---

## Exercise 2 - Confirm Write Operations Fail on the Reader

On the reader endpoint connection:

```sql
-- This should FAIL
CREATE TABLE test_routing (id INT);
```

Expected output:
```
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

```sql
-- This should also FAIL
INSERT INTO lag_test (payload) VALUES ('test');
```

Expected output:
```
ERROR:  cannot execute INSERT in a read-only transaction
```

This confirms your application will get an error if it accidentally sends writes to the reader endpoint.

---

## Exercise 3 - Test Connection Pooling with Multiple Sessions

Simulate multiple application workers connecting through the reader endpoint:

```bash
for i in 1 2 3 4 5 6; do
  psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -t -c "SELECT $i AS worker, inet_server_addr() AS connected_to;" &
done
wait
```

`&` - runs each psql command in the background simultaneously.
`wait` - waits for all background jobs to finish before showing results.

Expected output (yours will differ):
```
 worker | connected_to
--------+--------------
 1      | 10.0.2.45
 2      | 10.0.3.67
 3      | 10.0.2.45
 4      | 10.0.3.67
 5      | 10.0.2.45
 6      | 10.0.3.67
```

Workers alternate between two reader IPs - this is DNS round-robin load balancing working.

**Question 1:** If you have 6 application workers and 2 readers, how are connections distributed? Is this always perfectly even?

---

## Exercise 4 - Routing Diagnostic Queries

These queries help you understand where traffic is going. Run them on the writer.

Check all active connections and their state:

```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    LEFT(query, 50) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start DESC;
```

Check connections by application name:

```sql
SELECT
    application_name,
    COUNT(*) AS connection_count,
    STRING_AGG(DISTINCT state, ', ') AS states
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY application_name
ORDER BY connection_count DESC;
```

**Question 2:** How can you tell from `pg_stat_activity` which connections came through the reader endpoint vs the writer endpoint?

> Note: You cannot directly see which endpoint was used. You can infer it from `client_addr` - connections on reader instances came through the reader endpoint.

---

## Exercise 5 - Custom Endpoint Routing for Analytics

Create the analytics custom endpoint (if you deleted it in BUILD 05):

```bash
aws rds create-db-cluster-endpoint \
  --db-cluster-identifier my-aurora-cluster \
  --db-cluster-endpoint-identifier analytics-endpoint \
  --endpoint-type READER \
  --static-members my-aurora-reader-2 \
  --region us-east-1
```

Get the endpoint URL:

```bash
aws rds describe-db-cluster-endpoints \
  --db-cluster-identifier my-aurora-cluster \
  --filters Name=db-cluster-endpoint-type,Values=CUSTOM \
  --query 'DBClusterEndpoints[0].Endpoint' \
  --output text \
  --region us-east-1
```

Connect to the analytics endpoint and run a "heavy" query:

```bash
psql -h analytics-endpoint.cluster-custom-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
-- Simulate a heavy analytics query
EXPLAIN ANALYZE
SELECT
    DATE_TRUNC('hour', created_at) AS hour,
    COUNT(*) AS inserts,
    AVG(length(payload)) AS avg_payload_size
FROM lag_test
GROUP BY hour
ORDER BY hour;
```

While this runs, check what is happening on the reader used for OLTP (the reader endpoint):

```sql
-- On a separate reader connection
SELECT pid, state, LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE state != 'idle';
```

**Question 3:** Does the heavy analytics query appear on the OLTP reader? Why not?

---

## Exercise 6 - Simulate a Routing Bug and Fix It

**The Bug:** An application developer hardcoded the instance endpoint instead of the cluster endpoint. This breaks silently after failover.

Connect using an instance endpoint:

```bash
# Get instance endpoints
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=my-aurora-cluster \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,Endpoint:Endpoint.Address,Writer:MultiAZ}' \
  --output table \
  --region us-east-1
```

Connect using the writer's INSTANCE endpoint (not the cluster endpoint):

```bash
psql -h my-aurora-writer.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT inet_server_addr();"
```

This works right now. But trigger a failover:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --region us-east-1
```

After failover, try connecting again using the same instance endpoint:

```bash
psql -h my-aurora-writer.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT pg_is_in_recovery();"
```

Expected output:
```
 pg_is_in_recovery
-------------------
 t
```

You are now on a READER. The endpoint still resolves (the instance still exists), but it is no longer the writer. Any writes will fail.

**Question 4:** How would you find hardcoded instance endpoints in application code? What should all application connections use instead?

---

## Exercise 7 - Read-Your-Writes Pattern

Some applications need to read their own writes immediately. This is a classic problem with read replicas.

**Scenario:** A user updates their profile. The app writes to the writer, then reads the profile to show a confirmation page. If it reads from the replica, it might get the old data.

**Solution 1: Use the writer for post-write reads**

```bash
# After writing, read from the writer endpoint
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
BEGIN;
UPDATE lag_test SET payload = 'UPDATED' WHERE id = 1;
SELECT * FROM lag_test WHERE id = 1;  -- reads from writer, gets fresh data
COMMIT;
```

**Solution 2: Read from reader but wait for lag to clear**

```sql
-- On the reader
SELECT pg_sleep(0.1);  -- brief wait for lag
SELECT * FROM lag_test WHERE id = 1;
```

This is fragile. Do not use in production.

**Solution 3: Use Aurora's session-level consistency (best practice)**

Aurora supports `aurora_replica_read_consistency` which lets you choose consistency level per session:

```sql
-- On the reader endpoint
SET aurora_replica_read_consistency = 'SESSION';
```

With `SESSION` consistency, reads from the reader reflect writes made in the same session. This avoids reading stale data without routing all reads to the writer.

**Question 5:** What is the trade-off of using `aurora_replica_read_consistency = 'SESSION'` vs simply routing all reads to the writer?

---

## Reference: Endpoint Cheat Sheet

| Use Case | Endpoint to Use | Why |
|----------|----------------|-----|
| Application writes | Cluster (writer) endpoint | Always points to current writer |
| Application reads | Reader endpoint | Load balances across all readers |
| Analytics/BI queries | Custom endpoint (dedicated large reader) | Isolation from OLTP reads |
| DBA diagnostics | Instance endpoint | Target a specific instance |
| Serverless secondary writes | Secondary cluster endpoint + write forwarding | Routes writes to primary |

---

## Answer Guide

**Q1:** 6 workers, 2 readers = each reader gets ~3 connections on average. DNS round-robin is not guaranteed to be perfectly even - it depends on DNS TTL and connection timing.

**Q2:** You cannot directly see the endpoint from `pg_stat_activity`. You can only see `client_addr` (the client's IP). To know which endpoint they used, you must track it in application logs or use connection pool labels (`application_name` parameter).

**Q3:** The analytics query runs only on `my-aurora-reader-2` (the custom endpoint's target). The OLTP reader (`my-aurora-reader-1`) is not involved. This is the isolation benefit of custom endpoints.

**Q4:** Search code for `rds.amazonaws.com` and check if the hostname includes an instance name (e.g., `my-aurora-writer.xxxx.`) vs a cluster endpoint format (e.g., `my-aurora-cluster.cluster-xxxx.`). All application connections should use the cluster endpoint or reader endpoint, never instance endpoints.

**Q5:** `SESSION` consistency adds a small latency penalty (the reader must confirm it has replayed up to a certain LSN before serving the read). The writer endpoint has zero latency but adds load to the writer. For most workloads, routing writes to the writer and using `SESSION` consistency for read-after-write is the best balance.
