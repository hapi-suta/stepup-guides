# Build 11 - Wait Events and Lock Contention

**Estimated time:** 25-30 minutes

When a query is slow, it is either doing work (computing, reading data) or waiting for something (a lock, disk IO, another process). PostgreSQL tracks exactly what each session is waiting for through wait events. In this lab, you will learn to read wait events, simulate a lock, find the blocker, and resolve the situation.

---

## Prerequisites

- SSH access to your lab server
- PostgreSQL 16 running at `/opt/pgsql/data`
- Database `labdb` with an `orders` table containing data
- Ability to open three terminal windows simultaneously

---

## Section 1: Understanding Wait Events

Every active session in PostgreSQL is either running on CPU or waiting for something. The `wait_event_type` and `wait_event` columns in `pg_stat_activity` tell you exactly what a session is waiting on.

### Step 1: Log into your server

Open a terminal and SSH into your lab server.

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_SERVER_IP
```

### Step 2: Switch to the postgres user

```bash
sudo su - postgres
```

### Step 3: Connect to labdb

```bash
/usr/pgsql-16/bin/psql -d labdb
```

### Step 4: Query wait events for all sessions

This query shows what every backend process is doing right now. Background workers will show up with wait events like `AutoVacuumMain` or `BgWriterMain` - these are normal and expected.

```sql
SELECT pid, usename, state, wait_event_type, wait_event, backend_type,
       left(query, 50) AS query
FROM pg_stat_activity
ORDER BY backend_type, state;
```

Expected output (yours will differ):

```
  pid  | usename  |        state        | wait_event_type |     wait_event      |    backend_type    |                       query
-------+----------+---------------------+-----------------+---------------------+--------------------+---------------------------------------------------
 11001 |          |                     | Activity        | AutoVacuumMain      | autovacuum launcher|
 11002 |          |                     | Activity        | BgWriterMain        | background writer  |
 11003 |          |                     | Activity        | CheckpointerMain    | checkpointer       |
 11004 |          |                     | Activity        | WalWriterMain       | walwriter          |
 11010 | postgres | active              |                 |                     | client backend     | SELECT pid, usename, state, wait_event_type, wai
(5 rows)
```

### Step 5: Understand the wait event categories

Here are the categories you will see in `wait_event_type`:

| wait_event_type | What It Means |
|-----------------|---------------|
| **Lock** | Waiting for a heavyweight lock (row lock, table lock). Usually caused by another transaction holding a conflicting lock. |
| **LWLock** | Waiting for a lightweight lock (internal PostgreSQL data structures). Common during high concurrency. |
| **IO** | Waiting for a disk read or write. Could mean slow storage. |
| **BufferPin** | Waiting for access to a shared buffer page. Rare but can happen during VACUUM. |
| **Client** | Waiting for the client to send data or read results. Usually means the application is slow, not PostgreSQL. |
| **Activity** | Background worker waiting for work (AutoVacuumMain, BgWriterMain, etc.). Completely normal. |

A session with `wait_event_type = NULL` and `state = active` is running on CPU - it is doing actual work, not waiting.

---

## Section 2: Simulating a Lock

The best way to understand locks is to create one. You will open two psql sessions that try to update the same row. The second session will block until the first one finishes.

### Step 1: Open three terminal windows

You need three separate SSH connections to your server. In each terminal:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_SERVER_IP
```

Then switch to postgres:

```bash
sudo su - postgres
```

Then connect to labdb:

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Label your terminals mentally as **Terminal 1**, **Terminal 2**, and **Terminal 3**.

### Step 2: In Terminal 1 - Start a transaction and lock a row

The BEGIN command starts a transaction. The UPDATE acquires a row-level lock on order_id = 1. Because you do not COMMIT, the lock is held open.

```sql
BEGIN;
UPDATE orders SET status = 'test' WHERE order_id = 1;
```

Expected output (yours will differ):

```
BEGIN
UPDATE 1
```

**Do not type COMMIT. Leave this transaction open.**

### Step 3: In Terminal 2 - Try to update the same row

This UPDATE needs the same row lock that Terminal 1 is holding. It will hang - your cursor will just sit there with no output. This is a blocked query.

```sql
UPDATE orders SET status = 'test2' WHERE order_id = 1;
```

