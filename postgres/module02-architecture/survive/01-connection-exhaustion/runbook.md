# Scenario 01 - Connection Exhaustion

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL connection pool exhausted.
Applications reporting 'FATAL: too many connections'.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **max_connections** - The maximum number of concurrent connections PostgreSQL will accept. Set in postgresql.conf. Requires a restart to change. Default is 100.
- **superuser_reserved_connections** - Slots reserved exclusively for superuser connections (default: 3). This is your lifeline when the pool is full - you can still connect as postgres to diagnose.
- **pg_stat_activity** - System view showing one row per server process (connection). Key columns: pid, state, query, client_addr, backend_start.
- **Connection states** - active (running query), idle (waiting for command), idle in transaction (in open transaction, not running query), disabled (tracking disabled).
- **pg_cancel_backend(pid) vs pg_terminate_backend(pid)** - cancel sends SIGINT (cancels current query, keeps connection). terminate sends SIGTERM (kills entire backend process and closes connection).
- **Connection pooling** - Tools like PgBouncer sit between apps and PostgreSQL, multiplexing many app connections onto fewer database connections. Essential for production.

---

## Diagnostic Steps

### Step 1 - Connect as superuser

Even when the pool is full, superuser_reserved_connections keeps slots open for the postgres user.

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb
```

### Step 2 - Check total connection count vs limit

```sql
SELECT count(*) AS active_connections,
       current_setting('max_connections') AS max_connections,
       current_setting('superuser_reserved_connections') AS reserved
FROM pg_stat_activity;
```

### Step 3 - Break down connections by state

```sql
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state
ORDER BY count(*) DESC;
```

### Step 4 - Identify the offending sessions

Look for the pg_sleep sessions consuming all connections.

```sql
SELECT pid, state, query, backend_start, client_addr
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY backend_start;
```

### Step 5 - Confirm pg_sleep sessions are the problem

```sql
SELECT count(*) AS sleep_sessions
FROM pg_stat_activity
WHERE query LIKE '%pg_sleep%';
```

---

## Resolution

### Step 1 - Terminate all pg_sleep sessions

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE query LIKE '%pg_sleep%'
  AND pid != pg_backend_pid();
```

### Step 2 - Verify connections dropped

Wait a moment, then check the count.

```sql
SELECT count(*) FROM pg_stat_activity;
```

### Step 3 - Test a new connection

Open a new terminal and verify you can connect normally.

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT 'connection works';"
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- Connection count is well below max_connections
- New psql connections succeed
- No pg_sleep sessions remain

---

## Interview Discussion Points

1. **When would you introduce PgBouncer?** - Any production system with more than a handful of application servers. PgBouncer can multiplex thousands of app connections onto 20-50 database connections. Transaction-mode pooling is the most common and most efficient.

2. **How do you set max_connections?** - It depends on available RAM. Each connection consumes roughly work_mem + temp_buffers + maintenance_work_mem (when doing maintenance). A rough starting point is 100-200 for most workloads, but with PgBouncer in front, you can often keep it at 50-100 and let the pooler handle bursts.

3. **What is superuser_reserved_connections for?** - It reserves connection slots (default 3) that only superusers can use. This guarantees you can always connect as postgres to diagnose and fix connection exhaustion, even when max_connections is fully consumed by application connections.

4. **pg_cancel_backend vs pg_terminate_backend - when to use which?** - Use cancel when you want to stop a runaway query but keep the connection alive (the app can retry). Use terminate when the session itself is the problem (leaked connection, stuck transaction, malicious session). Terminate is more aggressive - it kills the entire backend process.

5. **What happens if the OOM killer hits a PostgreSQL backend?** - PostgreSQL detects the lost child process and restarts all backends to ensure shared memory consistency. All active transactions are rolled back. This is why connection exhaustion plus high work_mem is especially dangerous.
