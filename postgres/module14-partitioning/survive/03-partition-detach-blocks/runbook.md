# Scenario 03 - DETACH PARTITION Holding ACCESS EXCLUSIVE Lock

**Severity:** CRITICAL
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: A DETACH PARTITION operation is holding an ACCESS EXCLUSIVE lock on orders_chaos3.
All SELECTs and INSERTs on orders_chaos3 are queued.
Application is reporting timeouts.
Diagnose and resolve the blocking operation.
```

---

## Key Concepts for Revision

- **Plain DETACH PARTITION takes ACCESS EXCLUSIVE** - `ALTER TABLE ... DETACH PARTITION` (without CONCURRENTLY) takes an `ACCESS EXCLUSIVE` lock on the parent table for the entire duration of the operation. This blocks ALL operations on the parent: SELECT, INSERT, UPDATE, DELETE. On a large table, this can last minutes and cause a queue of waiting queries that cascades into application timeouts.

- **DETACH CONCURRENTLY was added in PG14** - `ALTER TABLE ... DETACH PARTITION CONCURRENTLY` uses a weaker lock mechanism. It takes a `SHARE UPDATE EXCLUSIVE` lock (allows reads and writes to continue), verifies no conflicting transactions exist, then completes the detach. It takes longer to complete but never blocks normal operations.

- **Killing the blocking session is immediate relief** - If the blocker is a non-essential administrative operation (like a runaway DETACH), terminate it with `pg_terminate_backend()`. The blocked queries will then immediately proceed.

- **Transaction holding a lock matters** - If the DETACH is in a transaction that also does other work, killing it rolls back everything in that transaction. Understand the scope of the transaction before terminating it.

---

## Diagnostic Steps

### Step 1 - Identify the blocking query

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check for blocked queries and their blockers:

```sql
SELECT
    blocked.pid            AS blocked_pid,
    blocked.query          AS blocked_query,
    blocker.pid            AS blocker_pid,
    blocker.query          AS blocker_query,
    blocker.state          AS blocker_state,
    blocker.wait_event     AS blocker_wait,
    now() - blocker.query_start AS blocker_duration
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocker
    ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.pid <> blocker.pid
ORDER BY blocker_duration DESC;
```

Expected output (yours will differ):

```
 blocked_pid | blocked_query | blocker_pid |           blocker_query            | blocker_state | blocker_wait | blocker_duration
-------------+---------------+-------------+------------------------------------+---------------+--------------+------------------
       12345 | SELECT ...    |       12301 | ALTER TABLE orders_chaos3 DETACH.. | active        | Lock         | 00:02:14
(1 row)
```

### Step 2 - Check the lock type

```sql
SELECT
    pid,
    locktype,
    relation::regclass AS table_name,
    mode,
    granted,
    query
FROM pg_locks
JOIN pg_stat_activity USING (pid)
WHERE relation = 'orders_chaos3'::regclass;
```

Expected output (yours will differ):

```
  pid  | locktype |  table_name   |        mode         | granted |          query
-------+----------+---------------+---------------------+---------+------------------------------
 12301 | relation | orders_chaos3 | AccessExclusiveLock |    t    | ALTER TABLE orders_chaos3 ...
 12345 | relation | orders_chaos3 | AccessShareLock     |    f    | SELECT COUNT(*) FROM ...
```

`AccessExclusiveLock granted = true` is the blocker. `AccessShareLock granted = false` is the blocked SELECT waiting.

### Step 3 - Confirm this is a plain DETACH (not CONCURRENTLY)

```sql
SELECT pid, query, query_start, state
FROM pg_stat_activity
WHERE query ILIKE '%DETACH PARTITION%'
AND query NOT ILIKE '%CONCURRENTLY%';
```

If this returns the blocking PID, it confirms the root cause: someone ran `DETACH PARTITION` without `CONCURRENTLY`.

---

## Resolution

### Step 1 - Terminate the blocking session

First record the blocker PID from the diagnostic step. Then terminate it:

```sql
SELECT pg_terminate_backend(12301);
```

Replace `12301` with the actual blocker PID from your diagnostic output.

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

### Step 2 - Verify the lock is released

```sql
SELECT COUNT(*) FROM pg_locks
WHERE relation = 'orders_chaos3'::regclass
AND mode = 'AccessExclusiveLock'
AND granted = true;
```

Expected output:

```
 count
-------
     0
(1 row)
```

### Step 3 - Verify queries can run again

```sql
SELECT COUNT(*) FROM orders_chaos3;
```

Expected output (yours will differ):

```
 count
-------
  3000
(1 row)
```

### Step 4 - Now do the DETACH correctly using CONCURRENTLY

```sql
ALTER TABLE orders_chaos3
    DETACH PARTITION orders_chaos3_2024_01 CONCURRENTLY;
```

Expected output:

```
ALTER TABLE
```

### Step 5 - Verify the detach completed and the table is accessible

```sql
SELECT COUNT(*) FROM orders_chaos3;
```

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## Validation

Run the validation script:

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- No ACCESS EXCLUSIVE lock on orders_chaos3
- orders_chaos3 accepts SELECT queries
- orders_chaos3_2024_01 is detached from the parent

---

## Interview Discussion Points

1. **Why does plain DETACH PARTITION block everything while DETACH CONCURRENTLY does not?** - Plain DETACH needs an `ACCESS EXCLUSIVE` lock to atomically remove the partition from the parent's metadata and update all catalog entries. No other operation can proceed on the parent during this window. DETACH CONCURRENTLY breaks the operation into multiple phases with progressively stronger locks, each held briefly. It waits for existing transactions to finish between phases rather than blocking them upfront.

2. **What is the `pg_blocking_pids()` function and why is it useful?** - `pg_blocking_pids(pid)` returns an array of PIDs that are blocking the given PID. It resolves the blocking chain automatically, even through multiple levels of blocking. It is more reliable than joining `pg_locks` manually because it handles the complexity of different lock types and wait queues. Always use this for lock diagnostics.

3. **If you terminate the blocking session, what happens to the DETACH operation?** - The termination causes the session to roll back. The DETACH is reversed - the partition is re-attached exactly as it was before. The blocked queries then proceed with the partition still in place. No data is lost. You then need to redo the DETACH correctly using CONCURRENTLY.

4. **How would you prevent this from happening again?** - Add a lock timeout to the DBA session before running DETACH: `SET lock_timeout = '5s';`. If the DETACH cannot acquire the lock within 5 seconds, it fails with an error rather than waiting and blocking everyone else. Also enforce policy: all partition maintenance must use CONCURRENTLY options. Add a check to your runbooks that flags any DETACH without CONCURRENTLY.

5. **What does DETACH CONCURRENTLY's multi-phase process look like?** - Phase 1: Mark the partition as "detaching" in the catalog (brief `ACCESS EXCLUSIVE` lock). Phase 2: Wait for all existing transactions that could see the partition to finish (no lock held, just waiting). Phase 3: Complete the detach and remove the partition from the parent's metadata (another brief lock). Between phases, reads and writes continue normally. The operation can take longer (seconds to minutes on a busy system) but never causes a queue.
