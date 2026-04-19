# Scenario 04 - Autovacuum Blocked by Long-Running Transaction

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Dead tuples in blocked_vacuum_demo are not being cleaned up.
VACUUM runs but cannot remove tuples.
A long-running transaction is holding back cleanup.
Identify and terminate the blocking transaction.
```

---

## Key Concepts for Revision

- **Transaction snapshots pin old tuple versions** - Every transaction takes a snapshot of active XIDs when it starts. PostgreSQL cannot remove any dead tuple that is still visible to an active snapshot. Even if a transaction is idle (doing nothing), its snapshot holds back VACUUM from cleaning tuples created before the transaction started.

- **VACUUM VERBOSE reveals pinned tuples** - When VACUUM cannot remove tuples due to an active transaction, it reports "dead row versions cannot be removed yet, oldest xmin: NNNN". The `xmin` value shown is the oldest snapshot that is blocking cleanup.

- **pg_stat_activity is your first stop** - Sort by `xact_start` ascending to find the oldest transaction. An idle session with a transaction open for hours is a classic blocker. It may be an application that started a transaction and then hung, or a monitoring tool that opened a connection with `BEGIN` and never committed.

- **pg_terminate_backend vs pg_cancel_backend** - `pg_cancel_backend(pid)` sends a cancellation signal - it cancels the current query but leaves the connection open. `pg_terminate_backend(pid)` closes the connection entirely. For a hung idle transaction, terminate is usually necessary because there is no query to cancel.

- **idle_in_transaction_session_timeout** - A server-side parameter that automatically terminates sessions that sit idle inside a transaction for too long. Setting this to `10min` or `30min` prevents this scenario from recurring.

---

## Diagnostic Steps

### Step 1 - Try running VACUUM and check its output

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
VACUUM VERBOSE blocked_vacuum_demo;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.blocked_vacuum_demo"
INFO:  "blocked_vacuum_demo": found 5000 removable, 5000 nonremovable row versions in 55 pages
DETAIL:  5000 dead row versions cannot be removed yet, oldest xmin: 748
VACUUM
```

The key line is "cannot be removed yet, oldest xmin: 748". This tells you xmin 748 is the snapshot blocking cleanup.

### Step 2 - Find the blocking transaction

```sql
SELECT pid,
       usename,
       application_name,
       state,
       now() - xact_start AS txn_age,
       left(query, 80) AS current_query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start
LIMIT 5;
```

Expected output (yours will differ):

```
  pid  | usename  | application_name |       state       |   txn_age    |         current_query
-------+----------+------------------+-------------------+--------------+-------------------------------
 12345 | postgres | psql             | idle in transaction | 00:08:23   | SELECT pg_sleep(600);
(1 row)
```

The session has been "idle in transaction" for 8 minutes. This is the blocker.

### Step 3 - Confirm this is the snapshot holding back VACUUM

```sql
SELECT backend_xmin
FROM pg_stat_activity
WHERE pid = 12345;
```

The `backend_xmin` should match or be close to the "oldest xmin" reported by VACUUM VERBOSE.

```bash
exit
```

---

## Resolution

### Step 1 - Terminate the blocking transaction

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Replace `12345` with the actual PID from your diagnostic:

```sql
SELECT pg_terminate_backend(12345);
```

Expected output (yours will differ):

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

### Step 2 - Run VACUUM again

```sql
VACUUM VERBOSE blocked_vacuum_demo;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.blocked_vacuum_demo"
INFO:  "blocked_vacuum_demo": removed 5000 row versions in 55 pages
DETAIL:  0 dead row versions cannot be removed yet, oldest xmin: 812
VACUUM
```

This time "0 dead row versions cannot be removed yet" - VACUUM cleaned everything.

### Step 3 - Verify dead tuples cleared

```sql
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'blocked_vacuum_demo';
```

Expected output (yours will differ):

```
       relname       | n_live_tup | n_dead_tup
---------------------+------------+------------
 blocked_vacuum_demo |       5000 |          0
(1 row)
```

### Step 4 - Prevent recurrence with idle_in_transaction_session_timeout

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '10min';
```

```sql
SELECT pg_reload_conf();
```

This automatically terminates sessions that sit idle inside a transaction for more than 10 minutes.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- No transaction older than 5 minutes
- blocked_vacuum_demo dead tuples below 200
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **How do you find which transaction is blocking VACUUM?** - VACUUM VERBOSE outputs "oldest xmin: NNNN". Cross-reference that with `pg_stat_activity.backend_xmin`. The session whose `backend_xmin` matches is the blocker. Alternatively, sort `pg_stat_activity` by `xact_start` ascending - the oldest transaction is almost always the blocker.

2. **Is terminating a long-running idle transaction safe?** - For an idle-in-transaction session, yes - the transaction has not committed anything, so terminating it simply rolls back any changes it made. The connected application will receive a connection error and should reconnect. Always communicate with the application team before terminating on production.

3. **What is idle_in_transaction_session_timeout and should it always be set?** - Yes, it should almost always be set. It terminates sessions that sit inside an open transaction doing nothing, preventing them from blocking VACUUM and holding back dead tuple cleanup. A reasonable default is 10 to 30 minutes. Setting it to 0 means no timeout.

4. **Can autovacuum be blocked by its own lock acquisition?** - Yes. Autovacuum takes a ShareUpdateExclusiveLock on the table before vacuuming. If another session holds a conflicting lock (like `LOCK TABLE` or `CREATE INDEX`), autovacuum will wait. It will eventually give up after `autovacuum_lock_timeout` and try again later.

5. **What is the difference between the xmin that blocks VACUUM and the xmax on dead tuples?** - xmax on a dead tuple is the transaction that deleted or updated it. The xmin that blocks VACUUM is the snapshot horizon - the oldest active transaction ID. VACUUM cannot remove any tuple whose xmax is greater than the oldest active xmin, because some transaction might still be able to "see" that dead tuple through its snapshot.
