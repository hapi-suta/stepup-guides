# Scenario 03 - Long-Running Idle Transaction

**Severity:** HIGH
**Expected Recovery Time:** 5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: A session is stuck in 'idle in transaction' state.
This session has been open for over 2 hours and is blocking
autovacuum and preventing VACUUM FULL from running on the orders table.
```

---

## Key Concepts for Revision

- **idle in transaction** - A session that ran `BEGIN` and then stopped sending queries is in `idle in transaction` state. The transaction is still open, holding any locks it acquired and blocking VACUUM from cleaning rows visible to its snapshot. Application bugs (crash without ROLLBACK, connection pooler misconfiguration) are the most common cause.

- **pg_stat_activity** - The view `pg_stat_activity` shows one row per backend process. Key columns: `pid`, `state` (active, idle, idle in transaction), `query_start`, `state_change`, `wait_event_type`, `wait_event`, `query`, `application_name`. Use `now() - state_change` to find how long a session has been in its current state.

- **Transaction age and VACUUM** - VACUUM cannot reclaim rows that are still potentially visible to the oldest active transaction. A long-running transaction forces PostgreSQL to keep old row versions alive across the entire database, not just the table the transaction touched.

- **pg_terminate_backend vs pg_cancel_backend** - `pg_cancel_backend(pid)` sends a signal that cancels the current query but keeps the connection alive. `pg_terminate_backend(pid)` terminates the entire backend process, rolling back any in-progress transaction and closing the connection. Use cancel first; terminate if cancel does not work.

- **idle_in_transaction_session_timeout** - This GUC automatically terminates sessions that are idle-in-transaction for longer than the specified interval. Set it to a reasonable value (e.g., `idle_in_transaction_session_timeout = '10min'`) in `postgresql.conf` to prevent this class of problem automatically.

---

## Diagnostic Steps

### Step 1 - Find all idle-in-transaction sessions

Log in and connect:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Query for sessions stuck in transaction:

```sql
SELECT pid, usename, application_name, state,
       now() - state_change AS idle_duration,
       left(query, 80) AS last_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_duration DESC;
```

Expected output (yours will differ):

```
  pid  | usename  | application_name |       state        | idle_duration | last_query
-------+----------+------------------+--------------------+---------------+-----------
 12345 | postgres | psql             | idle in transaction| 00:02:15      | SELECT * FROM orders LIMIT 1;
(1 row)
```

Note the `pid`. The `idle_duration` shows how long it has been sitting open.

### Step 2 - Check if the session holds any locks

```sql
SELECT l.pid, l.locktype, l.relation::regclass, l.mode, l.granted
FROM pg_locks l
WHERE l.pid = 12345;
```

Replace `12345` with the actual PID from Step 1.

Expected output (yours will differ):

```
  pid  |   locktype    | relation |      mode       | granted
-------+---------------+----------+-----------------+---------
 12345 | relation      | orders   | AccessShareLock | t
(1 row)
```

### Step 3 - Identify what the session was doing

```sql
SELECT pid, query, state, backend_start, state_change
FROM pg_stat_activity
WHERE pid = 12345;
```

---

## Resolution

### Step 1 - Cancel the query first (gentle approach)

Try to cancel just the current query:

```sql
SELECT pg_cancel_backend(12345);
```

Expected output:

```
 pg_cancel_backend
-------------------
 t
(1 row)
```

Wait a few seconds and check if the session is still idle-in-transaction:

```sql
SELECT pid, state FROM pg_stat_activity WHERE pid = 12345;
```

If the session is still stuck (or `pg_cancel_backend` returned false), proceed to terminate.

### Step 2 - Terminate the backend

```sql
SELECT pg_terminate_backend(12345);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

### Step 3 - Verify the session is gone

```sql
SELECT pid, state FROM pg_stat_activity WHERE state = 'idle in transaction';
```

Expected output:

```
 pid | state
-----+-------
(0 rows)
```

### Step 4 - Set idle_in_transaction_session_timeout to prevent recurrence

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '10min';
```

```sql
SELECT pg_reload_conf();
```

Verify:

```sql
SHOW idle_in_transaction_session_timeout;
```

Expected output:

```
 idle_in_transaction_session_timeout
--------------------------------------
 10min
(1 row)
```

```sql
\q
```

```bash
exit
```

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- No sessions in `idle in transaction` state
- `idle_in_transaction_session_timeout` is set to a non-zero value

---

## Interview Discussion Points

1. **A session is idle in transaction for 30 minutes. What is the risk of just leaving it?** - The session holds its transaction snapshot, preventing VACUUM from reclaiming dead tuples visible to that snapshot. If the session also holds row locks, any other query trying to update or lock those rows is blocked. The longer it sits, the more bloat accumulates and the more work VACUUM will need to catch up.

2. **How would you prevent idle-in-transaction sessions in a web application?** - Set `idle_in_transaction_session_timeout` in PostgreSQL. Configure statement timeouts in the application. Use a connection pooler (PgBouncer) that enforces transaction-mode pooling, which resets sessions between transactions. Instrument the application to log uncommitted transactions older than X seconds.

3. **What is the difference between pg_cancel_backend and pg_terminate_backend?** - `pg_cancel_backend` sends `SIGINT` to the backend - it cancels the current query but keeps the connection. The session can issue more queries. `pg_terminate_backend` sends `SIGTERM`, which rolls back the current transaction and closes the connection entirely. Use cancel for a running query you want to stop; use terminate for a completely stuck session.

4. **How does an idle-in-transaction session affect XID wraparound?** - The session's transaction XID is frozen at its start time. PostgreSQL cannot advance the `xmin` horizon past that XID, which means rows that should be considered ancient are kept alive. If the server approaches transaction ID wraparound (2 billion XIDs), emergency autovacuum kicks in and can cause significant performance impact.

5. **You need to terminate backends but you do not know the correct PIDs. How do you find all long-running transactions?** - Use `SELECT pid FROM pg_stat_activity WHERE now() - state_change > interval '10 minutes' AND state = 'idle in transaction';`. This finds all sessions that have been idle-in-transaction for more than 10 minutes. You can terminate all of them in one statement: `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE now() - state_change > interval '10 minutes' AND state = 'idle in transaction';`.
