# SURVIVE 02: The Locked Table During Deploy

**Module 05: CI/CD for Database Changes**
**Difficulty: Hard**
**Estimated Time: 30-45 minutes**

---

## The Scenario

It is 11:30 AM on a Friday (of course). Your CI/CD pipeline just deployed a migration to production. The migration runs:

```sql
CREATE INDEX idx_transactions_created_at ON transactions (created_at);
```

The `transactions` table has 50 million rows. This is a standard `CREATE INDEX` (not CONCURRENTLY), which acquires a `SHARE` lock - blocking all writes to the table.

Within 30 seconds, the application team reports:
- All insert/update operations on `transactions` are hanging
- The API response times have spiked from 50ms to 30+ seconds
- PgBouncer shows connections piling up in "waiting" state
- Customers are seeing timeouts

You check `pg_stat_activity` and see a lock queue forming: the index creation is holding a SHARE lock, 47 write transactions are queued behind it, and new connections keep arriving.

The index creation has been running for 2 minutes. Based on table size, you estimate it needs 8 more minutes to complete.

**You have to decide: do you wait, or do you kill it?**

---

## Setup - Reproduce the Problem

**On your Mac terminal:**

```bash
psql -U postgres -c "DROP DATABASE IF EXISTS survive_locks;"
psql -U postgres -c "CREATE DATABASE survive_locks;"
```

```bash
psql -U postgres -d survive_locks -c "
-- Create the transactions table with enough data to make index creation slow
CREATE TABLE transactions (
    txn_id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    txn_type VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    description TEXT
);

-- Insert 5 million rows (adjust down if your machine is slow)
INSERT INTO transactions (account_id, amount, txn_type, created_at, description)
SELECT
    (random() * 10000)::int + 1,
    (random() * 10000)::numeric(12,2),
    CASE (random() * 3)::int WHEN 0 THEN 'debit' WHEN 1 THEN 'credit' ELSE 'transfer' END,
    now() - (random() * 365)::int * interval '1 day',
    'Transaction ' || i
FROM generate_series(1, 5000000) AS i;

ANALYZE transactions;
"
```

This will take a minute or two.

---

## Simulate the Lock Problem

You need two terminal windows.

**Terminal 1 - Start the blocking index creation:**

```bash
psql -U postgres -d survive_locks -c "CREATE INDEX idx_transactions_created_at ON transactions (created_at);"
```

This will run for several seconds on 5M rows.

**Terminal 2 - While Terminal 1 is running, try to write:**

```bash
psql -U postgres -d survive_locks -c "INSERT INTO transactions (account_id, amount, txn_type) VALUES (1, 100.00, 'debit');"
```

This INSERT will hang until the index creation in Terminal 1 completes. This is the lock queue in action.

**Terminal 2 - Check the locks:**

Open a third terminal (or wait for the INSERT to time out):

```bash
psql -U postgres -d survive_locks -c "
SELECT
    pid,
    state,
    wait_event_type,
    wait_event,
    left(query, 80) AS query,
    now() - query_start AS duration
FROM pg_stat_activity
WHERE datname = 'survive_locks'
  AND state != 'idle'
ORDER BY query_start;
"
```

Expected output (yours will differ):
```
  pid  |        state        | wait_event_type | wait_event |                    query                     |    duration
-------+---------------------+-----------------+------------+----------------------------------------------+----------------
 12345 | active              |                 |            | CREATE INDEX idx_transactions_created_at ON t | 00:00:15.123
 12346 | active              | Lock            | relation   | INSERT INTO transactions (account_id, amount  | 00:00:08.456
```

You can see:
- The CREATE INDEX is `active` (running)
- The INSERT is `active` but waiting on a `Lock` (blocked)

---

## Your Mission

1. **Identify the blocking query** and its PID
2. **Decide whether to wait or kill** - justify your decision
3. **Kill the migration safely** if you decide to cancel
4. **Check for damage** - did the failed index leave anything behind?
5. **Rewrite the migration** using zero-downtime patterns
6. **Apply the corrected migration** and verify it works

---

## Investigation Steps

### Find the Blocking PID

```sql
-- Find who is blocking whom
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.query AS blocked_query,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.query AS blocking_query,
    now() - blocking_activity.query_start AS blocking_duration
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation = blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

### Check Lock Queue Depth

```sql
-- How many sessions are waiting?
SELECT count(*) AS waiting_sessions
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
  AND datname = 'survive_locks';
```

### Check Index Creation Progress

```sql
SELECT
    phase,
    blocks_total,
    blocks_done,
    CASE WHEN blocks_total > 0
         THEN round(100.0 * blocks_done / blocks_total, 1)
         ELSE 0
    END AS pct_done
