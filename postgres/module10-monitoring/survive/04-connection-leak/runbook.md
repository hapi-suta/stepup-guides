# Scenario 04 - Connection Leak

**Severity:** CRITICAL
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application reports "too many connections" errors.
New application connections are being refused.
max_connections is nearly exhausted.
```

---

## Key Concepts for Revision

- **max_connections** - The hard limit on simultaneous client connections. PostgreSQL reserves some of these for superusers (`superuser_reserved_connections`, default 3), so regular users can connect to `max_connections - 3`. When this limit is hit, new connection attempts fail immediately with `FATAL: sorry, too many clients already`.

- **Connection leaks** - A leak occurs when an application opens a connection and never closes it. Common causes: application crashed mid-request leaving connections open, missing `connection.close()` in application code, a misconfigured connection pool that creates more connections than it needs. Leaked connections are typically in `idle` or `idle in transaction` state.

- **pg_terminate_backend vs waiting** - In an emergency where connections must be freed immediately, `pg_terminate_backend` terminates sessions. This is disruptive to those specific sessions (their transactions are rolled back) but allows new connections to succeed. For idle connections, the rollback cost is zero.

- **Connection poolers** - The long-term fix for connection exhaustion is a connection pooler like PgBouncer or pgpool-II. These allow many application threads to share a small number of actual PostgreSQL connections. A typical production setup might have 1000 application threads sharing 20-50 actual PostgreSQL connections through PgBouncer.

---

## Diagnostic Steps

### Step 1 - Check connection count and limit

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT count(*) AS current,
       max_conn,
       round(count(*) * 100.0 / max_conn, 1) AS pct_used
FROM pg_stat_activity,
     (SELECT setting::int AS max_conn FROM pg_settings WHERE name = 'max_connections') mc
GROUP BY max_conn;
```

Expected output when broken (yours will differ):

```
 current | max_conn | pct_used
---------+----------+----------
      18 |       20 |     90.0
(1 row)
```

### Step 2 - Profile the connections

Find out who holds the connections.

```sql
SELECT usename, state, count(*), max(now() - state_change) AS max_idle_time
FROM pg_stat_activity
GROUP BY usename, state
ORDER BY count DESC;
```

Expected output (yours will differ):

```
  usename  |  state  | count |  max_idle_time
-----------+---------+-------+-----------------
 postgres  | active  |    15 | 00:02:14.123456
 postgres  | active  |     1 | 00:00:00.001234
(2 rows)
```

### Step 3 - Find the leaked connections

```sql
SELECT pid, usename, state, now() - state_change AS idle_time, left(query, 60)
FROM pg_stat_activity
WHERE query LIKE '%pg_sleep%'
   OR state = 'idle'
ORDER BY idle_time DESC;
```

Expected output (yours will differ):

```
  pid  | usename | state  |  idle_time  |         left
-------+---------+--------+-------------+-----------------------------
  3041 | postgres| active | 00:02:30.12 | SELECT pg_sleep(3600);
  3042 | postgres| active | 00:02:30.11 | SELECT pg_sleep(3600);
...
```

---

## Resolution

### Step 1 - Terminate the leaked connections

Collect the PIDs of the leaked connections into an array.

```sql
SELECT pid FROM pg_stat_activity WHERE query LIKE '%pg_sleep%';
```

Expected output (yours will differ):

```
  pid
-------
  3041
  3042
  3043
...
```

Terminate all of them at once.

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE query LIKE '%pg_sleep%';
```

Expected output (yours will differ):

```
 pg_terminate_backend
----------------------
 t
 t
 t
...
```

### Step 2 - Verify connection count dropped

```sql
SELECT count(*) FROM pg_stat_activity;
```

Expected output (yours will differ):

```
 count
-------
     3
(1 row)
```

### Step 3 - Confirm new connections are accepted

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT 'connection ok';"
```

Expected output:

```
 ?column?
--------------
 connection ok
(1 row)
```

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- PostgreSQL accepts new connections
- Connection count below 80% of max_connections
- Fewer than 16 connections (80% of 20)
- No leaked pg_sleep connections

---

## Interview Discussion Points

1. **How do you tell the difference between a connection leak and legitimate high load?** - Look at the `state` column and `query` text in `pg_stat_activity`. Legitimate load shows connections in `active` state running real application queries. A leak shows connections `idle` or `idle in transaction` with no recent activity (long `state_change` time). Also look at `application_name` - a well-configured app sets this to something identifiable, making it easy to trace leaked connections back to the specific service.

2. **Is it safe to terminate idle connections?** - Yes. An `idle` connection has no open transaction. Terminating it has no impact on data integrity - the client gets a connection error on their next query and must reconnect. `idle in transaction` is different: terminating it rolls back the open transaction, which may affect the application if it was mid-workflow. Always prefer terminating `idle` connections first.

3. **max_connections is a postmaster parameter - what does that mean for adding connections during an emergency?** - You cannot raise `max_connections` on a running server. A restart is required. During a live emergency, terminating idle connections is the only immediate relief. Permanently solving the problem requires either raising `max_connections` (with a restart) or deploying a connection pooler (which does not require a PostgreSQL restart).

4. **What is superuser_reserved_connections and why does it exist?** - PostgreSQL reserves `superuser_reserved_connections` (default 3) connections exclusively for superusers. When the non-reserved limit is exhausted, regular users get `too many clients`, but a postgres superuser can still connect to diagnose and fix the problem. Without this reservation, a connection leak could lock out the DBA along with the application.

5. **Walk through how PgBouncer helps with connection management.** - PgBouncer sits between the application and PostgreSQL. Applications connect to PgBouncer (which can accept thousands of connections). PgBouncer maintains a pool of actual PostgreSQL connections (typically 20-100). When an application query arrives, PgBouncer borrows a PostgreSQL connection from the pool, runs the query, then returns the connection to the pool. From PostgreSQL's view, it sees only the pooler connections, not the thousands of application connections. This dramatically reduces `max_connections` requirements.