The cursor will not return. Terminal 2 is now blocked, waiting for Terminal 1 to release the lock. Leave it hanging.

### Step 4: In Terminal 3 - See the wait event

Now query pg_stat_activity from Terminal 3 to see what is happening.

```sql
SELECT pid, usename, state, wait_event_type, wait_event,
       left(query, 50) AS query
FROM pg_stat_activity
WHERE usename = 'postgres' AND pid != pg_backend_pid();
```

Expected output (yours will differ):

```
  pid  | usename  |        state        | wait_event_type | wait_event  |                       query
-------+----------+---------------------+-----------------+-------------+---------------------------------------------------
 22001 | postgres | idle in transaction |                 |             | UPDATE orders SET status = $1 WHERE order_id = $2
 22002 | postgres | active              | Lock            | transactionid| UPDATE orders SET status = $1 WHERE order_id = $2
(2 rows)
```

Notice:

- Terminal 1's session shows `idle in transaction` - it ran the UPDATE and is now sitting in the open transaction.
- Terminal 2's session shows `active` with `wait_event_type = Lock` and `wait_event = transactionid` - it is waiting for Terminal 1's transaction to finish.

### Step 5: In Terminal 3 - Query pg_locks for both PIDs

Replace the PIDs below with the actual PIDs from your output above.

```sql
SELECT locktype, relation::regclass, mode, granted, pid
FROM pg_locks
WHERE pid IN (22001, 22002)
ORDER BY pid, granted;
```

Expected output (yours will differ):

```
   locktype    | relation |       mode       | granted |  pid
---------------+----------+------------------+---------+-------
 transactionid |          | ExclusiveLock    | t       | 22001
 relation      | orders   | RowExclusiveLock | t       | 22001
 transactionid |          | ShareLock        | f       | 22002
 relation      | orders   | RowExclusiveLock | t       | 22002
(4 rows)
```

The key line is where `granted = f` (false). That is Terminal 2's lock request that is waiting. It wants a ShareLock on Terminal 1's transaction ID, which means "I need to wait for your transaction to finish."

---

## Section 3: Finding Blockers

When a production database has lock contention, you need to quickly find which session is blocking others.

### Step 1: In Terminal 3 - Use pg_blocking_pids()

This built-in function returns the PID(s) that are blocking a given session.

```sql
SELECT pid,
       pg_blocking_pids(pid) AS blocked_by,
       left(query, 50) AS query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Expected output (yours will differ):

```
  pid  | blocked_by |                       query
-------+------------+---------------------------------------------------
 22002 | {22001}    | UPDATE orders SET status = $1 WHERE order_id = $2
