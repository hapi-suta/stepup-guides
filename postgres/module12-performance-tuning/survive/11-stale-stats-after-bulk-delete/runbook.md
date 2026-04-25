# Scenario 11 - Stale Statistics After Bulk Delete

**Severity:** CRITICAL

**Expected Recovery Time:** 5-10 minutes

**Single Node:** NODE1 only

**Based on:** Real production incident - bulk data deletion without ANALYZE caused widespread performance degradation across all application modules.

---

## Alert

```
ALERT: Application performance severely degraded.
All modules are slow. Queries that normally take 5ms
are now taking 2-10 seconds.

The data cleanup team ran a bulk deletion job last night
to purge old support tickets. No other changes were made.

Multiple teams are reporting timeouts.
```

---

## Key Concepts for Revision

- **PostgreSQL query planner depends on statistics** - The planner uses two sources of statistics to decide how to execute queries: `pg_class` (row count and page count per table) and `pg_statistic` (column-level distribution data like most common values, histograms, null fractions). When these are wrong, the planner picks terrible execution plans - choosing sequential scans over index scans, picking wrong join strategies, and misestimating memory needs.

- **ANALYZE is the only way to refresh statistics** - `VACUUM` cleans up dead tuples but does NOT update column statistics. Only `ANALYZE` (or `ANALYZE VERBOSE`) reads a sample of actual table data and updates `pg_statistic`. Autovacuum normally handles this automatically, but if autovacuum is delayed, disabled, or the table changed drastically between runs, statistics go stale.

- **Bulk operations are the #1 cause of stale statistics** - Any operation that inserts, deletes, or updates more than 10% of a table's rows can make the existing statistics dangerously wrong. The planner may think a 5.8 GB table has 8 rows, or that a column with 50,000 distinct values has only 3. This leads to wrong join orders, nested loop joins on large tables, and sequential scans where index scans should be used.

- **pg_stat_user_tables shows when ANALYZE last ran** - The columns `last_analyze` and `last_autoanalyze` show the timestamp of the most recent manual or automatic ANALYZE. If these are NULL for a large table, that table has never had its statistics collected - a red flag.

- **pg_class.reltuples is the planner's row count estimate** - This is the approximate number of live rows the planner uses for cost calculations. If this says 2 when the table actually has 50,000 rows, the planner will choose plans optimized for a tiny table - sequential scans everywhere, nested loop joins, and no parallel query.

- **ANALYZE VERBOSE shows what it does** - The VERBOSE option prints which columns were analyzed, how many rows were sampled, and how many distinct values were found. Use this during incident response so you can confirm the statistics are being rebuilt correctly.

---

## Diagnostic Steps

### Step 1 - Log in to the database server

```bash
ssh -i /path/to/key ec2-user@NODE1_IP
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Connect to the database:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Check what the planner thinks about table sizes

The first thing to check in any "everything is slow" situation is whether the planner's view of the data matches reality.

```sql
SELECT
  relname,
  reltuples::bigint AS planner_row_estimate,
  pg_relation_size(oid) AS actual_bytes,
  pg_size_pretty(pg_relation_size(oid)) AS actual_size
FROM pg_class
WHERE relname IN ('support_tickets', 'orders')
ORDER BY relname;
```

Expected output (yours will differ):

```
     relname       | planner_row_estimate | actual_bytes | actual_size
-------------------+----------------------+--------------+-------------
 orders            |                    8 |      1234567 | 1206 kB
 support_tickets   |                    2 |     75497472 | 72 MB
(2 rows)
```

The planner thinks `support_tickets` has 2 rows but the table is 72 MB. The planner thinks `orders` has 8 rows. These estimates are catastrophically wrong.

### Step 3 - Check when ANALYZE last ran

```sql
SELECT
  relname,
  n_live_tup,
  n_dead_tup,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE relname IN ('support_tickets', 'orders')
ORDER BY relname;
```

Expected output (yours will differ):

```
     relname       | n_live_tup | n_dead_tup | last_analyze | last_autoanalyze
-------------------+------------+------------+--------------+------------------
 orders            |        100 |          0 |              |
 support_tickets   |      50000 |     450000 |              |
(2 rows)
```

`last_analyze` is NULL - no ANALYZE has been recorded. The table has live rows but the planner does not know about them.

### Step 4 - Find ALL tables with missing statistics

This is the query from the real incident. It finds every table larger than 100 MB that has never been analyzed.

```sql
SELECT
  schemaname,
  relname,
  pg_size_pretty(pg_relation_size(relid)) AS size,
  n_live_tup,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE pg_relation_size(relid) > 100 * 1024 * 1024
  AND last_analyze IS NULL
  AND last_autoanalyze IS NULL
ORDER BY pg_relation_size(relid) DESC;
```

This tells you the full blast radius - every table affected.

### Step 5 - Confirm bad execution plans with EXPLAIN

Pick a query that should use an index and check:

```sql
EXPLAIN SELECT * FROM support_tickets WHERE customer_id = 12345;
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on support_tickets  (cost=0.00..1.03 rows=1 width=120)
   Filter: (customer_id = 12345)
