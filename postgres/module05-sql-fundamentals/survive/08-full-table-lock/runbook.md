# Scenario 08 - Full Table Lock

**Severity:** CRITICAL
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Products table is completely inaccessible.
All queries against the products table are hanging.
The storefront is down - customers cannot view or purchase products.
A migration script appears to be holding a lock.
```

---

## Key Concepts for Revision

- **Lock modes in PostgreSQL** - PostgreSQL has 8 lock modes from weakest to strongest: ACCESS SHARE, ROW SHARE, ROW EXCLUSIVE, SHARE UPDATE EXCLUSIVE, SHARE, SHARE ROW EXCLUSIVE, EXCLUSIVE, ACCESS EXCLUSIVE. Most queries take lightweight locks (ACCESS SHARE for SELECT, ROW EXCLUSIVE for UPDATE). ACCESS EXCLUSIVE blocks everything - even plain SELECTs.

- **ACCESS EXCLUSIVE lock** - This is the strongest lock mode. It blocks all other lock modes. Operations that take it include: `DROP TABLE`, `TRUNCATE`, `REINDEX`, `CLUSTER`, `VACUUM FULL`, and explicit `LOCK TABLE ... IN ACCESS EXCLUSIVE MODE`. A regular `ALTER TABLE` also takes this lock.

- **pg_locks** - The system view that shows all current lock requests. Key columns: `pid` (process holding/waiting for the lock), `relation` (the table OID), `mode` (lock type), `granted` (true if held, false if waiting). Joining with `pg_stat_activity` on `pid` shows the query that is holding the lock.

- **Blocking and waiting** - When session A holds an ACCESS EXCLUSIVE lock on a table, session B's SELECT on that table will wait. Session B shows `granted = false` in pg_locks and `wait_event_type = 'Lock'` in pg_stat_activity. The chain can be multiple levels deep if C is waiting on B which is waiting on A.

- **pg_blocking_pids()** - PostgreSQL 9.6+ provides `pg_blocking_pids(pid)` which returns an array of PIDs that are blocking the given PID. This is easier than manually joining pg_locks to find the blocker.

---

## Diagnostic Steps

### Step 1 - Connect to the server

Log in to the server:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open psql:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Confirm the table is locked

Try a simple SELECT on the products table. This query will hang (not return):

```sql
SET lock_timeout = '3s';
SELECT * FROM products LIMIT 1;
```

Expected output:

```
ERROR:  canceling statement due to lock timeout
```

The `lock_timeout = '3s'` prevents your own session from hanging indefinitely. The error confirms that something is holding a lock that blocks even reads.

Reset lock_timeout for the rest of your session:

```sql
SET lock_timeout = 0;
```

### Step 3 - Find ACCESS EXCLUSIVE locks on the products table

```sql
SELECT l.pid, l.mode, l.granted, a.application_name, a.state,
       now() - a.query_start AS lock_duration,
       LEFT(a.query, 80) AS query_preview
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.relation = 'products'::regclass
ORDER BY l.granted DESC, a.query_start;
```

Expected output (yours will differ):

```
  pid  |        mode         | granted |   application_name   |        state        |  lock_duration   |              query_preview
-------+---------------------+---------+----------------------+---------------------+------------------+---------------------------------------------
 12345 | AccessExclusiveLock |    t    | bad_migration_script | active              | 00:05:23.456789  | SELECT pg_sleep(3600);
(1 row)
```

The row with `granted = t` and `AccessExclusiveLock` is the blocker. Note the PID (12345 in this example).

### Step 4 - Confirm this PID is blocking others

Check if any sessions are waiting because of this PID:

```sql
SELECT pid, wait_event_type, wait_event, LEFT(query, 60) AS query_preview
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
  AND pid != pg_backend_pid();
```

This shows any other sessions that are stuck waiting for a lock. They will be unblocked once you terminate the blocker.

### Step 5 - Use pg_blocking_pids to confirm the chain

If you see waiting sessions, pick one and verify who is blocking it:

```sql
SELECT pg_blocking_pids(pid) AS blocked_by, pid, LEFT(query, 60)
FROM pg_stat_activity
WHERE wait_event_type = 'Lock';
```

Expected output (yours will differ):

```
 blocked_by | pid   |                         left