FROM pg_stat_progress_create_index;
```

---

## Decision Framework

### Wait It Out If:
- The index is 80%+ complete (almost done)
- Lock queue has fewer than 5 sessions
- Application has reasonable statement timeouts
- It is a maintenance window

### Kill It If:
- Lock queue is growing rapidly
- Application timeouts are cascading
- Index is less than 50% complete
- Customers are affected NOW

For this scenario: **kill it.** The application is actively degraded, customers see timeouts, and waiting 8 more minutes is unacceptable during business hours.

---

## Resolution Steps

### Step 1: Cancel the Index Creation

```sql
-- Find the PID of the CREATE INDEX statement
SELECT pid, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE query LIKE 'CREATE INDEX%' AND datname = 'survive_locks';
```

Cancel it gracefully first:

```sql
SELECT pg_cancel_backend(12345);  -- Replace 12345 with actual PID
```

If `pg_cancel_backend` does not work within a few seconds, force terminate:

```sql
SELECT pg_terminate_backend(12345);  -- Replace 12345 with actual PID
```

**Important difference:**
- `pg_cancel_backend` sends SIGINT - cancels the current query but keeps the connection
- `pg_terminate_backend` sends SIGTERM - kills the entire connection

### Step 2: Check for Invalid Index

When `CREATE INDEX` is cancelled, it may leave behind an invalid index:

```sql
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'transactions'
  AND indexname = 'idx_transactions_created_at';
```

Also check for invalid indexes:

```sql
SELECT
    c.relname AS index_name,
    i.indisvalid AS is_valid
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'transactions'::regclass
  AND NOT i.indisvalid;
```

If an invalid index exists, drop it:

```sql
DROP INDEX IF EXISTS idx_transactions_created_at;
```

### Step 3: Verify Lock Queue Cleared

```sql
SELECT count(*) AS waiting_sessions
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
  AND datname = 'survive_locks';
-- Should return 0
```

### Step 4: Rewrite the Migration

The original migration:

```sql
-- BAD: acquires SHARE lock, blocks all writes
CREATE INDEX idx_transactions_created_at ON transactions (created_at);
```

The corrected migration:

```bash
vi V_fixed__add_transactions_index.sql
```

```sql
-- flyway:executeInTransaction=false

-- Safety: fail fast if we cannot get a lock
SET lock_timeout = '5s';

-- CONCURRENTLY: builds the index without blocking writes
-- Takes longer but does not lock the table
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transactions_created_at
    ON transactions (created_at);
```

### Step 5: Apply the Corrected Migration

```bash
psql -U postgres -d survive_locks -f V_fixed__add_transactions_index.sql
```

Expected output (yours will differ):
```
SET
CREATE INDEX
```

### Step 6: Verify the Index

```sql
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'transactions'
  AND indexname = 'idx_transactions_created_at';
```

Check that it is valid:

```sql
SELECT
    c.relname AS index_name,
    i.indisvalid AS is_valid
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'transactions'::regclass;
```

All indexes should show `is_valid = true`.

---

## Prevention Checklist

After the incident, add these safeguards:

### Migration Review Checklist

- [ ] Does any migration use `CREATE INDEX` without `CONCURRENTLY`?
- [ ] Does any migration use `ALTER TABLE` that could rewrite the table?
- [ ] Does every migration include `SET lock_timeout = '5s'`?
- [ ] Has the migration been tested on production-scale data?
- [ ] Is the migration scheduled for a low-traffic window?

### CI Pipeline Additions

Add a lint step to your CI pipeline that checks for dangerous patterns:

```bash
# Check for CREATE INDEX without CONCURRENTLY
if grep -r "CREATE INDEX" migrations/sql/ | grep -v "CONCURRENTLY" | grep -v "^--"; then
    echo "FAIL: Found CREATE INDEX without CONCURRENTLY"
    exit 1
fi
```

### Flyway Configuration

For indexes, always disable transaction wrapping:

```sql
-- flyway:executeInTransaction=false
```

Without this, Flyway wraps the migration in a transaction, and `CREATE INDEX CONCURRENTLY` fails because it cannot run inside a transaction.

---

## Validation Checklist

- [ ] Blocking CREATE INDEX was cancelled
- [ ] No invalid indexes remain
- [ ] Lock queue is empty
- [ ] New index was created with CONCURRENTLY
- [ ] Index is valid (`indisvalid = true`)
- [ ] Application write operations are working normally
- [ ] Migration file is corrected for future deployments
- [ ] CI lint step added to catch `CREATE INDEX` without `CONCURRENTLY`

---

## Lessons Learned

1. **Never use `CREATE INDEX` without `CONCURRENTLY` on production tables** - the SHARE lock blocks all writes.
2. **lock_timeout is a safety net** - it prevents your migration from causing a growing lock queue.
3. **`pg_cancel_backend` before `pg_terminate_backend`** - always try the gentle approach first.
4. **Cancelled CREATE INDEX leaves invalid indexes** - always check and clean up.
5. **CI should lint for dangerous DDL patterns** - catch these before they reach production.
6. **`flyway:executeInTransaction=false`** is required for CONCURRENTLY operations.
