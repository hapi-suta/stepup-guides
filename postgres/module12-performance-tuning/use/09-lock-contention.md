# Use Exercise 09 - Lock Contention

Simulate and diagnose lock contention scenarios that happen in production PostgreSQL databases.

**Server:** NODE1 only
**Terminals needed:** 3 (Terminal A, Terminal B, Terminal C)

---

## Setup

Open three separate terminal windows. In each one, SSH into NODE1 and connect to labdb as the postgres user.

**Step 1 - SSH into NODE1 (do this in all three terminals):**

```bash
ssh -i ~/your-key.pem ec2-user@<NODE1_IP>
```

This connects you to NODE1 as the ec2-user.

**Step 2 - Switch to the postgres OS user (do this in all three terminals):**

```bash
sudo -i -u postgres
```

This switches you to the postgres OS user, which has permission to run psql commands.

**Step 3 - Connect to labdb (do this in all three terminals):**

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

This opens an interactive psql session connected to the labdb database on port 5432.

You should see the `labdb=#` prompt in all three terminals. You are ready to begin.

---

## Task 1 - Simulate a Row Lock

In this task, you will start a transaction that holds a lock, then watch a second session block while trying to update the same row.

**In Terminal A - Begin a transaction and lock a row:**

```sql
BEGIN;
```

This starts a transaction. PostgreSQL will hold any locks acquired in this transaction until you COMMIT or ROLLBACK.

```sql
UPDATE orders SET status = 'processing' WHERE order_id = 1;
```

This updates row 1 in the orders table. PostgreSQL places a row-level exclusive lock on this row. The lock is held because we have not committed yet.

**In Terminal B - Try to update the same row:**

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 1;
```

This command will appear to hang. Terminal B is now blocked because Terminal A already holds an exclusive lock on row 1. Terminal B is waiting for that lock to be released.

**In Terminal C - Find the waiting session:**

```sql
SELECT pid,
       usename,
       state,
       wait_event_type,
       wait_event,
       query
FROM pg_stat_activity
WHERE state = 'active'
  AND wait_event IS NOT NULL;
```

This queries the `pg_stat_activity` view, which shows one row per active database connection. We are filtering for sessions that are currently active and waiting on something.

Expected output (yours will differ):

```
  pid  | usename  | state  | wait_event_type | wait_event |             query
-------+----------+--------+-----------------+------------+--------------------------------
 12847 | postgres | active | Lock            | relation   | UPDATE orders SET status = ...
```

**Answer these questions before moving on:**

- What value do you see in the `wait_event_type` column?
- What value do you see in the `wait_event` column?
- What does this tell you about why Terminal B is stuck?

**Cleanup - keep Terminal A's transaction open for Task 2. Do NOT commit yet.**

---

## Task 2 - Find the Blocker

Now you will use the `pg_blocking_pids()` function to identify exactly which session is preventing Terminal B from continuing.

**In Terminal C - Find the blocker:**

First, get the PID of the waiting session. Replace `<waiting_pid>` with the pid you found in Task 1.

```sql
SELECT pid,
       pg_blocking_pids(pid) AS blocked_by,
       usename,
       query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

This query uses `pg_blocking_pids()`, which takes a session's PID and returns an array of PIDs that are blocking it. The `cardinality()` function returns the number of elements in the array - we use it here to filter out sessions that are not blocked by anyone.

Expected output (yours will differ):

```
  pid  | blocked_by | usename  |             query
-------+------------+----------+--------------------------------
 12847 | {12801}    | postgres | UPDATE orders SET status = ...
```

The value in `blocked_by` is the PID of Terminal A - the session holding the lock.

**Answer these questions before moving on:**

- Which PID is the blocker? Which PID is blocked?
- If this were a production database and the blocker had been idle for 30 minutes, how would you handle it?

**Cleanup - keep Terminal A's transaction open for Task 3. Do NOT commit yet.**

---

## Task 3 - Kill a Blocking Session

You will now terminate the blocking session using `pg_terminate_backend()` and watch Terminal B's query unblock.

**In Terminal C - Terminate the blocking session:**

Replace `<blocker_pid>` with the PID of Terminal A's session that you found in Task 2.

```sql
SELECT pg_terminate_backend(<blocker_pid>);
```

This sends a SIGTERM signal to the specified backend process, forcing it to disconnect immediately. PostgreSQL will automatically roll back any open transaction that session was holding.

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

The `t` (true) means the termination signal was sent successfully.

**Switch to Terminal A - observe what happened:**

Terminal A should now show an error message like:

```
FATAL:  terminating connection due to administrator command
The connection to the server was lost. Attempting reset: Succeeded.
```

The transaction Terminal A was holding has been rolled back automatically.

**Switch to Terminal B - observe what happened:**

Terminal B's blocked UPDATE should now complete. You will see:

```
UPDATE 1
```

This confirms that once the blocker was removed, PostgreSQL granted the lock to Terminal B and executed the update.

**Answer this question before moving on:**

- What is the difference between `pg_cancel_backend()` and `pg_terminate_backend()`? When would you use one versus the other?

**Cleanup - In Terminal B, roll back the completed update:**

```sql
ROLLBACK;
```

This undoes the update Terminal B just made, keeping the orders table clean for the next tasks.

**In Terminal A - reconnect to labdb (psql was disconnected):**

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

---

## Task 4 - Simulate a Deadlock

A deadlock happens when two sessions each hold a lock the other session needs. You will create this situation deliberately so you can recognize it in production.

**In Terminal A - Begin a transaction and lock row 1:**

```sql
BEGIN;
```

```sql
UPDATE orders SET status = 'processing' WHERE order_id = 1;
```