(2 rows)
```

The planner chose a sequential scan because it thinks the table has 2 rows. With accurate statistics, this would use `idx_tickets_customer`.

```sql
EXPLAIN SELECT * FROM support_tickets WHERE category = 'billing' AND priority = 'critical';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on support_tickets  (cost=0.00..1.04 rows=1 width=120)
   Filter: ...
(2 rows)
```

Every query is doing a sequential scan. The composite index `idx_tickets_category_priority` is being ignored because the planner thinks scanning 2 rows is cheaper than using an index.

```sql
\q
```

---

## Resolution

### Step 1 - Run ANALYZE VERBOSE on the most critical tables first

Start with the largest and most-queried tables. In the real incident, analyzing the 11 largest tables first restored 60% of normal performance.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ANALYZE VERBOSE support_tickets;
```

Expected output (yours will differ):

```
INFO:  analyzing "public.support_tickets"
INFO:  "support_tickets": scanned 30000 of 30000 pages, containing 50000 live rows and 450000 dead rows; 50000 rows in sample, 50000 estimated total rows
ANALYZE
```

The planner now knows the table has ~50,000 rows, not 2.

```sql
ANALYZE VERBOSE orders;
```

Expected output (yours will differ):

```
INFO:  analyzing "public.orders"
INFO:  "orders": scanned 10 of 10 pages, containing 100 live rows and 0 dead rows; 100 rows in sample, 100 estimated total rows
ANALYZE
```

### Step 2 - Verify the planner's estimates are now correct

```sql
SELECT
  relname,
  reltuples::bigint AS planner_row_estimate,
  pg_size_pretty(pg_relation_size(oid)) AS actual_size
FROM pg_class
WHERE relname IN ('support_tickets', 'orders')
ORDER BY relname;
```

Expected output (yours will differ):

```
     relname       | planner_row_estimate | actual_size
-------------------+----------------------+-------------
 orders            |                  100 | 1206 kB
 support_tickets   |                50000 | 72 MB
(2 rows)
```

Row estimates now match reality.

### Step 3 - Confirm execution plans are using indexes

```sql
EXPLAIN SELECT * FROM support_tickets WHERE customer_id = 12345;
```

Expected output (yours will differ):

```
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Index Scan using idx_tickets_customer on support_tickets  (cost=0.29..8.31 rows=1 width=120)
   Index Cond: (customer_id = 12345)
(2 rows)
```

The planner now uses the index. This alone reduces query time from seconds to milliseconds.

### Step 4 - Check for remaining bottlenecks

After restoring statistics, look for any queries still doing sequential scans unnecessarily:

```sql
SELECT
  relname,
  seq_scan,
  idx_scan,
  seq_tup_read
FROM pg_stat_user_tables
WHERE seq_scan > 0
  AND n_live_tup > 1000
ORDER BY seq_tup_read DESC;
```

If any large table still shows high `seq_scan` with low `idx_scan`, investigate whether a composite index is needed (as was the case in the real incident).

### Step 5 - Re-enable autovacuum on support_tickets

The table had autovacuum disabled. Re-enable it so statistics stay fresh automatically.

```sql
ALTER TABLE support_tickets RESET (autovacuum_enabled);
```

Verify it is re-enabled:

```sql
SELECT reloptions FROM pg_class WHERE relname = 'support_tickets';
```

Expected output:

```
 reloptions
------------

(1 row)
```

No `autovacuum_enabled=false` in reloptions means autovacuum is using the default (on).

