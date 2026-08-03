# Runbook: Autovacuum Blocked

**Scenario:** A long-running transaction prevents autovacuum from cleaning dead tuples. A table is bloating rapidly. If left unchecked, this leads to performance degradation and eventual TXID wraparound risk.

**Time limit:** 20 minutes
**Severity:** P2 - Degrading performance, no immediate outage

---

## Symptoms

- `pg_stat_user_tables` shows high and rising `n_dead_tup` for one or more tables
- Autovacuum runs but cannot remove old dead tuples
- Table size growing faster than expected
- Query performance degrading on the affected table

---

## Step 1 - Check Dead Tuple Count

```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
    last_autovacuum,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'bloat_target';
```

Expected output:
```
   relname    | n_live_tup | n_dead_tup | dead_pct |      last_autovacuum       | total_size
--------------+------------+------------+----------+----------------------------+------------
 bloat_target |     450000 |     550000 |     55.0 | 2026-06-09 14:20:00+00     | 128 MB
```

---

## Step 2 - Check if Autovacuum is Running

```sql
SELECT pid, now() - xact_start AS age, wait_event, left(query, 80) AS query
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker';
```

---

## Step 3 - Find the Blocking Transaction

```sql
SELECT
    pid,
    usename,
    application_name,
    now() - xact_start AS txn_age,
    state,
    left(query, 100) AS current_query,
    backend_xmin
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY txn_age DESC
LIMIT 10;
```

Look for a session with:
- Very old `txn_age` (more than a few minutes)
- `state = 'idle in transaction'` or `application_name = 'autovacuum_blocker'`

The oldest `backend_xmin` holds back the vacuum horizon. Autovacuum cannot remove any dead tuple created before this transaction's snapshot.

---

## Step 4 - Understand the Vacuum Horizon

```sql
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

---

## Step 5 - Evaluate Whether to Kill the Transaction

Ask:
1. Is this a legitimate long-running job (pg_dump, ETL)? Schedule maintenance.
2. Is this `idle in transaction` with no active query? Safe to kill.
3. Is this the `autovacuum_blocker` application? Kill immediately.

```sql
SELECT pid, state, application_name, now() - state_change AS idle_for, left(query, 80)
FROM pg_stat_activity
WHERE application_name LIKE '%blocker%'
   OR (state = 'idle in transaction' AND now() - xact_start > interval '5 minutes');
```

---

## Step 6 - Kill the Blocking Transaction

Soft kill (sends SIGTERM, allows cleanup):

```sql
SELECT pg_cancel_backend([BLOCKING_PID]);
```

If that does not work, hard kill:

```sql
SELECT pg_terminate_backend([BLOCKING_PID]);
```

Replace `[BLOCKING_PID]` with the actual pid from Step 3.

---

## Step 7 - Run Vacuum Manually

After the blocking transaction is gone, vacuum immediately:

```sql
VACUUM (VERBOSE, ANALYZE) bloat_target;
```

Expected output:
```
INFO:  vacuuming "public.bloat_target"
INFO:  "bloat_target": removed 550000 row versions in 5000 pages
INFO:  "bloat_target": found 550000 removable, 450000 nonremovable row versions
...
```

---

## Step 8 - Verify Dead Tuples Are Gone

```sql
SELECT
    relname,
    n_dead_tup,
    last_vacuum,
    pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_stat_user_tables
WHERE relname = 'bloat_target';
```

`n_dead_tup` should be 0 or very low.

---

## Step 9 - Check for Index Bloat

```sql
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'bloat_target';
```

If indexes are much larger than expected after heavy churn:

```sql
REINDEX TABLE CONCURRENTLY bloat_target;
```

---

## Prevention

Set these parameters:

```
idle_in_transaction_session_timeout = 60000  # 1 minute
statement_timeout = 3600000                  # 1 hour
```

For large tables, tune autovacuum per-table:

```sql
ALTER TABLE bloat_target SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_vacuum_cost_delay = 2
);
```

---

## Post-Incident Check

```sql
SELECT relname, n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```
