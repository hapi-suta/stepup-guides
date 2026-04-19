# Exercise 05 - Connection Saturation

**Time estimate:** 20-25 minutes
**Prerequisites:** BUILD phase complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb (pgbench data), postgres user, PGDATA at `/opt/pgsql/data`. Extensions installed: pg_buffercache, pageinspect, pgstattuple.

---

## Objective

Simulate connection exhaustion and understand its operational impact. By the end of this exercise, you should be able to diagnose a connection saturation event, identify which connections to kill, and clean up programmatically.

---

## Step 1 - Check Current Connection Limits

On **NODE1** (pg-primary), switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -d labdb
```

Query the connection settings:

```sql
SELECT
    current_setting('max_connections') AS max_connections,
    current_setting('superuser_reserved_connections') AS superuser_reserved,
    current_setting('max_connections')::int - current_setting('superuser_reserved_connections')::int AS available_for_normal_users;
```

**Expected:** With defaults, `max_connections = 100` and `superuser_reserved_connections = 3`, leaving 97 slots for normal users.

Now check how many connections are currently in use:

```sql
SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

**Expected:** A small number - likely just your current session showing as `active`.

> **Concept:** PostgreSQL allocates one backend process per connection. Each backend consumes memory (at minimum `work_mem` per sort/hash operation) and one of the limited `max_connections` slots. The `superuser_reserved_connections` setting holds back a few slots so that a superuser (like `postgres`) can always connect to diagnose problems even when all normal slots are full. This is your emergency escape hatch.

---

## Step 2 - Open Many Background Connections

Exit psql:

```sql
\q
```

```bash
exit
```

Open 20 background psql sessions using a loop. Each session runs `pg_sleep(600)` to stay alive for 10 minutes:

```bash
for i in $(seq 1 20); do psql -U postgres -d labdb -c "SELECT pg_sleep(600);" & done
```

This runs 20 psql commands in the background. Each one occupies a connection slot.

Wait a few seconds for all connections to establish, then verify:

```bash
sudo -iu postgres
```

```bash
psql -d labdb
```

```sql
SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

**Expected:** `total_connections` should be around 22 (20 sleeping sessions + your psql session + possibly one more).

---

## Step 3 - Monitor Connection Details

Examine each connection's state, wait event, and query:

```sql
SELECT
    pid,
    state,
    wait_event_type,
    wait_event,
    left(query, 40) AS query_snippet,
    backend_start,
    state_change
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY backend_start DESC;
```

**Expected:** The 20 sleeping sessions will show:
- `state = 'active'` (they are actively running pg_sleep)
- `wait_event_type = 'Timeout'`
- `wait_event = 'PgSleep'`
- `query_snippet` starts with `SELECT pg_sleep`

> **Concept:** The `wait_event_type` and `wait_event` columns tell you exactly what a backend is waiting on. Common types: `Lock` (waiting to acquire a lock), `IO` (waiting for disk I/O), `Client` (waiting for the client to send data), `Timeout` (sleeping or waiting for a timeout). When diagnosing connection problems, always check `wait_event` first - it tells you whether backends are doing useful work or just sitting there.

---

## Step 4 - Calculate Remaining Capacity

```sql
SELECT
    current_setting('max_connections')::int AS max_conn,
    (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') AS used,
    current_setting('max_connections')::int - (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') AS remaining,
    current_setting('superuser_reserved_connections')::int AS reserved_for_su;
```

**Expected:** Shows how many slots are still available. With 20 background connections plus your session, roughly 77 slots remain (from a default of 100).

> **Concept:** In production, connection exhaustion happens when application servers open connections faster than they close them. Common causes: connection pool misconfiguration, a slow query causing all pool connections to block, or a deploy that starts many new instances simultaneously. When `remaining` hits `superuser_reserved_connections`, normal users get "FATAL: too many connections" errors. Only superusers can still connect.

---

## Step 5 - Terminate Connections Programmatically

Identify and terminate all the sleeping test connections. Do NOT terminate your own session:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND query LIKE '%pg_sleep%'
  AND pid != pg_backend_pid();
```

**Expected:** Returns multiple rows, each with `t` (true), indicating each backend was terminated.

Verify the connections are gone:

```sql
SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

**Expected:** The count should drop back to a small number (just your session).

> **Concept:** `pg_terminate_backend` is the standard way to clean up unwanted connections. In a real incident, you would target specific criteria - longest-running queries, idle-in-transaction sessions, or connections from a specific application. The pattern `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE <criteria>` is a production-safe approach because it lets you filter precisely. Always exclude your own PID with `pid != pg_backend_pid()` to avoid terminating yourself.

---

## Step 6 - Clean Up Background Jobs

Exit psql and the postgres user:

```sql
\q
```

```bash
exit
```

Kill any remaining background shell jobs:

```bash
jobs -p | xargs kill 2>/dev/null
```

The `jobs -p` command lists PIDs of all background jobs. The `xargs kill` sends SIGTERM to each one. The `2>/dev/null` suppresses errors for jobs that already exited.

Verify no orphan connections remain:

```bash
sudo -iu postgres
```

```bash
psql -d labdb -c "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';"
```

**Expected:** Returns 1 (just this query's connection).

```bash
exit
```

---

## Step 7 - Think: Connection Pooling

In production, 100 `max_connections` is often not enough for modern applications with hundreds of microservice instances. But increasing `max_connections` to 1000 increases memory usage (each backend process uses 5-10MB at minimum) and context switching overhead.

The solution is a connection pooler like PgBouncer, which sits between the application and PostgreSQL:
- Applications open connections to PgBouncer (hundreds or thousands)
- PgBouncer maintains a small pool of real PostgreSQL connections (e.g., 50)
- Queries are multiplexed across the pool
- PostgreSQL only sees 50 backends, not 1000

This is beyond the scope of this exercise but critical knowledge for production PostgreSQL.

---

## Checkpoint

Before continuing, confirm:
- [ ] You checked `max_connections` and `superuser_reserved_connections` and calculated available slots
- [ ] You opened multiple background connections and observed them in `pg_stat_activity`
- [ ] You examined `wait_event_type` and `wait_event` for each connection
- [ ] You calculated remaining connection capacity during saturation
- [ ] You terminated connections programmatically with `pg_terminate_backend` and verified cleanup
- [ ] You understand why `superuser_reserved_connections` exists as an emergency escape hatch
- [ ] You know that connection pooling (PgBouncer) is the production solution for high connection counts

---

**Next:** [06 - Architecture Integration](06-architecture-integration.md)
