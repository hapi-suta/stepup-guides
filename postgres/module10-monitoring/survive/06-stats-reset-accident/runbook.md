# Scenario 06 - Stats Reset Accident

**Severity:** MEDIUM
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: All monitoring data is gone.
pg_stat_user_tables shows zero counts everywhere.
pg_stat_statements is empty.
Someone ran pg_stat_reset(). Monitoring is blind.
```

---

## Key Concepts for Revision

- **pg_stat_reset()** - This function resets all statistics counters in the current database to zero. Table scan counts, tuple counts, index usage, sequential vs index scans - all gone. It affects `pg_stat_user_tables`, `pg_stat_user_indexes`, `pg_statio_user_tables`, and more. Unlike dropping a table, the data structures still exist - but the accumulated counters are zeroed.

- **pg_stat_statements_reset()** - This resets the `pg_stat_statements` extension, which tracks query-level performance metrics (calls, total_time, rows, shared_blks_hit). Losing this data means you lose your query performance baseline - you cannot compare "before" vs "after" for tuning work.

- **Stats are cumulative, not point-in-time** - PostgreSQL statistics accumulate from the moment they were last reset. There is no "undo" for a stats reset. The only recovery is to wait for new activity to rebuild the counters. This means you lose historical ratios (cache hit ratio, index usage ratio) until enough new data accumulates.

- **stats_reset timestamp** - The `pg_stat_database` view has a `stats_reset` column that records when `pg_stat_reset()` was last called. This is the forensic evidence that a reset occurred and when it happened.

- **Prevention** - Revoke `EXECUTE` on `pg_stat_reset()` from non-superuser roles. Only superusers should be able to reset statistics. In production, consider creating a monitoring role that has read access to stats views but cannot call reset functions.

---

## Diagnostic Steps

### Step 1 - Connect to PostgreSQL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Confirm stats were reset

```sql
SELECT datname, stats_reset
FROM pg_stat_database
WHERE datname = current_database();
```

Expected output (yours will differ):

```
   datname    |          stats_reset
--------------+-------------------------------
 stepup_store | 2026-04-19 10:52:30.123456+00
(1 row)
```

The `stats_reset` timestamp will be very recent - this is when the reset happened.

### Step 3 - Check that table stats are zeroed

```sql
SELECT relname, seq_scan, seq_tup_read, idx_scan, n_tup_ins, n_tup_upd
FROM pg_stat_user_tables
ORDER BY relname
LIMIT 10;
```

Expected output (yours will differ):

```
      relname       | seq_scan | seq_tup_read | idx_scan | n_tup_ins | n_tup_upd
--------------------+----------+--------------+----------+-----------+-----------
 aggressive_vac_demo|        0 |            0 |        0 |         0 |         0
 avac_neglected     |        0 |            0 |        0 |         0 |         0
 ...
```

All counters are zero. This confirms the reset.

### Step 4 - Check if pg_stat_statements was also reset

```sql
SELECT count(*) AS statement_count,
       COALESCE(sum(calls), 0) AS total_calls
FROM pg_stat_statements;
```

Expected output (yours will differ):

```
 statement_count | total_calls
-----------------+-------------
               0 |           0
(1 row)
```

If `statement_count` is 0 or very low, `pg_stat_statements_reset()` was also called.

### Step 5 - Check bgwriter stats

```sql
SELECT checkpoints_timed, checkpoints_req, buffers_checkpoint, buffers_clean
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | buffers_checkpoint | buffers_clean
-------------------+-----------------+--------------------+---------------
                 0 |               0 |                  0 |             0
(1 row)
```

If these are all zero, `pg_stat_reset_shared('bgwriter')` was also called.

```bash
exit
```

---

## Resolution

There is no way to recover lost statistics. The fix is to document what happened, generate activity to rebuild the baseline, and prevent recurrence.

### Step 1 - Document the reset event

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Record the reset timestamp for incident documentation.

```sql
SELECT datname, stats_reset
FROM pg_stat_database
WHERE datname = current_database();
```

Note this timestamp - it tells you and your team exactly when visibility was lost.

### Step 2 - Generate activity to rebuild statistics

Run a few queries against key tables so the stats collectors start accumulating data again.

```sql
SELECT count(*) FROM pg_stat_user_tables;
```

```sql
ANALYZE;
```

Expected output:

```
ANALYZE
```

`ANALYZE` updates the planner statistics (which are separate from the monitoring stats) and also generates scan activity that the stats collector records.

### Step 3 - Verify stats are collecting again

```sql
SELECT relname, seq_scan, n_live_tup, last_analyze
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_scan DESC
LIMIT 5;
```

Expected output (yours will differ):

```
      relname       | seq_scan | n_live_tup |         last_analyze
--------------------+----------+------------+-------------------------------
 avac_neglected     |        1 |       5000 | 2026-04-19 11:05:30.123+00
 ...
```

You should see non-zero `seq_scan` counts. The `last_analyze` column will show the recent ANALYZE timestamp.

### Step 4 - Verify pg_stat_statements is collecting

```sql
SELECT count(*) AS statement_count
FROM pg_stat_statements;
```

Expected output (yours will differ):

```
 statement_count
-----------------
              12
(1 row)
```

The count should be greater than zero - new queries are being tracked.

### Step 5 - Prevent future accidental resets

Revoke the ability to call `pg_stat_reset()` from application roles. Only superusers should have this ability.

```sql
SELECT rolname, rolsuper
FROM pg_roles
WHERE rolsuper = true;
```

Document which roles are superusers. If application connections use a superuser role (which is itself a problem), consider creating a dedicated application role without superuser privileges.

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
- pg_stat_user_tables shows activity (seq_scan > 0 for some tables)
- pg_stat_statements has entries
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **Can you recover statistics after pg_stat_reset()?** - No. The counters are gone. You cannot undo a stats reset. The only recovery is to wait for new activity to rebuild them. On a busy production system, basic table-level stats rebuild within hours, but meaningful ratios (like cache hit ratio over a week) take time to become representative again.

2. **What is the difference between pg_stat_reset() and ANALYZE?** - `pg_stat_reset()` clears runtime activity counters (scan counts, tuple counts, I/O stats). `ANALYZE` updates the planner statistics stored in `pg_statistic` (column value distributions, most common values, histograms). They are completely separate systems. Resetting runtime stats does not affect query plans. Running ANALYZE does not reset runtime counters.

3. **How would you detect that stats were reset if you were not online when it happened?** - Check `pg_stat_database.stats_reset` for the reset timestamp. If your monitoring system stores historical metrics (Prometheus, Datadog, etc.), look for all counters dropping to zero simultaneously - that is a telltale sign of a stats reset vs normal counter behavior.

4. **Should you schedule periodic pg_stat_reset() calls?** - Generally no. Some teams reset stats after a major release to get clean "post-deploy" metrics, but this should be a deliberate, documented decision - not an automated cron job. The cumulative nature of stats is a feature, not a bug. Most monitoring tools compute rates (deltas per second) rather than using raw cumulative values.

5. **What monitoring would you set up to detect a stats reset automatically?** - Monitor the `stats_reset` timestamp in `pg_stat_database`. If it changes, fire an alert. You can also monitor for sudden drops in cumulative counters (like `seq_scan` going from millions to zero). Most monitoring systems can detect counter resets and flag them.