Terminal A now holds an exclusive lock on order_id = 1.

**In Terminal B - Begin a transaction and lock row 2:**

```sql
BEGIN;
```

```sql
UPDATE orders SET status = 'processing' WHERE order_id = 2;
```

Terminal B now holds an exclusive lock on order_id = 2.

**In Terminal A - Now try to lock row 2:**

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 2;
```

Terminal A will hang. It is waiting for the lock on row 2, which Terminal B holds.

**In Terminal B - Now try to lock row 1:**

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 1;
```

Do not wait - run this immediately. PostgreSQL's deadlock detector runs periodically (default every 1 second). Within a second or two, one of the sessions will receive an error.

Expected output in the session PostgreSQL chose to cancel (yours will differ):

```
ERROR:  deadlock detected
DETAIL:  Process 12801 waits for ShareLock on transaction 5432; blocked by process 12847.
         Process 12847 waits for ShareLock on transaction 5431; blocked by process 12801.
HINT:  See server log for query details.
```

**Answer these questions before moving on:**

- Which session did PostgreSQL kill - Terminal A or Terminal B?
- Why does PostgreSQL always kill exactly one of the two sessions and not both?
- What exact error message appeared in the killed session?

**Cleanup - the surviving session must also be rolled back:**

In the session that did NOT get the deadlock error, run:

```sql
ROLLBACK;
```

In the session that did get the deadlock error, PostgreSQL already aborted that transaction. Run ROLLBACK to clear the error state:

```sql
ROLLBACK;
```

---

## Task 5 - Lock Monitoring Query

You will write a query that joins `pg_locks` and `pg_stat_activity` to get a complete picture of lock activity, including which locks are granted and which are waiting.

**In Terminal A - Hold a lock so there is something to see:**

```sql
BEGIN;
```

```sql
UPDATE orders SET status = 'processing' WHERE order_id = 3;
```

Leave this transaction open. Do not commit yet.

**In Terminal C - Run the lock monitoring query:**

```sql
SELECT
    sa.pid,
    sa.usename,
    sa.state,
    pl.locktype,
    pl.mode,
    pl.granted,
    sa.query
FROM pg_locks pl
JOIN pg_stat_activity sa ON pl.pid = sa.pid
WHERE sa.pid <> pg_backend_pid()
  AND sa.usename IS NOT NULL
ORDER BY sa.pid, pl.granted;
```

This joins `pg_locks` (which shows every lock currently held or requested in the database) with `pg_stat_activity` (which shows session details). The `pg_backend_pid()` function returns the PID of the current session so we can exclude it from results. We order by `granted` so waiting locks appear first.

Expected output (yours will differ):

```
  pid  | usename  | state  | locktype |      mode       | granted |             query
-------+----------+--------+----------+-----------------+---------+--------------------------------
 12801 | postgres | idle   | relation | RowExclusiveLock| t       | UPDATE orders SET status = ...
 12801 | postgres | idle   | tuple    | ExclusiveLock   | t       | UPDATE orders SET status = ...
```

**Now open a second session that blocks (in Terminal B):**

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 3;
```

Terminal B will hang. Run the monitoring query again in Terminal C to see both the granted and waiting locks.

**Answer this question before moving on:**

- What does `granted = false` mean in the `pg_locks` view?

**Cleanup - In Terminal A:**

```sql
ROLLBACK;
```

In Terminal B, the blocked UPDATE will complete now. Roll it back:

```sql
ROLLBACK;
```

---

## Task 6 - Idle in Transaction

An "idle in transaction" session is one that has opened a transaction but is not actively running a query. It holds locks and blocks vacuum. This is one of the most common production problems.

**In Terminal A - Start a transaction and run a query, then do nothing:**

```sql
BEGIN;
```

```sql
SELECT order_id, status FROM orders WHERE order_id = 4;
```

You will see results. Now do nothing. Do not type COMMIT or ROLLBACK. Just leave the terminal sitting there.

Wait 10 seconds. The session is now "idle in transaction" - it has an open transaction but is not executing anything.

**In Terminal C - Find idle in transaction sessions:**

```sql
SELECT pid,
       usename,
       state,
       now() - state_change AS idle_duration,
       query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_duration DESC;
```

This queries `pg_stat_activity` for sessions in the `idle in transaction` state. The `state_change` column holds the timestamp of the last state change, so subtracting it from `now()` gives you how long the session has been idle.

Expected output (yours will differ):

```
  pid  | usename  |       state         | idle_duration |                query
-------+----------+---------------------+---------------+--------------------------------------
 12801 | postgres | idle in transaction | 00:00:18.4312 | SELECT order_id, status FROM orders ...
```

**Answer these questions before moving on:**

- What value do you see in the `state` column for Terminal A's session?
- Why is an "idle in transaction" session dangerous in production? Name at least two reasons.

**Cleanup - In Terminal A, end the open transaction:**

```sql
ROLLBACK;
```

This closes the transaction and releases any locks it was holding.

---

## Wrap-Up

You have now practiced the core skills for diagnosing lock contention in PostgreSQL:

- Identifying blocked sessions using `pg_stat_activity`
- Finding the blocking PID using `pg_blocking_pids()`
- Safely terminating a blocking session with `pg_terminate_backend()`
- Recognizing and understanding deadlock errors
- Writing a lock monitoring query that joins `pg_locks` and `pg_stat_activity`
- Identifying dangerous "idle in transaction" sessions

These same queries and techniques apply directly to production incidents. Bookmark the lock monitoring query from Task 5 - you will use it regularly.

**Final cleanup - exit psql in all three terminals:**

```sql
\q
```

Then exit the postgres OS user in each terminal:

```bash
exit
```
