# Runbook: Autovacuum Blocked

**Scenario:** A long-running transaction is preventing autovacuum from cleaning dead tuples. A table is bloating rapidly. If left unchecked, this leads to performance degradation from bloat and eventual wraparound risk.

**Time limit:** 20 minutes
**Severity:** P2 - Degrading performance, no immediate outage

---

## Symptoms

- `pg_stat_user_tables` shows high and rising `n_dead_tup` for one or more tables
- Autovacuum runs but cannot remove old dead tuples
- Table size is growing faster than expected
- Query performance degrading on the affected table (sequential scans taking longer)

---

## Step 1 - Confirm Autovacuum is Running but Blocked

```sql
-- Is autovacuum currently working on the table?
SELECT
    pid,
    now() - xact_start AS age,
    wait_event,
    left(query, 80) AS query
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker';
```

```sql
-- Is the table still bloating despite autovacuum running?
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'bloat_target';
```

---

## Step 2 - Find the Blocking Transaction

```sql
SELECT
    pid,
    usename,
    application_name,
    now() - xact_start AS txn_age,
    state,
    left(query, 100) AS current_query,
    backend_xid,
    backend_xmin
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY txn_age DESC
LIMIT 10;
```

Look for a session with:
- Very old `txn_age` (more than a few minutes in most cases)
- `state = 'idle in transaction'` or `state = 'active'` with `pg_sleep`

The oldest `backend_xmin` is holding back the vacuum horizon.

---

## Step 3 - Understand the Vacuum Horizon

```sql
-- What is the oldest transaction ID that autovacuum cannot vacuum past?
SELECT
    pid,
    backend_xid,
    backend_xmin,
    now() - xact_start AS txn_age,
    state
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL
ORDER BY txn_age DESC
LIMIT 5;
```

Any dead tuple created before the oldest `backend_xmin` cannot be removed until that transaction finishes.

---

## Step 4 - Evaluate Whether to Kill the Transaction

Ask:
1. Is this a legitimate long-running job (pg_dump, analytics query, ETL)? If yes, do not kill it - schedule a maintenance window.
2. Is this `idle in transaction` with no active query? If yes, it is almost certainly safe to kill.
3. Is this injected load (`pg_sleep`)? Kill it immediately.

```sql
-- Safe check: is the blocking session idle in transaction?
SELECT pid, state, now() - state_change AS idle_for, left(query, 80)
FROM pg_stat_activity
WHERE pid = [BLOCKING_PID];
```

---

## Step 5 - Kill the Blocking Transaction

```sql
-- Soft kill: sends SIGTERM, allows cleanup
SELECT pg_cancel_backend([BLOCKING_PID]);
```

If that does not work:

```sql
-- Hard kill: sends SIGKILL
SELECT pg_terminate_backend([BLOCKING_PID]);
```

---

## Step 6 - Trigger Vacuum Manually

After the blocking transaction is gone, run vacuum immediately rather than waiting for autovacuum:

```sql
VACUUM (VERBOSE, ANALYZE) bloat_target;
```

Expected output (yours will differ):
```
INFO:  vacuuming "public.bloat_target"
INFO:  "bloat_target": removed 200000 row versions in 2778 pages
```

---

## Step 7 - Verify Dead Tuples Are Gone

```sql
SELECT
    relname,
    n_dead_tup,
    last_vacuum,
    pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_stat_user_tables
WHERE relname = 'bloat_target';
```

`n_dead_tup` should be 0 or very low after vacuum completes.

---

## Step 8 - Check for Index Bloat

Bloat also affects indexes. After heavy churn, indexes grow with unused pages:

```sql
-- Check index sizes before and after
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'bloat_target';
```

If indexes are much larger than expected, use `REINDEX CONCURRENTLY`:

```sql
REINDEX TABLE CONCURRENTLY bloat_target;
```

---

## Prevention

Set these parameters to limit idle-in-transaction blocking:

```
idle_in_transaction_session_timeout = 60000  # 1 minute
statement_timeout = 3600000                  # 1 hour for all statements
lock_timeout = 10000                         # 10 seconds for lock waits
```

Monitor with this CloudWatch query or a scheduled pg_stat_user_tables check:

```sql
-- Alert if any table has > 20% dead tuples for more than 10 minutes
SELECT relname, n_dead_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > (n_live_tup + n_dead_tup) * 0.20
ORDER BY n_dead_tup DESC;
```