------------+-------+----------------------------------------------
 {12345}    | 12350 | SELECT * FROM products WHERE product_id = 1
(1 row)
```

This confirms PID 12345 is the root blocker.

---

## Resolution

### Step 1 - Terminate the blocking session

Use `pg_terminate_backend` to kill the session holding the ACCESS EXCLUSIVE lock. Replace `12345` with the actual PID from your diagnostic query:

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

`t` (true) means the signal was sent. The transaction will be rolled back and the lock released.

We use `pg_terminate_backend` instead of `pg_cancel_backend` here because the session is running `pg_sleep()` inside a transaction. Cancelling would abort the sleep but the transaction would remain open with the lock held. Terminating kills the entire connection and forces a rollback.

### Step 2 - Verify the lock is released

```sql
SELECT l.pid, l.mode, l.granted
FROM pg_locks l
WHERE l.relation = 'products'::regclass
  AND l.mode = 'AccessExclusiveLock';
```

Expected output:

```
 pid | mode | granted
-----+------+---------
(0 rows)
```

No more ACCESS EXCLUSIVE locks on the products table.

### Step 3 - Verify the table is accessible

```sql
SELECT * FROM products ORDER BY product_id;
```

Expected output (yours will differ):

```
 product_id |    name     | price  | stock
------------+-------------+--------+-------
          1 | Widget A    |  19.99 |   150
          2 | Widget B    |  29.99 |    80
          3 | Gadget C    |  49.99 |   200
          4 | Gadget D    |  99.99 |    50
          5 | Thingamajig |   9.99 |   500
(5 rows)
```

The table is readable again. Since the blocking transaction was rolled back, no data was changed.

### Step 4 - Test that writes also work

```sql
UPDATE products SET stock = stock + 1 WHERE product_id = 1;
```

Expected output:

```
UPDATE 1
```

```sql
UPDATE products SET stock = stock - 1 WHERE product_id = 1;
```

Revert the test change.

Exit psql:

```sql
\q
```

Exit the postgres user:

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
- products table exists
- No ACCESS EXCLUSIVE locks on products
- No blocked sessions waiting on products
- Table is readable and writable

---

## Interview Discussion Points

1. **What operations take an ACCESS EXCLUSIVE lock?** - `DROP TABLE`, `TRUNCATE`, `VACUUM FULL`, `REINDEX`, `CLUSTER`, and `LOCK TABLE ... IN ACCESS EXCLUSIVE MODE`. Most `ALTER TABLE` commands also take this lock. Regular `VACUUM` (without FULL) only takes a SHARE UPDATE EXCLUSIVE lock, which does not block reads or writes.

2. **How would you prevent this in production?** - Set `lock_timeout` on migration roles: `ALTER ROLE migration_user SET lock_timeout = '30s'`. This way, if a migration cannot acquire a lock within 30 seconds, it fails instead of waiting indefinitely and blocking everything behind it. Also use `statement_timeout` as a second safety net.

3. **What is the difference between lock_timeout and statement_timeout in this context?** - `lock_timeout` limits how long a statement will wait to acquire a lock. `statement_timeout` limits total execution time including the lock wait. If a migration acquires the lock quickly but then takes too long to run, `statement_timeout` catches it. Both should be set for migration roles.

4. **How do you safely run ALTER TABLE on a busy table?** - Use `lock_timeout` with retries: `SET lock_timeout = '3s'; ALTER TABLE ...`. If it times out, wait a moment and retry. This gives a brief window for the lock to be acquired without blocking all traffic for minutes. Some teams use tools like `pg_repack` or `pg-osc` that avoid long-held locks entirely.

5. **Can you have a chain of blocked sessions?** - Yes. If A holds a lock, B waits for A, then C's query needs the same table - C waits behind B. Terminating A unblocks B, which then runs and unblocks C. The `pg_blocking_pids()` function helps trace these chains. In extreme cases, hundreds of sessions can pile up behind a single blocker, exhausting `max_connections`.
