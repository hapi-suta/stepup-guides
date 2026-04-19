# Scenario 05 - Idle Connections Hogging All Slots

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Connection pool exhausted. New connections failing.
Many idle connections from app_user are holding all available slots.
The Pulse dashboard shows errors. New connections from the app cannot be established.
```

---

## Key Concepts for Revision

- **Idle connections are not free** - An idle connection still holds a backend process, a slot in the postmaster's process table, and shared memory. 90 idle connections consume nearly the same resources as 90 active connections. Applications that open connections and never close them cause this pattern.

- **pg_terminate_backend terminates a connection** - This sends SIGTERM to the backend process. The backend exits cleanly, the client sees a connection error, and the slot is freed. Use `pg_cancel_backend(pid)` to cancel only the current query while keeping the connection open.

- **Targeting idle connections** - Filter pg_stat_activity by `state = 'idle'` and `usename` to find the connections to terminate. Do not blindly terminate all connections - active queries will be aborted.

- **Prevention with idle_in_transaction_session_timeout** - Sets a timeout for connections that are idle inside a transaction. Does not affect purely idle connections. For purely idle connections, consider `tcp_keepalives_idle` at the OS level or application-side connection pool settings.

- **CONNECTION LIMIT per role** - After fixing the immediate problem, set `CONNECTION LIMIT` on the offending role to prevent recurrence. If the app only needs 10 connections, set `ALTER ROLE app_user CONNECTION LIMIT 10`.

---

## Diagnostic Steps

### Step 1 - Confirm the problem

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  sorry, too many clients already
```

### Step 2 - Connect as postgres via socket

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 3 - Count connections by state and user

```sql
SELECT usename, state, count(*) AS connection_count
FROM pg_stat_activity
GROUP BY usename, state
ORDER BY connection_count DESC;
```

Expected output (yours will differ):

```
  usename  | state  | connection_count
-----------+--------+-----------------
 app_user  | idle   |               85
 postgres  | active |                1
```

85 idle connections from app_user is clearly the problem.

### Step 4 - Check available connection slots

```sql
SELECT
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn,
  count(*) AS total_in_use,
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') - count(*) AS free_slots
FROM pg_stat_activity;
```

Expected output (yours will differ):

```
 max_conn | total_in_use | free_slots
----------+--------------+------------
      100 |           89 |         11
```

Only 11 slots free, with 3 reserved for superusers = 8 effectively available for the app.

---

## Resolution

### Step 1 - Terminate all idle connections from app_user

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE usename = 'app_user'
AND state = 'idle';
```

Expected output (yours will differ):

```
 count
-------
    85
(1 row)
```

### Step 2 - Verify connections are freed

```sql
SELECT usename, state, count(*) AS connection_count
FROM pg_stat_activity
GROUP BY usename, state
ORDER BY connection_count DESC;
```

Expected output (yours will differ):

```
  usename  | state  | connection_count
-----------+--------+-----------------
 postgres  | active |                1
```

All idle app_user connections are gone.

### Step 3 - Set a connection limit on app_user to prevent recurrence

```sql
ALTER ROLE app_user CONNECTION LIMIT 10;
```

Expected output:

```
ALTER ROLE
```

This prevents app_user from opening more than 10 simultaneous connections. If the application bug recurs, it will hit the role limit before exhausting the server limit.

### Step 4 - Set idle_in_transaction_session_timeout as an additional safeguard

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
```

```sql
SELECT pg_reload_conf();
```

This terminates connections that are idle inside a BEGIN/COMMIT block for more than 5 minutes. It does not affect purely idle connections, but adds a safety net for the common "transaction left open" pattern.

### Step 5 - Exit and verify app_user can connect

```bash
\q
```

```bash
exit
```

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT 1;"
```

Expected output:

```
 ?column?
----------
        1
(1 row)
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- app_user idle connection count is under 20
- app_user can connect via TCP
- app_user has a CONNECTION LIMIT set

---

## Interview Discussion Points

1. **How do you identify which application is causing connection leaks?** - Check `application_name` in pg_stat_activity. Applications should set this when connecting (e.g., `psql -A "application_name=PulseApp"`). Also check `client_addr` to identify which server is the source. The `backend_start` time shows when the connection was established.

2. **What is the difference between terminating and canceling a backend?** - `pg_cancel_backend(pid)` cancels the current query but leaves the connection open. The client gets an error and can retry. `pg_terminate_backend(pid)` closes the entire connection. The client must reconnect. Use cancel for long-running queries you want to stop gracefully; use terminate for stuck or zombie connections.

3. **How does a connection pooler like PgBouncer prevent this problem?** - PgBouncer maintains a fixed pool of real PostgreSQL connections (e.g., 20). Hundreds of application threads share these through the pooler. When a thread finishes its transaction, the connection is returned to the pool rather than held idle. PostgreSQL never sees more than 20 connections regardless of how many application threads are running.

4. **Can you set idle connection timeout in PostgreSQL (for non-transaction idle)?** - There is no built-in parameter for pure idle connection timeout in PostgreSQL itself. Options include: setting `tcp_keepalives_idle` to detect dead connections at the TCP level, using the application-side connection pool timeout settings, or writing a cron job that runs `pg_terminate_backend` on connections idle for too long. PgBouncer has a `server_idle_timeout` for this.

5. **Why would you terminate connections from the app role but not the postgres role?** - Because your own diagnostic session is running as postgres. If you terminated all connections indiscriminately, you would cut your own session. Always filter by `usename != current_user` or by the specific role causing the problem.
