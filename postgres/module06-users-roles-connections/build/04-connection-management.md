# Build 04 - Connection Management

**Module:** 06 - Users, Roles & Connections
**Node:** NODE1 only
**Time:** 25 minutes

---

## What You Will Learn

- How max_connections works and why it matters
- How to inspect active connections with pg_stat_activity
- How to identify and terminate idle connections
- How to set per-role connection limits
- The basics of connection pooling and why it is necessary

---

> **Concept: max_connections and shared memory**
> Each PostgreSQL connection requires a backend process and a chunk of shared memory. The `max_connections` parameter reserves memory at startup for the maximum number of simultaneous connections. Setting it too high wastes memory. Setting it too low causes connection failures for legitimate users. The sweet spot for most single-server setups is between 100 and 400. Above 500, you should be using a connection pooler (PgBouncer). Changing max_connections requires a full restart.

---

> **Concept: Idle connections are not free**
> An idle connection still holds a backend process, a slot in the process table, and shared memory resources. 100 idle connections consume roughly the same memory as 100 active connections. Applications that open connections and hold them idle are a major cause of connection exhaustion. Connection poolers solve this by multiplexing many application connections through a small number of actual PostgreSQL connections.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Check the current max_connections setting

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SHOW max_connections;
```

Expected output (yours will differ):

```
 max_connections
-----------------
 100
(1 row)
```

---

## Step 3 - Check how many connections are currently in use

```sql
SELECT count(*) FROM pg_stat_activity;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

---

## Step 4 - View all active connections

```sql
SELECT pid, usename, application_name, client_addr, state, wait_event_type, wait_event, query_start, state_change
FROM pg_stat_activity
ORDER BY state, query_start;
```

This is your primary tool for connection monitoring. Key columns:

- `pid` - OS process ID of the backend
- `usename` - role name that is connected
- `application_name` - set by the client application
- `client_addr` - source IP (NULL for local socket)
- `state` - `active`, `idle`, `idle in transaction`, `idle in transaction (aborted)`
- `wait_event_type` and `wait_event` - what the backend is waiting on (Lock, IO, Client, etc.)

Expected output (yours will differ):

```
  pid  | usename  | application_name | client_addr |        state        | ...
-------+----------+------------------+-------------+---------------------+----
 12345 | postgres | psql             |             | active              |
 12346 | app_user | PulseApp         | 10.0.0.5    | idle                |
 12347 | app_user | PulseApp         | 10.0.0.5    | idle                |
```

---

## Step 5 - Find long-running queries

```sql
SELECT pid, usename, now() - query_start AS query_duration, state, query
FROM pg_stat_activity
WHERE state = 'active'
AND query_start < now() - interval '1 minute'
ORDER BY query_duration DESC;
```

This finds queries that have been running for more than 1 minute. These are candidates for investigation or termination.

Expected output (yours will differ - may be empty if no long queries):

```
 pid | usename | query_duration | state | query
-----+---------+----------------+-------+-------
(0 rows)
```

---

## Step 6 - Find idle connections older than 10 minutes

```sql
SELECT pid, usename, application_name, state, state_change, now() - state_change AS idle_duration
FROM pg_stat_activity
WHERE state = 'idle'
AND state_change < now() - interval '10 minutes'
ORDER BY idle_duration DESC;
```

These are connections sitting idle and wasting slots.

---

## Step 7 - Terminate a specific backend

If you need to terminate a specific connection, use `pg_terminate_backend()`. This sends SIGTERM to the backend, which exits cleanly.

First get the pid of the connection you want to terminate:

```sql
SELECT pid FROM pg_stat_activity WHERE usename = 'app_user' AND state = 'idle' LIMIT 1;
```

Then terminate it (replace 12346 with the actual pid):

```sql
SELECT pg_terminate_backend(12346);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

`t` means the signal was sent successfully. `f` means the backend was already gone.

---

> **Concept: pg_cancel_backend vs pg_terminate_backend**
> `pg_cancel_backend(pid)` sends SIGINT, which cancels the current query but leaves the connection open. The client gets an error message and can retry. Use this for long-running queries you want to stop without disconnecting the user. `pg_terminate_backend(pid)` sends SIGTERM, which closes the connection entirely. Use this for stuck idle connections or connections you want to permanently remove.

---

## Step 8 - Terminate all idle connections from a specific user

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = 'app_user'
AND state = 'idle';
```

This terminates all idle connections from app_user at once. In production, be careful with blanket terminations - the app may reconnect immediately.

---

## Step 9 - Set idle connection timeout with idle_in_transaction_session_timeout

