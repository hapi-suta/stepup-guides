# Guide 04 - Wait Events and Locks

Learn to identify what PostgreSQL processes are waiting for, understand lock types, and resolve lock contention before it becomes an outage.

**Run all commands on:** NODE1

---

## Overview

When a query is slow and you cannot find a bad execution plan, the problem is often a lock. One session holds a lock and another is blocked waiting for it. PostgreSQL exposes this through `pg_stat_activity` wait events and the `pg_locks` view.

By the end of this guide you will know:
- What wait event categories mean
- The most common lock types and when they conflict
- How to find the blocking session and the blocked sessions
- How to resolve a lock situation safely

---

## Section 1 - Connect

SSH into NODE1.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

Switch to the postgres user.

```
sudo -iu postgres
```

Open a psql session.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Section 2 - Wait Events in pg_stat_activity

Every process in `pg_stat_activity` has two wait event columns:

- `wait_event_type` - the category of what is being waited on
- `wait_event` - the specific thing being waited on

### 2.1 - See current wait events

```sql
SELECT pid, usename, state, wait_event_type, wait_event, left(query, 60) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY wait_event_type NULLS LAST;
```

Expected output (yours will differ):

```
  pid  | usename  | state  | wait_event_type | wait_event  |          query_snippet
-------+----------+--------+-----------------+-------------+--------------------------
   412 | postgres | active |                 |             | SELECT pid, usename ...
  1042 | app_user | active | Lock            | relation    | UPDATE orders SET ...
(2 rows)
```

### 2.2 - Key wait event types

| wait_event_type | Meaning |
|---|---|
| (NULL) | Not waiting - actively running on CPU |
| `Lock` | Waiting to acquire a lock held by another session |
| `LWLock` | Waiting on an internal lightweight lock (usually transient) |
| `IO` | Waiting for disk I/O (reading/writing blocks) |
| `Client` | Waiting for the client to send data |
| `IPC` | Waiting for another backend to complete (e.g., WAL flush) |
| `Timeout` | Waiting for a timer (e.g., `pg_sleep`) |

> **Concept - Wait Events vs Slow Queries**: A query with a long `duration` in the logs is not always doing slow work - it might be waiting. If pg_stat_activity shows `wait_event_type = Lock`, the query is blocked on a lock, not executing. The fix is to find and resolve the lock, not to optimize the query.

---

## Section 3 - Lock Types

PostgreSQL uses different lock levels depending on what operation is being performed. Some locks conflict with each other; others do not.

### The most common lock types:

| Lock Mode | Acquired by | Conflicts with |
|---|---|---|
| `AccessShareLock` | `SELECT` | Only `AccessExclusiveLock` |
| `RowShareLock` | `SELECT FOR UPDATE/SHARE` | `ExclusiveLock`, `AccessExclusiveLock` |
| `RowExclusiveLock` | `INSERT`, `UPDATE`, `DELETE` | `ShareLock`, `ShareRowExclusiveLock`, `ExclusiveLock`, `AccessExclusiveLock` |
| `ShareUpdateExclusiveLock` | `VACUUM`, `ANALYZE`, `CREATE INDEX CONCURRENTLY` | Itself and stronger |
| `ShareLock` | `CREATE INDEX` (non-concurrent) | `RowExclusiveLock` and stronger |
| `ExclusiveLock` | Certain system operations | Most other locks |
| `AccessExclusiveLock` | `ALTER TABLE`, `DROP TABLE`, `TRUNCATE`, `LOCK TABLE` | Everything |

The practical takeaway: `SELECT` barely conflicts with anything. `ALTER TABLE` conflicts with everything and will be blocked by even a long-running `SELECT`.

> **Concept - AccessExclusiveLock and ALTER TABLE**: When you run `ALTER TABLE`, PostgreSQL must acquire `AccessExclusiveLock` on the table. This lock conflicts with every other lock, including `AccessShareLock` from simple `SELECT` statements. If there are any long-running queries on that table, the `ALTER TABLE` will wait. And while it waits, it blocks all new queries behind it too - because lock requests are queued. One `ALTER TABLE` waiting on one slow query can cascade into hundreds of blocked connections.

---

## Section 4 - Create a Lock Scenario

You need two psql sessions to demonstrate a lock. Open a second terminal window and SSH to NODE1 again, then switch to postgres.

In your first terminal (Session 1), start a transaction that holds a lock:

```sql
BEGIN;
```

```sql
UPDATE orders SET status = 'processing' WHERE order_id = 1;
```

Expected output:

```
UPDATE 1
```

Do NOT commit yet. Leave this transaction open.

In your second terminal (Session 2), try to update the same row:

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 1;
```

This command will hang - it is blocked waiting for Session 1's lock to be released.

---

## Section 5 - Find the Blocking Session

Open a third terminal window and SSH to NODE1 as ec2-user, then switch to postgres. Run the lock detection query.

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocked.query AS blocked_query,
    blocker.pid AS blocker_pid,
    blocker.usename AS blocker_user,
    blocker.query AS blocker_query,
    blocker.state AS blocker_state,
    now() - blocker.query_start AS blocker_duration
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocker
    ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Expected output (yours will differ):

```
 blocked_pid | blocked_user |          blocked_query           | blocker_pid | blocker_user |         blocker_query          | blocker_state | blocker_duration
-------------+--------------+----------------------------------+-------------+--------------+--------------------------------+---------------+-----------------
        2841 | postgres     | UPDATE orders SET status = 'sh.. |        2812 | postgres     | UPDATE orders SET status = 'pr | idle in trans | 00:01:23.412
(1 row)
```

(`pg_blocking_pids(pid)` = returns an array of PIDs blocking the given PID. This is the cleanest way to find the blocker-blocked relationship in PostgreSQL 9.6+.)

---

## Section 6 - Inspect pg_locks Directly

For more detail on what locks are held and requested:

```sql
SELECT
    l.pid,
    l.locktype,
    l.relation::regclass AS table_name,
    l.mode,
    l.granted,
    a.state,
    a.usename
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.relation IS NOT NULL
  AND l.locktype = 'relation'
ORDER BY l.granted, l.pid;
```

Expected output (yours will differ):

```
  pid  | locktype | table_name | mode            | granted | state           | usename
-------+----------+------------+-----------------+---------+-----------------+---------
  2841 | relation | orders     | RowExclusiveLock | f       | active          | postgres
  2812 | relation | orders     | RowExclusiveLock | t       | idle in trans   | postgres
(2 rows)
```

(`granted = t` = lock is held. `granted = f` = lock is waiting to be acquired.)

---

## Section 7 - Resolve the Lock

### Option 1 - Ask the session to commit or rollback

Go back to Session 1 and commit the transaction.

```sql
COMMIT;
```

Session 2 will immediately unblock and complete its UPDATE.

### Option 2 - Terminate the blocking session (when you cannot wait)

If the blocking session is from a crashed application or an accidental long transaction, you can terminate it:

```sql
SELECT pg_terminate_backend(<blocker_pid>);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

(`pg_terminate_backend(pid)` = sends SIGTERM to the backend process. The session disconnects and its transaction is rolled back. Use `pg_cancel_backend(pid)` first if you only want to cancel the current query without disconnecting the session.)

> **Concept - pg_cancel_backend vs pg_terminate_backend**: `pg_cancel_backend` sends a signal that cancels the current query but keeps the connection alive. `pg_terminate_backend` disconnects the session entirely (which also rolls back any open transaction). Always try cancel first - terminate is more disruptive to the application.

---

## Section 8 - Watch the Pulse Query Stats Panel

The Pulse Query Stats panel shows a locks indicator. When locks are present, it will highlight blocked sessions. To see it active, create a new lock scenario (start a transaction with an UPDATE but do not commit), then refresh the Pulse dashboard at:

```
http://<NODE1-IP>:8080
```

The Query Stats panel should show the blocked session with its wait event type as `Lock`.

---

## Section 9 - Exit All Sessions

In each terminal where you have an open psql session:

```sql
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should have:

- [ ] Read `wait_event_type` and `wait_event` from `pg_stat_activity`
- [ ] Understood the difference between key lock modes (AccessShare through AccessExclusive)
- [ ] Created a lock scenario with two sessions
- [ ] Used `pg_blocking_pids()` to identify the blocker and blocked sessions
- [ ] Inspected `pg_locks` to see granted vs waiting locks
- [ ] Resolved a lock with both `COMMIT` and `pg_terminate_backend()`
- [ ] Understood the difference between `pg_cancel_backend` and `pg_terminate_backend`

---

Proceed to: [Guide 05 - Custom Monitoring Queries](./05-custom-monitoring-queries.md)
