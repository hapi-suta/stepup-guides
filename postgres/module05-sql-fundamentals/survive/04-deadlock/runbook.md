# Scenario 04 - Deadlock

**Severity:** HIGH
**Expected Recovery Time:** 10-15 minutes (diagnosis + fix design)
**Single Node:** NODE1 only

---

## Alert

```
ALERT: A deadlock was detected and logged.
Two application threads are failing with 'deadlock detected' errors
when processing concurrent transfers between accounts.
The operations are being retried but keep deadlocking.
```

---

## Key Concepts for Revision

- **What is a deadlock** - A deadlock occurs when two or more transactions each hold a lock that the other needs, and neither can proceed. Transaction A holds Row 1 and wants Row 2. Transaction B holds Row 2 and wants Row 1. PostgreSQL's lock manager detects this cycle and automatically aborts one transaction (the "deadlock victim") with `ERROR: deadlock detected (SQLSTATE 40P01)`.

- **PostgreSQL's response** - PostgreSQL detects deadlocks within `deadlock_timeout` (default 1 second). It aborts the transaction that would be cheapest to roll back (usually the one that started most recently or did least work). The error must be caught by the application, which should then retry the transaction from the beginning.

- **pg_locks** - The view `pg_locks` shows all lock requests in the system: granted and waiting. Combined with `pg_stat_activity`, you can see which query is waiting for which lock held by which pid.

- **The fix: consistent lock ordering** - The root cause of most deadlocks is inconsistent lock ordering. If every transfer always updates the lower account ID first, transactions can never deadlock because they always acquire locks in the same order. Session A: lock 1 then 2. Session B: also lock 1 then 2 - so B waits for A to release row 1 rather than creating a cycle.

- **pg_log deadlock entries** - PostgreSQL logs deadlocks with `DETAIL` lines showing the full cycle: which process waited on which, and which process was selected as the victim. Always check the log first when diagnosing a deadlock.

---

## Diagnostic Steps

### Step 1 - Find deadlock entries in the log

Log in and switch to postgres:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

```bash
sudo -iu postgres
```

Search the PostgreSQL log for deadlock messages:

```bash
grep -i "deadlock" /opt/pgsql/log/postgresql-*.log | tail -20
```

Expected output (yours will differ):

```
2024-01-20 16:00:01 UTC [12345]: ERROR:  deadlock detected
2024-01-20 16:00:01 UTC [12345]: DETAIL:  Process 12345 waits for ShareLock on transaction 789; blocked by process 12346.
        Process 12346 waits for ShareLock on transaction 788; blocked by process 12345.
        Process 12345: UPDATE deadlock_accounts SET balance = balance + 100 WHERE id = 2;
        Process 12346: UPDATE deadlock_accounts SET balance = balance + 100 WHERE id = 1;
2024-01-20 16:00:01 UTC [12345]: HINT:   See server log for query details.
```

The DETAIL shows the cycle. Process 12345 held a lock Process 12346 needed and vice versa.

### Step 2 - Reproduce the scenario to understand the pattern

Open psql:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Look at the accounts table:

```sql
SELECT * FROM deadlock_accounts ORDER BY id;
```

Expected output:

```
 id |   name    | balance
----+-----------+---------
  1 | Account A | 1000.00
  2 | Account B | 2000.00
(2 rows)
```

### Step 3 - See active locks (run during an active deadlock)

If you can catch the deadlock in progress:

```sql
SELECT a.pid, a.query, a.state, l.locktype, l.relation::regclass, l.mode, l.granted
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.relation IS NOT NULL
ORDER BY a.pid;
```

A deadlock in progress will show one `granted = true` and one `granted = false` for the conflicting rows.

---

## Resolution

### Step 1 - Understand the deadlock pattern

The two failing transactions are:

**Transaction A (Transfer: 1 -> 2):**
1. UPDATE WHERE id = 1 (acquires lock on row 1)
2. UPDATE WHERE id = 2 (tries to acquire lock on row 2 - blocked by B)

**Transaction B (Transfer: 2 -> 1):**
1. UPDATE WHERE id = 2 (acquires lock on row 2)
2. UPDATE WHERE id = 1 (tries to acquire lock on row 1 - blocked by A)

Both are stuck. PostgreSQL kills one of them.

### Step 2 - Apply the fix: always lock in row ID order

Rewrite the transfer logic so rows are always updated in ascending `id` order, regardless of which direction the transfer goes.

For a transfer from account 2 to account 1 (i.e., debit account 2, credit account 1), you must still lock account 1 first:

```sql
BEGIN;
```

Lock the lower-ID account first (account 1), then the higher-ID account (account 2):

```sql
SELECT id, balance FROM deadlock_accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
```

The `FOR UPDATE` with `ORDER BY id` locks both rows in a consistent order before any UPDATE statement.

```sql
UPDATE deadlock_accounts SET balance = balance + 100 WHERE id = 1;
```

```sql
UPDATE deadlock_accounts SET balance = balance - 100 WHERE id = 2;
```

```sql
COMMIT;
```

When every transaction that touches multiple rows locks them in the same order (ascending ID), it is impossible for a deadlock cycle to form.

### Step 3 - Verify the table is in a consistent state

```sql
SELECT * FROM deadlock_accounts ORDER BY id;
```

Confirm the balances add up to $3000 (the original total):

```sql
SELECT SUM(balance) AS total FROM deadlock_accounts;
```

Expected output:

```
  total
---------
 3000.00
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
- `deadlock_accounts` table exists
- Total balance in `deadlock_accounts` is 3000 (no money lost or created)
- Deadlock log entry exists confirming the scenario fired

---

## Interview Discussion Points

1. **What is deadlock_timeout and how does it work?** - `deadlock_timeout` (default 1 second) is how long PostgreSQL waits before checking if a lock wait is part of a deadlock cycle. When a session waits for a lock, PostgreSQL does not immediately check for deadlocks (checking is expensive). After `deadlock_timeout`, it checks the wait graph. If a cycle is detected, the victim is chosen and aborted. Lowering this value speeds up deadlock detection but increases overhead on the lock manager.

2. **How do you choose which transaction is the deadlock victim?** - PostgreSQL tries to abort the transaction that has done the least work (fewest locks held, lowest transaction ID). The goal is to minimize wasted work. The application should be designed to retry any transaction that fails with `SQLSTATE 40P01`.

3. **Can advisory locks cause deadlocks?** - Yes. Advisory locks (`pg_advisory_lock(key)`) follow the same lock manager rules as row locks. If two sessions acquire advisory locks in different orders, a deadlock cycle can form just as it does with row locks.

4. **What is the difference between a deadlock and a lock wait timeout?** - A deadlock is a circular dependency that cannot resolve on its own - PostgreSQL must abort one transaction. A lock wait timeout (`lock_timeout`) fires when a session has been waiting for a lock for longer than the configured threshold, even if there is no deadlock. Lock timeouts allow the application to fail fast and retry rather than waiting indefinitely.

5. **How would you design a high-concurrency transfer system to minimize deadlocks?** - Always lock rows in a consistent order (e.g., ascending primary key). Use `SELECT ... FOR UPDATE` at the start of the transaction to grab all needed locks before doing any work. Minimize transaction duration. Consider a two-phase approach: mark both rows as "in transfer" in a single statement before doing the debits and credits.
