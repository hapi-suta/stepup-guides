# Scenario 05 - Post-Upgrade Slow Queries

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: After a major version upgrade, queries are
running 10-50x slower than before. EXPLAIN shows
wildly wrong row estimates. The DBA ran pg_upgrade
but forgot to run ANALYZE on the new cluster.
```

---

## Key Concepts for Revision

- **pg_upgrade does not transfer statistics by default** - When you run `pg_upgrade`, it copies table data and schema but does not transfer optimizer statistics from `pg_statistic`. The new cluster starts with no statistics for any table. The planner falls back to default estimates (e.g., assuming every table has 200 rows), leading to terrible plan choices.

- **pg_upgrade --analyze-in-stages** - The `pg_upgrade` tool offers `--analyze-in-stages` which generates a script that runs ANALYZE in priority order: first on the most critical system catalogs, then on smaller tables, then on larger tables. You can also run `vacuumdb --analyze-in-stages --all` after the upgrade manually.

- **The planner relies on pg_statistic** - Statistics include: number of distinct values per column, most common values, histogram boundaries, correlation, and null fraction. Without these, the planner uses hardcoded defaults. For example, it assumes `1/10` selectivity for equality conditions and `1/3` for range conditions, regardless of actual data distribution.

- **ANALYZE collects fresh statistics** - `ANALYZE tablename` reads a sample of the table (default 30,000 rows or `default_statistics_target * 300`) and updates `pg_statistic`. `ANALYZE` without a table name analyzes all tables in the database. `vacuumdb --analyze-only --all` does this across all databases.

- **Post-upgrade checklist** - After every major version upgrade: (1) Run `ANALYZE` on all databases. (2) Check the PostgreSQL log for planner warnings. (3) Monitor query performance for the first few hours. (4) Compare `EXPLAIN` output for critical queries against pre-upgrade plans.

---

## Diagnostic Steps

### Step 1 - Check query plans for row estimate accuracy

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos13_orders WHERE status = 'pending';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos13_orders  (cost=0.00..1000.00 rows=50000 width=...)
   Filter: ((status)::text = 'pending'::text)
   Rows Removed by Filter: 37500
   Actual Rows: 12500
...
```

The estimated rows (50000) is wildly off from actual rows (12500). Without statistics, the planner has no idea about the data distribution.

### Step 2 - Check pg_statistic for missing entries

```sql
SELECT
  c.relname,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_statistic s WHERE s.starelid = c.oid
  ) THEN 'HAS STATS' ELSE 'NO STATS' END AS stat_status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
AND c.relkind = 'r'
AND c.relname LIKE 'chaos13_%'
ORDER BY c.relname;
```

Expected output:

```
      relname       | stat_status
--------------------+-------------
 chaos13_customers  | NO STATS
 chaos13_orders     | NO STATS
(2 rows)
```

Both tables have no statistics. This confirms the post-upgrade state.

### Step 3 - Check the last ANALYZE time

```sql
SELECT relname, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE relname LIKE 'chaos13_%';
```

Expected output (yours will differ):

```
      relname       | last_analyze | last_autoanalyze
--------------------+--------------+------------------
 chaos13_customers  |              |
 chaos13_orders     |              |
(2 rows)
```

Both `last_analyze` and `last_autoanalyze` are NULL, confirming no statistics have been collected since the "upgrade".

---

## Resolution

### Step 1 - Run ANALYZE on the affected tables

Start with the smaller table first:

```sql
ANALYZE chaos13_customers;
```

Expected output:

```
ANALYZE
```

```sql
ANALYZE chaos13_orders;
```

Expected output:

```
ANALYZE
```

### Step 2 - Verify statistics exist now

```sql
SELECT
  c.relname,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_statistic s WHERE s.starelid = c.oid
  ) THEN 'HAS STATS' ELSE 'NO STATS' END AS stat_status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
AND c.relkind = 'r'
AND c.relname LIKE 'chaos13_%'
ORDER BY c.relname;
```

Expected output:

```
      relname       | stat_status
--------------------+-------------
 chaos13_customers  | HAS STATS
 chaos13_orders     | HAS STATS
(2 rows)
```

### Step 3 - Verify improved row estimates

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos13_orders WHERE status = 'pending';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Seq Scan on chaos13_orders  (cost=... rows=12500 width=...)
   Filter: ((status)::text = 'pending'::text)
   Actual Rows: 12500
...
```

The estimated rows now closely matches the actual rows. The planner has accurate statistics.

### Step 4 - Verify last_analyze is set

```sql
SELECT relname, last_analyze
FROM pg_stat_user_tables
WHERE relname LIKE 'chaos13_%';
```

Expected output (yours will differ):

```
      relname       |         last_analyze
--------------------+-------------------------------
 chaos13_customers  | 2026-04-19 12:00:00.000000+00
 chaos13_orders     | 2026-04-19 12:00:01.000000+00
(2 rows)
```

### Step 5 - For a real post-upgrade, analyze all databases

In a real post-upgrade scenario, you would analyze all databases:

```sql
\q
```

```bash
/usr/pgsql-16/bin/vacuumdb --analyze-only --all
```

Expected output (yours will differ):

```
vacuumdb: processing database "stepup_store"
vacuumdb: processing database "postgres"
...
```

This runs ANALYZE across all databases, not just the current one.

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- pg_statistic has entries for chaos13_orders
- pg_statistic has entries for chaos13_customers
- EXPLAIN row estimates are within 2x of actual rows
- last_analyze is set for both tables

---

## Interview Discussion Points

1. **Why does pg_upgrade not transfer statistics?** - Statistics are version-specific internal structures. The format of `pg_statistic` entries can change between major versions. Additionally, the new version's planner may interpret statistics differently. Transferring old statistics could lead to incorrect plan choices. It is safer to regenerate fresh statistics on the new cluster.

2. **What is the impact of missing statistics on a production system?** - The planner defaults to generic estimates (e.g., 200 rows per table, 10% selectivity for equality). For tables with millions of rows, this causes catastrophically bad plans: nested loop joins where hash joins should be used, sequential scans instead of index scans, wrong join ordering. Query times can increase by 100x or more.

3. **What is vacuumdb --analyze-in-stages?** - It runs ANALYZE in three stages: (1) System catalogs and small tables (fast, high impact). (2) Medium tables. (3) Large tables. This ensures the most commonly-queried tables get statistics first, reducing the window of poor performance. Each stage generates progressively more I/O as table sizes increase.

4. **How long does ANALYZE take on a large database?** - ANALYZE reads a sample of `default_statistics_target * 300` rows (default: 30,000 rows) per column. For a table with 10 columns, it samples ~300,000 rows regardless of table size. The time depends on I/O speed: typically a few seconds per table. A 1TB database with 1,000 tables takes roughly 30-60 minutes for a full ANALYZE pass.

5. **Should you run ANALYZE during normal operations?** - The autovacuum daemon runs ANALYZE automatically when enough rows change (default threshold: 10% of the table). For most OLTP workloads, autovacuum handles statistics collection. You should run ANALYZE manually after: bulk loads, pg_upgrade, schema changes, or when you notice bad query plans. Running ANALYZE is lightweight and does not block writes.