(1 row)
```

This tells you clearly: PID 22002 is blocked by PID 22001. In production, you would then look at PID 22001 to decide whether to wait for it or terminate it.

---

## Section 4: Lock Types

PostgreSQL has multiple lock modes, from the most permissive to the most restrictive. Two operations conflict when their lock modes are incompatible.

| Lock Mode | Taken By | Conflicts With |
|-----------|----------|----------------|
| AccessShareLock | SELECT | AccessExclusiveLock |
| RowShareLock | SELECT FOR UPDATE | ExclusiveLock, AccessExclusiveLock |
| RowExclusiveLock | INSERT, UPDATE, DELETE | ShareLock, ShareRowExclusiveLock, ExclusiveLock, AccessExclusiveLock |
| ShareLock | CREATE INDEX (non-concurrent) | RowExclusiveLock, ShareRowExclusiveLock, ExclusiveLock, AccessExclusiveLock |
| ShareRowExclusiveLock | Some ALTER TABLE, CREATE TRIGGER | RowExclusiveLock, ShareLock, ShareRowExclusiveLock, ExclusiveLock, AccessExclusiveLock |
| ExclusiveLock | REFRESH MATERIALIZED VIEW CONCURRENTLY | Everything except AccessShareLock |
| AccessExclusiveLock | DROP TABLE, ALTER TABLE (most forms), VACUUM FULL, LOCK TABLE | Everything |

The key takeaway: **VACUUM FULL and most ALTER TABLE commands take AccessExclusiveLock**, which blocks ALL other operations - including SELECT. On a busy production table, this can cause an outage. Use `ALTER TABLE ... ADD COLUMN` with defaults carefully, and prefer `CREATE INDEX CONCURRENTLY` over `CREATE INDEX`.

---

## Section 5: Resolving Locks

### Step 1: In Terminal 1 - Commit the transaction

This releases the lock and unblocks Terminal 2.

```sql
COMMIT;
```

### Step 2: Check Terminal 2

Terminal 2 should now complete its UPDATE and return output.

Expected output (yours will differ):

```
UPDATE 1
```

The lock is resolved. In production, you have three options when you find a blocker:

1. **Wait** - If the blocking transaction will finish soon, just wait.
2. **Ask the application team** - Find out what the blocking session is doing and whether it can be committed or rolled back.
3. **pg_terminate_backend()** - As a last resort, kill the blocking connection. This rolls back its transaction.

```sql
-- LAST RESORT ONLY - do not run this now
SELECT pg_terminate_backend(22001);
```

### Step 3: Clean up the test data in Terminal 1

Reset the row you modified during the simulation.

```sql
UPDATE orders SET status = 'pending' WHERE order_id = 1;
```

---

## Section 6: Deadlock Detection

A deadlock happens when two sessions each hold a lock that the other needs. Neither can proceed. PostgreSQL automatically detects deadlocks and kills one of the two transactions to break the cycle.

### Step 1: In Terminal 1 - Configure lock wait logging

These settings tell PostgreSQL to log a message when a session waits more than 1 second for a lock. This helps you find lock contention in your logs.

```sql
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET deadlock_timeout = '1s';
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
ALTER SYSTEM
ALTER SYSTEM
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 2: Understand what happens during a deadlock

Here is the scenario (you do not need to simulate this):

1. Session A locks row 1, then tries to lock row 2.
2. Session B locks row 2, then tries to lock row 1.
3. Both sessions are waiting for each other - a deadlock.
4. PostgreSQL detects this within `deadlock_timeout` (1 second).
5. PostgreSQL picks one session and cancels its transaction with: `ERROR: deadlock detected`
6. The other session proceeds.

The canceled session's transaction is rolled back. The application should retry it.

### Step 3: Verify the settings took effect

```sql
SHOW log_lock_waits;
SHOW deadlock_timeout;
```

Expected output (yours will differ):

```
 log_lock_waits
----------------
 on
(1 row)

 deadlock_timeout
------------------
 1s
(1 row)
```

---

## Section 7: Advisory Locks (Brief)

Advisory locks are application-level locks that PostgreSQL manages for you. Unlike row or table locks, they do not lock any actual data. Your application decides what they mean.

### Step 1: See how advisory locks work

The most common use case is ensuring only one instance of a batch job runs at a time. The number (12345) is an arbitrary key your application chooses.

```sql
-- Try to acquire advisory lock 12345 (non-blocking)
SELECT pg_try_advisory_lock(12345);
```

Expected output (yours will differ):

```
 pg_try_advisory_lock
----------------------
 t
(1 row)
```

`t` (true) means you got the lock. If another session already held lock 12345, you would get `f` (false) and know that the batch job is already running.

### Step 2: Release the advisory lock

```sql
SELECT pg_advisory_unlock(12345);
```

There is also a blocking version - `pg_advisory_lock(12345)` - which waits until the lock is available instead of returning true/false.

Advisory locks are released automatically when the session disconnects. You can also release them explicitly as shown above.

---

## Cleanup

### Step 1: Exit psql in all three terminals

In each terminal:

```sql
\q
```

### Step 2: Exit the postgres user in all three terminals

In each terminal:

```bash
exit
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| Wait events | How to see what each session is waiting for using pg_stat_activity |
| Lock simulation | How row-level locks cause blocking between concurrent transactions |
| pg_blocking_pids() | How to quickly find which session is blocking others |
| Lock types | Why VACUUM FULL and ALTER TABLE are dangerous in production |
| Deadlock detection | PostgreSQL automatically detects and resolves deadlocks |
| Advisory locks | Application-level locks for coordinating batch jobs |

In production, lock contention is one of the most common causes of performance problems. The queries in this lab - especially `pg_blocking_pids()` and the pg_stat_activity wait event query - should be bookmarked and ready to run at a moment's notice.
