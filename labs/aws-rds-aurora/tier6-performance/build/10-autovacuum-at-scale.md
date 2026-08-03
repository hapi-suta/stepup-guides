# Build 10 - Autovacuum at Scale

**Time:** 45 minutes
**Goal:** Monitor autovacuum activity, identify tables that are bloating or at risk of wraparound, and configure autovacuum aggressively for large tables.
**Prerequisites:** RDS PostgreSQL with a custom parameter group. psql access. `$DB_INSTANCE_ID`, `$REGION` set.

---

## Background

PostgreSQL's MVCC model means every UPDATE creates a new version of a row rather than modifying it in place. The old version becomes a dead tuple. Every DELETE also creates a dead tuple. Autovacuum's job is to reclaim the space occupied by dead tuples and keep statistics fresh for the query planner.

When autovacuum falls behind, three things happen:
1. Tables and indexes bloat (wasted space, slower sequential scans)
2. Statistics go stale (planner chooses bad plans)
3. Transaction ID wraparound approaches (catastrophic: PostgreSQL shuts down to prevent data corruption)

On large tables (100M+ rows), the default autovacuum thresholds wait too long. A table with 100M rows and the default 20% threshold means autovacuum waits until 20M rows are dead. That is a lot of bloat.

---

## Step 1 - Check Autovacuum Configuration

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name "custom-pg16-perf" \
  --query "Parameters[?contains(ParameterName,'autovacuum')].{Name:ParameterName,Value:ParameterValue,Source:Source}" \
  --output table \
  --region "$REGION"
```

Expected output (yours will differ):
```
---------------------------------------------------------------
|                   DescribeDBParameters                      |
+------------------------------------------+--------+--------+
|               Name                        | Value  | Source |
+------------------------------------------+--------+--------+
|  autovacuum                               | 1      | system |
|  autovacuum_analyze_scale_factor          | 0.05   | system |
|  autovacuum_analyze_threshold             | 50     | system |
|  autovacuum_max_workers                   | 3      | system |
|  autovacuum_naptime                       | 60     | system |
|  autovacuum_vacuum_cost_delay             | 20     | system |
|  autovacuum_vacuum_cost_limit             | 200    | system |
|  autovacuum_vacuum_scale_factor           | 0.2    | system |
|  autovacuum_vacuum_threshold              | 50     | system |
|  autovacuum_freeze_max_age                | 200000000 | system |
+------------------------------------------+--------+--------+
```

---

## Step 2 - Monitor Live Autovacuum Activity

Connect to the database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

See which tables autovacuum is currently working on:

```sql
SELECT
    pid,
    datname,
    relid::regclass AS relname,
    phase,
    heap_blks_scanned,
    heap_blks_vacuumed,
    index_vacuum_count,
    num_dead_tuples
FROM pg_stat_progress_vacuum;
```

If nothing is running, this returns empty. That is normal unless a vacuum is actively in progress.

---

## Step 3 - Find Tables That Need Attention

This query identifies the most problematic tables:

```sql
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    autovacuum_count,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
```

Focus on tables where:
- `dead_pct` > 10% (table is bloating)
- `last_autovacuum` is NULL or very old (autovacuum is not keeping up)

---

## Step 4 - Transaction ID Age (Wraparound Risk)

This is the most critical autovacuum metric. A table that has not been frozen in a long time accumulates transaction ID age. When age approaches 2.1 billion, PostgreSQL shuts down to prevent data corruption.

```sql
SELECT
    schemaname,
    relname,
    age(relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(oid)) AS size,
    CASE
        WHEN age(relfrozenxid) > 1500000000 THEN 'CRITICAL - freeze immediately'
        WHEN age(relfrozenxid) > 1000000000 THEN 'WARNING - schedule freeze'
        WHEN age(relfrozenxid) > 500000000 THEN 'WATCH - autovacuum should handle'
        ELSE 'OK'
    END AS status
FROM pg_class
WHERE relkind = 'r'
  AND age(relfrozenxid) > 100000000
ORDER BY age(relfrozenxid) DESC;
```

Also check at the database level:

```sql
SELECT
    datname,
    age(datfrozenxid) AS db_xid_age,
    CASE
        WHEN age(datfrozenxid) > 1500000000 THEN 'CRITICAL'
        WHEN age(datfrozenxid) > 1000000000 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

Expected output (yours will differ):
```
 datname  | db_xid_age | status
----------+------------+--------
 postgres |   14234567 | OK
```

The CloudWatch metric `MaximumUsedTransactionIDs` monitors this at the instance level. Set an alarm at 1.5B (covered in Build 01).

---

## Step 5 - Create Large Tables for Testing

Create tables that simulate a high-throughput OLTP environment:

```sql
-- High-write table (simulates orders in an e-commerce system)
CREATE TABLE IF NOT EXISTS high_write_orders (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_hwo_customer ON high_write_orders(customer_id);
CREATE INDEX idx_hwo_status ON high_write_orders(status);

-- Insert initial data
INSERT INTO high_write_orders (customer_id, amount, status)
SELECT
    (random() * 100000)::INT,
    (random() * 500)::NUMERIC(12,2),
    'pending'
FROM generate_series(1, 500000);

ANALYZE high_write_orders;
```

Simulate continuous updates (creates dead tuples):

```sql
-- Run this multiple times to generate dead tuples
UPDATE high_write_orders
SET status = 'processing', updated_at = now()
WHERE order_id IN (
    SELECT order_id FROM high_write_orders
    WHERE status = 'pending'
    ORDER BY random()
    LIMIT 50000
);

UPDATE high_write_orders
SET status = 'completed', updated_at = now()
WHERE order_id IN (
    SELECT order_id FROM high_write_orders
    WHERE status = 'processing'
    ORDER BY random()
    LIMIT 25000
);
```

Run the UPDATE block 3-4 times to accumulate dead tuples.

---

## Step 6 - Check Dead Tuple Accumulation

```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
    last_autovacuum,
    pg_size_pretty(pg_total_relation_size('high_write_orders')) AS size
FROM pg_stat_user_tables
WHERE relname = 'high_write_orders';
```

Expected output (yours will differ):
```
       relname       | n_live_tup | n_dead_tup | dead_pct | last_autovacuum |  size
---------------------+------------+------------+----------+-----------------+--------
 high_write_orders   |     500000 |     150000 |     23.1 | (null)          | 68 MB
```

23% dead tuples - autovacuum has not run yet (or the threshold is not met).

---

## Step 7 - Set Aggressive Per-Table Autovacuum

For large or high-write tables, override the global autovacuum settings at the table level:

```sql
ALTER TABLE high_write_orders SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 500,
    autovacuum_analyze_scale_factor = 0.005,
    autovacuum_analyze_threshold = 250,
    autovacuum_vacuum_cost_delay = 2,
    autovacuum_vacuum_cost_limit = 400
);
```

Each parameter explained:
- `autovacuum_vacuum_scale_factor = 0.01`: Vacuum when 1% of rows are dead (not the global 20%).
- `autovacuum_vacuum_threshold = 500`: Also vacuum if 500 dead rows exist, regardless of percentage.
- `autovacuum_analyze_scale_factor = 0.005`: Analyze when 0.5% of rows change (keeps statistics fresh).
- `autovacuum_analyze_threshold = 250`: Minimum rows changed before analyzing.
- `autovacuum_vacuum_cost_delay = 2`: Sleep only 2ms between cost periods (less throttling, default is 20ms).
- `autovacuum_vacuum_cost_limit = 400`: Double the cost budget (default 200), allowing more work per period.

Verify the settings were applied:

```sql
SELECT reloptions
FROM pg_class
WHERE relname = 'high_write_orders';
```

Expected output (yours will differ):
```
                                            reloptions
-------------------------------------------------------------------------------------------------------
 {autovacuum_vacuum_scale_factor=0.01,autovacuum_vacuum_threshold=500,autovacuum_analyze_scale_factor=0.005,...}
```

---

## Step 8 - Tune Global Autovacuum Parameters

For environments with many large tables, also tune the global parameters:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters \
    "ParameterName=autovacuum_max_workers,ParameterValue=5,ApplyMethod=pending-reboot" \
    "ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=10,ApplyMethod=immediate" \
    "ParameterName=autovacuum_vacuum_cost_limit,ParameterValue=400,ApplyMethod=immediate" \
    "ParameterName=autovacuum_naptime,ParameterValue=30,ApplyMethod=immediate" \
  --region "$REGION"
