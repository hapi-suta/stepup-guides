# Runbook: Wrong Endpoint
## Survive Scenario 02

**What is being tested:** Your ability to diagnose and fix an application that is sending write operations to an Aurora reader endpoint instead of the writer endpoint.

**Why this matters:** Aurora has multiple endpoints. Using the wrong one is a common misconfiguration - especially during deployments, failovers, or when multiple environments exist. The application connects fine (no connection error), but all write operations fail. This is tricky because the "connection works but writes fail" pattern confuses developers who assume a connection problem.

**Symptom:** Application errors: "cannot execute INSERT in a read-only transaction"
**Severity:** High - all write operations fail, reads still work
**Time to resolve:** 5 to 10 minutes

---

## Your Starting Point

A developer deployed a new version of the application. The deployment updated the database config file. Now the application can read data but all write operations fail.

Application logs show:
```
ERROR: cannot execute INSERT in a read-only transaction
STATEMENT: INSERT INTO orders (customer_id, total) VALUES ($1, $2)
```

The config file is at `/tmp/devops-app-config.env`.
The app script is at `/tmp/devops-app-writer.sh`.

Try running the app script to see the error:
```bash
bash /tmp/devops-app-writer.sh
```

---

## Symptoms

You will observe these symptoms:

1. All INSERT, UPDATE, DELETE, and CREATE TABLE operations fail
2. SELECT queries work perfectly
3. The error message says "read-only transaction"
4. The application connects successfully (no connection timeout, no auth failure)
5. The database cluster shows `available` status

The key clue: reads work, writes fail. This means the application is connected to a reader instance.

---

## Diagnostic Steps

### Step 1 - Read the Application Config

Look at what endpoint the application is using:

```bash
cat /tmp/devops-app-config.env
```

Look at the `DB_HOST` value. Does it contain `cluster-ro` in the hostname?

**Hint:** Aurora reader endpoints contain `cluster-ro` in the hostname. Writer endpoints contain `cluster` (without the `-ro`).

### Step 2 - Identify the Endpoint Type

Check if the configured endpoint is the writer or reader:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint}" \
  --output table
```

Compare the `DB_HOST` value from the config to these two endpoints.

### Step 3 - Confirm by Connecting and Checking the Role

Connect to the endpoint from the config and check if it is a reader:

```bash
source /tmp/devops-app-config.env

psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -p "$DB_PORT"
```

```sql
SELECT pg_is_in_recovery();
```

**Hint:** `t` (true) means this is a reader. `f` (false) means this is the writer. If you see `t`, the application is connected to a reader - that is why writes fail.

```sql
\q
```

### Step 4 - Get the Correct Writer Endpoint

```bash
WRITER_EP=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Endpoint" \
  --output text)

echo "Correct writer endpoint: $WRITER_EP"
```

### Step 5 - Fix the Config File

Update the config to use the writer endpoint:

```bash
sed -i.bak "s|DB_HOST=.*|DB_HOST=${WRITER_EP}|" /tmp/devops-app-config.env
```

Verify the fix:

```bash
grep "^DB_HOST=" /tmp/devops-app-config.env
```

The hostname should NOT contain `cluster-ro`.

### Step 6 - Test the Fix

Run the app script again:

```bash
bash /tmp/devops-app-writer.sh
```

It should now succeed without the read-only error.

### Step 7 - Verify Writes Work

Connect to the writer and confirm:

```bash
source /tmp/devops-app-config.env

psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -p "$DB_PORT"
```

```sql
SELECT pg_is_in_recovery();
```

Expected: `f` (this is the writer).

```sql
CREATE TABLE IF NOT EXISTS endpoint_test (
    id SERIAL PRIMARY KEY,
    source TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO endpoint_test (source) VALUES ('fix-verified');
SELECT * FROM endpoint_test ORDER BY id DESC LIMIT 3;
\q
```

---

## Resolution Approach

1. Read the config to find the endpoint being used
2. Compare it to the cluster's writer and reader endpoints
3. If the config has the reader endpoint (`cluster-ro`), replace it with the writer endpoint
4. Test that writes now succeed

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | Application config pointed to the reader endpoint instead of the writer endpoint |
| Impact | All write operations failed. Reads continued to work normally. |
| Database status | Cluster was running fine the entire time |
| How to detect | "read-only transaction" errors + `pg_is_in_recovery()` returns true |
| Fix | Update config to use the cluster (writer) endpoint |
| Time to fix | Under 5 minutes once you know what to look for |

---

## Prevention

1. **Use environment variables for endpoints** - Store the writer and reader endpoints separately (e.g., `DB_WRITE_HOST` and `DB_READ_HOST`). This makes it obvious which endpoint is used for which purpose.

2. **Store endpoints in AWS Secrets Manager or SSM Parameter Store** - The application reads the endpoint at startup from a central source of truth. No config file to regenerate incorrectly.

3. **Validate in CI/CD** - Add a pipeline step that connects to the configured endpoint and runs `SELECT pg_is_in_recovery()`. If the write endpoint returns `t`, the pipeline should fail before deploying.

4. **Use connection wrappers** - Many ORMs and database drivers support Aurora-aware connection handling. For example, the AWS JDBC driver can automatically route reads and writes to the correct endpoint.

5. **Name endpoints clearly** - In config files and documentation, always label endpoints as "writer" or "reader" - not just "primary" or "database".

---

## Interview Questions

**Q1: An application is throwing "cannot execute INSERT in a read-only transaction" errors. The database is running fine. What do you check?**

Strong answer: The application is likely connected to a reader instance. I would check which endpoint the application is using and compare it to the cluster's writer endpoint. In Aurora, the writer endpoint uses `cluster-` prefix and the reader endpoint uses `cluster-ro-` prefix. I would also connect to the endpoint the app is using and run `SELECT pg_is_in_recovery()` - if it returns true, the app is on a reader.

**Q2: What is the difference between the Aurora cluster endpoint and the reader endpoint? When do you use each?**

Strong answer: The cluster endpoint always routes to the current writer instance - use it for all INSERT, UPDATE, DELETE, and DDL operations. The reader endpoint load-balances connections across all reader instances using DNS round-robin - use it for SELECT queries only. After a failover, the cluster endpoint automatically updates to point to the new writer. The reader endpoint automatically excludes any instance that becomes the writer.

**Q3: After a failover, your application starts getting read-only errors even though it was working before. The cluster endpoint has not changed. What happened?**

Strong answer: DNS caching. The application (or the OS, or a connection pool) cached the old IP address for the cluster endpoint. After failover, the cluster endpoint DNS record points to a different IP (the new writer), but the cached DNS entry still points to the old writer (now a reader). The fix is to reduce the DNS TTL, configure the connection pool to refresh DNS periodically, or restart the application to clear the cache.

---

## Key Terminology

| Term | Definition |
|------|-----------|
| Cluster endpoint | DNS name that always routes to the current Aurora writer instance |
| Reader endpoint | DNS name that load-balances connections across Aurora reader instances |
| Instance endpoint | DNS name for a specific Aurora instance (does not change with failover) |
| pg_is_in_recovery() | PostgreSQL function that returns true on a standby/reader and false on a primary/writer |
| Read-only transaction | A transaction that cannot modify data - enforced on Aurora readers |

---

## Red Flags

These are answers that would concern an interviewer:

- "I would just restart the database" - The database is fine. The problem is the endpoint configuration.
- "I would make the reader accept writes" - You cannot make an Aurora reader accept writes. It is read-only by design.
- "I would use the instance endpoint instead of the cluster endpoint" - Instance endpoints do not update during failover. Always use the cluster endpoint for writes.
- Not knowing the difference between `cluster-` and `cluster-ro-` endpoints

---

## Now Run the Validate Script

```bash
export CLUSTER_ID=devops-lab-cluster
export REGION=us-east-1
export PGPASSWORD=YourPassword
bash validate.sh
```