### Step 6 - Run ANALYZE on the entire database as a safety net

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ANALYZE VERBOSE;"
```

This ensures every table in the database has fresh statistics.

```bash
exit
```

---

## Prevention

Add these rules to your team's operational runbook:

1. **After any bulk delete, insert, or data migration** - always run `ANALYZE VERBOSE <table>;` as a mandatory post-step
2. **Any operation that touches more than 10% of a table's rows** must be followed by `ANALYZE` on that table
3. **Monitor for tables with stale statistics** using this query (add to your monitoring dashboard):

```sql
SELECT count(*)
FROM   pg_stat_user_tables
WHERE  schemaname = 'public'
AND    pg_relation_size(relid) > 100 * 1024 * 1024
AND    (last_analyze IS NULL AND last_autoanalyze IS NULL);
```

Result should always be 0. Alert if it is not.

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- support_tickets reltuples > 1000 (planner has accurate estimates)
- orders reltuples > 10 (planner has accurate estimates)
- support_tickets query uses index scan (not sequential scan)
- pg_statistic has entries for support_tickets
- autovacuum is re-enabled on support_tickets

---

## Interview Discussion Points

1. **What is the difference between VACUUM and ANALYZE?** - VACUUM reclaims storage from dead tuples (rows that were deleted or updated). It does NOT update planner statistics. ANALYZE reads a sample of rows from the table and updates pg_statistic with column distributions (most common values, histograms, null fractions, distinct counts). The planner only uses ANALYZE output for query planning. You need both, but they solve different problems.

2. **A 5.8 GB table shows reltuples = 8. How do you fix this?** - Run `ANALYZE VERBOSE <table>;` to rebuild statistics from actual data. Then verify with `SELECT reltuples FROM pg_class WHERE relname = '<table>';` to confirm the estimate is now reasonable. Do NOT manually UPDATE pg_class - let ANALYZE set the correct values from sampled data.

3. **How does autovacuum decide when to run ANALYZE?** - Autovacuum triggers an auto-analyze when the number of changed rows (inserts + updates + deletes) exceeds `autovacuum_analyze_threshold + autovacuum_analyze_scale_factor * reltuples`. The default threshold is 50 rows and the default scale factor is 0.1 (10%). So for a 100,000-row table, auto-analyze triggers after 10,050 row changes. For very large tables, you may want to lower the scale factor per-table.

4. **Why did the bulk delete cause wrong statistics instead of just outdated statistics?** - When you delete a large percentage of rows, the physical table size stays roughly the same (dead tuples still occupy space until VACUUM), but the live row count drops dramatically. Without ANALYZE, pg_class.reltuples and pg_statistic still reflect the pre-delete state - or worse, if something resets them. The planner then overestimates or underestimates row counts, picking wrong join strategies and scan methods.

5. **How would you prevent this in a CI/CD pipeline?** - Add a mandatory post-migration step that runs `ANALYZE` on every table touched by the migration. In the migration script itself, add `ANALYZE <table>;` after any bulk INSERT, UPDATE, or DELETE. For Flyway or Liquibase, add this as the final statement in any changeset that modifies more than 10% of a table. In application code, if a batch job deletes or loads large amounts of data, it should call ANALYZE as a post-step.

6. **What does pg_stat_user_tables tell you that pg_class does not?** - pg_stat_user_tables shows operational activity: seq_scan count, idx_scan count, rows inserted/updated/deleted since last stats reset, n_live_tup, n_dead_tup, and critically the timestamps last_vacuum, last_autovacuum, last_analyze, last_autoanalyze. pg_class shows the planner's cached estimates (reltuples, relpages) but not when they were last updated or how active the table is.

7. **You restored statistics on the 11 largest tables and performance improved by 60%. Why not 100%?** - Because some queries have additional bottlenecks beyond stale statistics. In the real incident, one query branch was scanning 94,362 rows because two single-column indexes were being combined inefficiently (BitmapAnd). Creating a composite index on both columns eliminated the remaining bottleneck. Restoring statistics fixes plan selection, but you may still need better indexes for optimal performance.

8. **What is a composite index, and when should you use one instead of separate single-column indexes?** - A composite index indexes multiple columns together in a single B-tree. Use it when queries frequently filter on both columns together (e.g., WHERE category = 'billing' AND priority = 'critical'). PostgreSQL can combine separate single-column indexes using BitmapAnd/BitmapOr, but this is slower than a single composite index because it has to scan two index trees and intersect the results. Column order matters - put the most selective column first.

9. **How do you identify which tables need ANALYZE across an entire database?** - Query pg_stat_user_tables for tables where last_analyze IS NULL AND last_autoanalyze IS NULL AND pg_relation_size(relid) is significant. Also check n_mod_since_analyze (PostgreSQL 13+) which shows how many rows changed since the last analyze. High values relative to n_live_tup mean statistics are going stale.

10. **What monitoring would you set up to catch this before users are affected?** - (1) Alert on tables with no statistics: count tables where last_analyze IS NULL AND size > 100 MB. (2) Alert on n_mod_since_analyze exceeding 50% of n_live_tup. (3) Track seq_scan rate on large tables - a sudden spike in seq_scans on a table that normally uses indexes means something changed. (4) Monitor pg_stat_statements for queries whose mean_exec_time suddenly increases. (5) Dashboard showing reltuples vs pg_relation_size ratio - if a table is 5 GB but reltuples says 8, that is an anomaly.

11. **The original incident mentioned creating a composite index idx_t2688_c205_c101. How did you decide which columns to index?** - By reading the EXPLAIN ANALYZE output of the slow query. The plan showed a BitmapAnd combining two separate index scans on c1000000205 and c1000000101, scanning 94,362 rows to find a small result set. A composite index on (c1000000205, c1000000101) lets PostgreSQL satisfy the filter in a single index lookup instead of scanning two indexes and intersecting results. The most selective column (fewer distinct values matching the filter) goes first.

12. **After a bulk delete, should you run VACUUM before or after ANALYZE?** - Run ANALYZE first to restore planner statistics immediately - this is the faster fix and has the biggest performance impact. Then run VACUUM to reclaim dead tuple storage. VACUUM alone does NOT fix statistics. In an emergency, ANALYZE is the priority.