```

Each parameter explained:
- `autovacuum_max_workers=5`: Allow 5 parallel autovacuum workers (default 3). Each works on one table.
- `autovacuum_vacuum_cost_delay=10`: Reduce global throttling from 20ms to 10ms.
- `autovacuum_vacuum_cost_limit=400`: Double the global cost budget.
- `autovacuum_naptime=30`: Check for tables needing vacuum every 30 seconds (default 60).

`autovacuum_max_workers` requires a reboot. Apply other changes immediately and reboot during the next maintenance window.

### Console

Use this if you prefer clicking through the AWS Console instead of running the CLI command above.

1. Open the **AWS Console** and go to **RDS** (search "RDS" in the top search bar).
2. In the left sidebar, click **Parameter groups**.
3. Find your parameter group in the list (e.g., `custom-pg16-perf`) and click its name.
4. Click the **Edit parameters** button in the top-right corner of the page. The button row should become editable.
5. In the **Filter parameters** search box, type `autovacuum_vacuum_cost_delay`. The list will narrow to show just that parameter.
6. Click inside the **Value** field next to `autovacuum_vacuum_cost_delay` and change the value to `10`.
7. Clear the search box, then search for `autovacuum_vacuum_cost_limit`. Change its value to `400`.
8. Clear the search box, then search for `autovacuum_naptime`. Change its value to `30`.
9. Clear the search box, then search for `autovacuum_max_workers`. Change its value to `5`.
   - You will see a note next to this parameter saying **Requires restart** (it is a static parameter). The others are dynamic and take effect immediately.
10. Click **Save changes** in the top-right corner. You should see a green success banner: "Parameter group updated successfully."

**After saving:**
- The three dynamic parameters (`autovacuum_vacuum_cost_delay`, `autovacuum_vacuum_cost_limit`, `autovacuum_naptime`) take effect within a minute - no reboot needed.
- `autovacuum_max_workers` will only take effect after you reboot the instance. Schedule this during your next maintenance window. To reboot: go to **Databases**, select your instance, click **Actions** > **Reboot**.

---

## Step 9 - Manually Trigger Vacuum

When autovacuum is behind and you need to reclaim space now:

```sql
-- Vacuum with verbose output to see what it is doing
VACUUM (VERBOSE, ANALYZE) high_write_orders;
```

Expected output (yours will differ):
```
INFO:  vacuuming "public.high_write_orders"
INFO:  scanned index "high_write_orders_pkey" to remove 150000 row versions
INFO:  "high_write_orders": removed 150000 row versions in 2083 pages
INFO:  index "idx_hwo_customer" now contains 500000 row versions in 1389 pages
...
INFO:  "high_write_orders": found 150000 removable, 500000 nonremovable row versions
INFO:  "high_write_orders": removed 150000 dead tuples, 0 remain
```

For wraparound emergencies, trigger aggressive freeze:

```sql
VACUUM (FREEZE, VERBOSE) high_write_orders;
```

`FREEZE`: Marks all tuples as frozen (sets XID to FrozenTransactionId), resetting the XID age to 0. Use when a table's `xid_age` is dangerously high.

---

## Step 10 - Monitor Autovacuum via pg_stat_bgwriter

Track autovacuum efficiency:

```sql
SELECT
    checkpoints_timed,
    checkpoints_req,
    buffers_checkpoint,
    buffers_clean,
    maxwritten_clean,
    buffers_backend,
    buffers_alloc,
    stats_reset
FROM pg_stat_bgwriter;
```

Key indicators:
- `maxwritten_clean > 0`: Background writer is being maxed out. Increase `bgwriter_lru_maxpages`.
- `buffers_backend` much larger than `buffers_clean`: Sessions are writing dirty buffers directly (bgwriter can't keep up). Increase `bgwriter_lru_maxpages` or reduce I/O load.
- `checkpoints_req` much larger than `checkpoints_timed`: Checkpoints are forced by WAL filling up. Increase `max_wal_size`.

---

## Step 11 - Autovacuum Blocking Issues

Autovacuum can be blocked by long-running transactions. When a session holds a transaction open, autovacuum cannot remove dead tuples that are newer than that transaction's snapshot.

Find transactions blocking autovacuum:

```sql
SELECT
    pid,
    now() - xact_start AS transaction_age,
    state,
    left(query, 80) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
ORDER BY transaction_age DESC;
```

If you find long-running transactions blocking autovacuum:

```sql
-- Check if they are idle in transaction (a common problem)
SELECT pid, state, now() - xact_start AS age, query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - xact_start > interval '5 minutes';
```

Set timeouts to prevent this:

```sql
-- Kill idle-in-transaction sessions after 10 minutes
-- Set in parameter group for all sessions
-- idle_in_transaction_session_timeout = 600000  (milliseconds)
```

Or as a one-time check during an incident:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - xact_start > interval '10 minutes';
```

---

## Cleanup

```sql
DROP TABLE IF EXISTS high_write_orders;
```

---

## Summary

You have:
- Identified bloated tables and TXID age risk using pg_stat_user_tables and pg_class
- Applied aggressive per-table autovacuum settings for high-write tables
- Tuned global autovacuum parameters to increase worker count and reduce throttling
- Manually triggered VACUUM with FREEZE for wraparound situations
- Found transactions that block autovacuum and applied timeouts to prevent them

For production: run the dead tuple and TXID age queries weekly. Set a CloudWatch alarm on MaximumUsedTransactionIDs. Apply per-table autovacuum settings on any table that updates or deletes more than 10% of its rows per day.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Dead tuple | Old row version no longer visible to any transaction - must be reclaimed |
| Autovacuum | Background daemon that reclaims dead tuples and updates statistics |
| TXID wraparound | When 32-bit transaction IDs cycle around; PostgreSQL shuts down before this happens |
| Frozen tuple | Row version marked safe against TXID wraparound by setting XID to FrozenTransactionId |
| autovacuum_vacuum_scale_factor | Fraction of live rows that must be dead before vacuum triggers |
| autovacuum_vacuum_cost_delay | Sleep time between cost periods - lower = less throttling, higher I/O impact |
| autovacuum_max_workers | Max concurrent autovacuum processes (each handles one table) |
| idle in transaction | Session that started a transaction but is not executing any query - blocks autovacuum |
