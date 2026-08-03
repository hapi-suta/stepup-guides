# SURVIVE Scenario 05: Schema Migration Gone Wrong - Runbook

## Scenario

A schema migration is holding a lock on a critical table. All queries to the table are blocked. The application is effectively down for operations involving this table.

---

## Step 1: Identify the Blocking Session

Connect to the database and find sessions holding ACCESS EXCLUSIVE locks:

```sql
SELECT pid, usename, state, wait_event_type, wait_event,
  now() - query_start AS duration, query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock' OR state = 'active'
ORDER BY duration DESC;
```

---

## Step 2: Find the Lock Holder

```sql
SELECT blocked_locks.pid AS blocked_pid,
  blocked_activity.usename AS blocked_user,
  blocking_locks.pid AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  blocked_activity.query AS blocked_statement,
  blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
  ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

---

## Step 3: Terminate the Lock-Holding Session

Use the `blocking_pid` from Step 2:

```sql
SELECT pg_terminate_backend(BLOCKING_PID);
```

Replace `BLOCKING_PID` with the actual PID from the query above.

---

## Step 4: Verify the Table is Accessible

```sql
SELECT count(*) FROM app.orders;
```

This should return immediately (50,000 rows).

---

## Step 5: Apply the Migration Correctly

The bad migration tried to add a NOT NULL column without a default. The correct way:

```sql
ALTER TABLE app.orders ADD COLUMN shipping_address TEXT DEFAULT '' NOT NULL;
```

In PostgreSQL 11+, adding a column with a non-volatile DEFAULT is instant (no table rewrite). The DEFAULT is stored in the catalog, not written to every row.

---

## Step 6: Set Lock Timeout for Future Migrations

Prevent migrations from holding locks indefinitely:

```sql
SET lock_timeout = '5s';
```

This causes the ALTER TABLE to fail immediately if it cannot acquire the lock within 5 seconds, instead of blocking forever.

---

## Step 7: Document Prevention Plan

1. Always set `lock_timeout` before running DDL in production
2. Always add NOT NULL columns WITH a DEFAULT value
3. Always test migrations in staging under concurrent load
4. Use `CREATE INDEX CONCURRENTLY` for new indexes (does not hold a lock)
5. Review every migration for potential lock conflicts before applying