Connections stuck `idle in transaction` are especially dangerous - they hold locks. Set a timeout:

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
```

```sql
SELECT pg_reload_conf();
```

This terminates any connection that has been idle IN A TRANSACTION for more than 5 minutes. Regular idle connections are not affected by this setting.

Expected output for pg_reload_conf():

```
 pg_reload_conf
----------------
 t
(1 row)
```

---

## Step 10 - Set connection limit per role

```sql
ALTER ROLE app_user CONNECTION LIMIT 5;
```

This caps app_user at 5 simultaneous connections. If a 6th connection attempt comes in, PostgreSQL returns an error:

```
FATAL:  too many connections for role "app_user"
```

Expected output:

```
ALTER ROLE
```

---

## Step 11 - Check connection limits in pg_roles

```sql
SELECT rolname, rolconnlimit FROM pg_roles WHERE rolconnlimit != -1;
```

`-1` means unlimited. This shows only roles with an explicit limit.

Expected output:

```
  rolname | rolconnlimit
----------+--------------
 app_user |            5
(1 row)
```

---

## Step 12 - Check how close you are to max_connections

```sql
SELECT max_conn, used, reserved_for_superusers, max_conn - used - reserved_for_superusers AS available
FROM (
  SELECT setting::int AS max_conn FROM pg_settings WHERE name = 'max_connections'
) mc,
(
  SELECT count(*) AS used FROM pg_stat_activity
) ua,
(
  SELECT setting::int AS reserved_for_superusers FROM pg_settings WHERE name = 'superuser_reserved_connections'
) src;
```

Expected output (yours will differ):

```
 max_conn | used | reserved_for_superusers | available
----------+------+-------------------------+-----------
      100 |    5 |                       3 |        92
(1 row)
```

The `superuser_reserved_connections` parameter reserves slots that only superusers can use. This ensures you can always connect as postgres to diagnose problems even when max_connections is exhausted.

---

## Step 13 - Understand connection pooling (concept)

A connection pooler sits between your application and PostgreSQL. The application thinks it has many connections, but the pooler multiplexes them through fewer actual database connections.

```
App server 1 ---|
App server 2 ---| ---> PgBouncer ---> PostgreSQL (10 real connections)
App server 3 ---|
(100 app connections)
```

PgBouncer supports three modes:
- **Session mode** - one PostgreSQL connection per client session (like no pooler)
- **Transaction mode** - a PostgreSQL connection is borrowed for each transaction and returned to the pool after COMMIT/ROLLBACK (most efficient)
- **Statement mode** - connection returned after each statement (most restrictive, breaks multi-statement transactions)

For the Pulse app in this lab, the app connects directly. In production, PgBouncer or pgpool-II would sit in front.

---

## Step 14 - Exit

```bash
\q
```

```bash
exit
```

---

## Summary

Key commands for connection management:

| Task | Command |
|------|---------|
| View all connections | `SELECT * FROM pg_stat_activity;` |
| Find idle connections | `WHERE state = 'idle'` |
| Cancel a query | `SELECT pg_cancel_backend(pid);` |
| Kill a connection | `SELECT pg_terminate_backend(pid);` |
| Set role connection limit | `ALTER ROLE rolename CONNECTION LIMIT n;` |
| Set idle transaction timeout | `ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';` |

---

## Interview Discussion Points

1. **What is superuser_reserved_connections and why does it exist?** - It reserves a fixed number of connection slots that only superusers can use. If an application exhausts all connections and an operator cannot connect to diagnose the problem, the situation becomes unrecoverable without a restart. The reserved slots ensure you can always connect as postgres. Default is 3.

2. **How does pg_stat_activity differ from pg_stat_activity on a standby?** - On a standby, pg_stat_activity shows connections to the standby itself plus any walsender processes. Recovery-related backends (startup, walreceiver) appear there too. You can query it on both primary and standby.

3. **What is idle in transaction and why is it dangerous?** - A connection is `idle in transaction` when a transaction has been opened (BEGIN) but no COMMIT or ROLLBACK has been issued. During this time, any rows touched by the transaction have locks held. Other queries waiting for those locks will block indefinitely. An idle-in-transaction connection can cascade into widespread blocking across the application.

4. **When would you use pg_cancel_backend instead of pg_terminate_backend?** - pg_cancel_backend stops the current query but keeps the connection alive. The client sees an error and can retry. Use this when you want to stop a runaway query without forcing the application to reconnect (reconnect might cause extra load or disruption). Use pg_terminate_backend when you want the connection fully gone.

5. **How do you estimate the right max_connections value?** - A common guideline is to limit max_connections to 3-4x the number of CPU cores. Above that, context switching between PostgreSQL backend processes starts hurting throughput. The real answer depends on workload, but 200-400 with a connection pooler is a common production setup. Never set max_connections above 1000 without a compelling reason and careful memory planning.
