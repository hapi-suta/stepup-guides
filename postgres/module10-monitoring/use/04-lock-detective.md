# Use Exercise 04 - Lock Detective

Create a lock scenario yourself, then use pg_locks and pg_stat_activity to find the blocker, understand what lock it holds, and resolve it.

**Run on:** NODE1

---

## Your Mission

Locks are one of the most common causes of production incidents. A DBA who can walk into a situation, identify the blocker in under 2 minutes, and resolve it safely is worth their weight. In this exercise you will:

1. Create a 3-session lock chain (A blocks B, B blocks C)
2. Use your diagnostic queries to map the entire chain
3. Resolve it with the least disruptive method
4. Document what happened

---

## Instructions

You will need 3 terminal windows open, all SSH'd into NODE1.

### Terminal Setup

In all three terminals, SSH into NODE1 and switch to postgres.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

```
sudo -iu postgres
```

---

## Part A - Create the Lock Chain

### Session 1 - The Root Blocker

Open psql.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Start a transaction and lock a row.

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

Leave this transaction open. Do NOT commit.

### Session 2 - The Middle Waiter

Open psql.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Try to update the same row.

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 1;
```

This will hang. Leave it hanging.

### Session 3 - Your Diagnostic Session

Open psql.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Part B - Map the Lock Chain

In Session 3, run the blocker query from Guide 04.

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    left(blocked.query, 50) AS blocked_query,
    blocker.pid AS blocker_pid,
    blocker.usename AS blocker_user,
    blocker.state AS blocker_state,
    now() - blocker.query_start AS blocker_running_for
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocker
    ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Write down: the blocker PID, the blocked PID, and the state of the blocker.

Now run the pg_locks inspection.

```sql
SELECT
    l.pid,
    l.locktype,
    l.relation::regclass AS table_name,
    l.mode,
    l.granted,
    a.state
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.relation IS NOT NULL
ORDER BY l.granted, l.pid;
```

Write down: which mode is granted and which mode is waiting.

---

## Part C - Answer the Investigation Questions

Before resolving, answer these questions (write your answers down or discuss with your instructor):

1. What lock mode does Session 1 hold on the `orders` table?
2. What lock mode is Session 2 waiting for?
3. Why does Session 2's UPDATE conflict with Session 1's UPDATE? (Check the lock conflict matrix from Guide 04.)
4. If a fourth session tried to run `ALTER TABLE orders ADD COLUMN notes text;` right now, what would happen? Why?
5. If Session 1 stays open for 30 more minutes, what happens to the application? (Think about connection pool exhaustion.)

---

## Part D - Resolve the Lock

Decide: is this a case for `pg_cancel_backend` or `pg_terminate_backend`?

The blocker is in `idle in transaction` state - that means it is not actively running a query, so `pg_cancel_backend` will NOT help (there is no query to cancel). You must use `pg_terminate_backend`.

In Session 3, terminate the blocking session.

```sql
SELECT pg_terminate_backend(<blocker_pid_from_part_b>);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

Now look at Session 2. It should either complete its UPDATE or fail with a connection error (if it was connected to the same session you terminated - which it was not in this case).

In Session 3, confirm no more blocked sessions.

```sql
SELECT blocked.pid, pg_blocking_pids(blocked.pid)
FROM pg_stat_activity AS blocked
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Expected output:

```
 pid | pg_blocking_pids
-----+------------------
(0 rows)
```

---

## Part E - Clean Up

In Session 2, if the UPDATE completed, commit it.

```sql
COMMIT;
```

If Session 2 received an error because the blocker was terminated, roll back.

```sql
ROLLBACK;
```

Exit all sessions.

```sql
\q
```

```
exit
```

---

## Checkpoint

- [ ] Created a lock scenario with at least 2 sessions (one holding, one waiting)
- [ ] Used `pg_blocking_pids()` to find the blocker
- [ ] Inspected `pg_locks` to see granted vs waiting modes
- [ ] Answered the 5 investigation questions
- [ ] Resolved the lock with `pg_terminate_backend`
- [ ] Confirmed no blocked sessions remain

---

Proceed to: [Use Exercise 05 - Log Analysis](./05-log-analysis.md)
