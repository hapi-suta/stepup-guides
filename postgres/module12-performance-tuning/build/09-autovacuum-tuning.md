# Build 09 - Autovacuum Tuning for Performance

**Estimated time:** 30-35 minutes

In this lab, you will learn what autovacuum does, why the defaults are too conservative for many workloads, and how to tune it per-table for high-churn tables.

---

## Prerequisites

- PostgreSQL 16 running on your lab server
- Database `labdb` exists
- You can SSH into your server as `ec2-user`

---

## Section 1: What Autovacuum Does

PostgreSQL uses MVCC (Multi-Version Concurrency Control). When you UPDATE or DELETE a row, the old version is not removed immediately - it is marked as "dead." This is by design, because other transactions might still need to see the old version.

Autovacuum has two jobs:

1. **VACUUM** - Finds and reclaims dead tuples so the space can be reused by future INSERTs and UPDATEs
2. **ANALYZE** - Refreshes table statistics so the query planner makes good execution plans

Without autovacuum, your tables would grow forever and your queries would get slower over time.

### Step 1: Log in to your server

```bash
ssh -i your-key.pem ec2-user@YOUR_SERVER_IP
```

### Step 2: Switch to the postgres user

```bash
sudo su - postgres
```

### Step 3: Connect to labdb

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

### Step 4: Check current autovacuum settings

```sql
SELECT name, setting
FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;
```

Expected output (yours will differ):

```
                 name                  |  setting
---------------------------------------+-----------
 autovacuum                            | on
 autovacuum_analyze_scale_factor       | 0.1
 autovacuum_analyze_threshold          | 50
 autovacuum_freeze_max_age             | 200000000
 autovacuum_max_workers                | 3
 autovacuum_multixact_freeze_max_age   | 400000000
 autovacuum_naptime                    | 60
 autovacuum_vacuum_cost_delay          | 2
 autovacuum_vacuum_cost_limit          | -1
 autovacuum_vacuum_insert_scale_factor | 0.2
 autovacuum_vacuum_insert_threshold    | 1000
 autovacuum_vacuum_scale_factor        | 0.2
 autovacuum_vacuum_threshold           | 50
 autovacuum_work_mem                   | -1
(14 rows)
```

The important ones for this lab are:

- `autovacuum_vacuum_threshold` (50) - The base number of dead tuples before vacuum considers running
- `autovacuum_vacuum_scale_factor` (0.2) - The fraction of the table that must be dead tuples
- `autovacuum_analyze_threshold` (50) - Same idea but for ANALYZE
- `autovacuum_analyze_scale_factor` (0.1) - Same idea but for ANALYZE

---

## Section 2: Understanding Autovacuum Triggers

Autovacuum does not run constantly. It checks each table periodically and decides whether to vacuum or analyze based on a formula.

### The VACUUM trigger formula

```
Trigger when dead tuples >= threshold + (scale_factor x reltuples)
```

With the defaults:

```
Trigger when dead tuples >= 50 + (0.2 x reltuples)
```

### Example: a table with 1,000,000 rows

```
50 + (0.2 x 1,000,000) = 200,050 dead tuples
```

That means autovacuum will not run until **200,050 rows** (20% of the table) are dead. For a large, busy table, that is far too late - you will accumulate massive bloat before autovacuum kicks in.

### The ANALYZE trigger formula

```
Trigger when changed tuples >= 50 + (0.1 x reltuples)
```

For the same 1M row table:

```
50 + (0.1 x 1,000,000) = 100,050 changed tuples
```

ANALYZE triggers at 10% changes. This means the query planner might be using stale statistics for a long time on large tables.

### Why the defaults are conservative

PostgreSQL ships with conservative defaults because they work for most small databases out of the box. But for tables with millions of rows and high update rates, you need to lower the scale factor so autovacuum runs more frequently.

---

## Section 3: Creating a High-Churn Test Table

You will create a table, fill it with data, and then update rows to create dead tuples. This lets you watch autovacuum in action.

### Step 1: Create the test table

Run this in your psql session:

```sql
CREATE TABLE churn_test (
    id SERIAL PRIMARY KEY,
    status TEXT,
    updated_at TIMESTAMP DEFAULT now()
);
```

Expected output (yours will differ):

```
CREATE TABLE
```

### Step 2: Insert 100,000 rows

```sql
INSERT INTO churn_test (status)
SELECT 'active'
FROM generate_series(1, 100000);
```

The `generate_series` function creates 100,000 numbered rows. Each gets `status = 'active'`.

Expected output (yours will differ):

```
INSERT 0 100000
```

### Step 3: Check the table statistics

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE relname = 'churn_test';
```

Expected output (yours will differ):

```
   relname   | n_live_tup | n_dead_tup | last_autovacuum | last_autoanalyze
-------------+------------+------------+-----------------+------------------
 churn_test  |     100000 |          0 |                 |
(1 row)
```

You have 100,000 live tuples and 0 dead tuples. The `last_autovacuum` column is empty because autovacuum has not run on this table yet (autoanalyze may have already run after the INSERT).

### Step 4: Calculate when autovacuum would trigger

With the defaults (threshold=50, scale_factor=0.2):

```
50 + (0.2 x 100,000) = 20,050 dead tuples
```

So you need to create at least 20,050 dead tuples before autovacuum will vacuum this table.

### Step 5: Update 50,000 rows to create dead tuples

```sql
UPDATE churn_test SET status = 'updated', updated_at = now() WHERE id <= 50000;
```

Expected output (yours will differ):

```
UPDATE 50000
```

Each updated row creates one dead tuple (the old version) and one new live tuple.

### Step 6: Check the statistics again

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'churn_test';
```

Expected output (yours will differ):

```
   relname   | n_live_tup | n_dead_tup | last_autovacuum
-------------+------------+------------+-----------------
 churn_test  |     100000 |      50000 |
(1 row)
```

You have 50,000 dead tuples. That exceeds the threshold of 20,050, so autovacuum should trigger on the next check cycle (every 60 seconds by default).

### Step 7: Wait for autovacuum and check again

Wait about 60-90 seconds, then run:

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'churn_test';
```

Expected output (yours will differ):

```
   relname   | n_live_tup | n_dead_tup | last_autovacuum
-------------+------------+------------+-------------------------------
 churn_test  |     100000 |          0 | 2026-04-25 10:22:45.123456+00
(1 row)
```

Once `last_autovacuum` shows a timestamp and `n_dead_tup` drops to 0, autovacuum has cleaned up the dead tuples. If it has not run yet, wait another minute and check again.

---

## Section 4: Per-Table Autovacuum Tuning

The global defaults apply to every table. But high-churn tables need more aggressive settings. You can override autovacuum behavior on a per-table basis.

### Step 1: Set aggressive vacuum scale factor for this table

```sql
ALTER TABLE churn_test SET (autovacuum_vacuum_scale_factor = 0.01);
```

This means autovacuum will trigger at 1% dead tuples instead of the default 20%.

Expected output (yours will differ):

```
ALTER TABLE
```

### Step 2: Set aggressive analyze scale factor

```sql
ALTER TABLE churn_test SET (autovacuum_analyze_scale_factor = 0.005);
```

This triggers ANALYZE at 0.5% changed tuples instead of 10%. This keeps the planner's statistics fresh.

Expected output (yours will differ):

```
ALTER TABLE
```

### Step 3: Calculate the new trigger point

With the new settings:

```
Vacuum: 50 + (0.01 x 100,000) = 1,050 dead tuples
Analyze: 50 + (0.005 x 100,000) = 550 changed tuples
```

Now autovacuum will trigger after just 1,050 dead tuples instead of 20,050.

### Step 4: Verify the per-table settings

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'churn_test';
```

Expected output (yours will differ):

```
   relname   |                            reloptions
-------------+-------------------------------------------------------------------
 churn_test  | {autovacuum_vacuum_scale_factor=0.01,autovacuum_analyze_scale_factor=0.005}
(1 row)
```

### Step 5: Test the aggressive settings

Update just 2,000 rows (2% of the table):

```sql
UPDATE churn_test SET status = 'changed', updated_at = now() WHERE id BETWEEN 1 AND 2000;
```

Expected output (yours will differ):

```
UPDATE 2000
```

### Step 6: Check dead tuples

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'churn_test';
```

You should see 2,000 dead tuples. Since 2,000 > 1,050 (our new threshold), autovacuum will trigger on the next check cycle. Wait 60-90 seconds and check again - `n_dead_tup` should drop to 0.

---

## Section 5: Cost-Based Vacuum Delay

Autovacuum is designed to be polite. It does a little work, then pauses so it does not overwhelm the disk I/O and CPU. This is controlled by cost-based vacuum delay settings.

### Step 1: Check current throttling settings

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('autovacuum_vacuum_cost_delay', 'autovacuum_vacuum_cost_limit', 'vacuum_cost_limit')
ORDER BY name;
```

Expected output (yours will differ):

```
             name              | setting | unit
-------------------------------+---------+------
 autovacuum_vacuum_cost_delay  | 2       | ms
 autovacuum_vacuum_cost_limit  | -1      |
 vacuum_cost_limit             | 200     |
(3 rows)
```

Here is how it works:

- **vacuum_cost_limit** (200) - After accumulating 200 units of "cost," vacuum pauses
- **autovacuum_vacuum_cost_delay** (2ms) - Each pause lasts 2 milliseconds
- **autovacuum_vacuum_cost_limit** (-1) - The -1 means "use the global vacuum_cost_limit" (200)

The "cost" is based on what vacuum does:
- Reading a page from disk cache = 1 cost unit
- Reading a page from actual disk = 10 cost units
- Dirtying (modifying) a page = 20 cost units

With the defaults, autovacuum does 200 units of work, pauses for 2ms, does 200 more, pauses, and so on. This makes vacuum slow but gentle.

### Step 2: Set aggressive vacuum settings for the test table

For tables that need fast cleanup, you can disable the delay and raise the cost limit:

```sql
ALTER TABLE churn_test SET (autovacuum_vacuum_cost_delay = 0);
```

Setting cost_delay to 0 means no pauses at all - vacuum runs at full speed.

```sql
ALTER TABLE churn_test SET (autovacuum_vacuum_cost_limit = 2000);
```

Raising the cost limit to 2000 (10x the default) means vacuum does much more work before each pause. Combined with a delay of 0, this makes vacuum run as fast as it can.

Expected output (yours will differ):

```
ALTER TABLE
```

### When is this safe?

- **NVMe or SSD storage** - Safe to raise cost_limit to 800-2000 and lower delay
- **Spinning disks (HDD)** - Be more conservative (cost_limit 400-800, delay 5-10ms)
- **Off-peak hours** - You can be more aggressive when fewer users are on the system

### Step 3: Verify all per-table settings

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'churn_test';
```

Expected output (yours will differ):

```
   relname   |                                         reloptions
-------------+--------------------------------------------------------------------------------------------
 churn_test  | {autovacuum_vacuum_scale_factor=0.01,autovacuum_analyze_scale_factor=0.005,autovacuum_vacuum_cost_delay=0,autovacuum_vacuum_cost_limit=2000}
(1 row)
```

---

## Section 6: Monitoring Autovacuum Activity

In production, you want a query that shows which tables have the most dead tuples and when they were last vacuumed.

### Step 1: Run the monitoring query

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(n_dead_tup::numeric / GREATEST(n_live_tup, 1) * 100, 1) AS dead_pct,
       last_autovacuum,
       last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC;
```

This query:

- Lists all user tables that have at least 1 dead tuple
- Calculates `dead_pct` - the percentage of dead tuples relative to live tuples
- Uses `GREATEST(n_live_tup, 1)` to avoid division by zero
- The `::numeric` cast ensures proper decimal division instead of integer division
- Sorts by most dead tuples first, so the tables needing attention are at the top

Expected output (yours will differ):

```
    relname     | n_live_tup | n_dead_tup | dead_pct |        last_autovacuum        |       last_autoanalyze
----------------+------------+------------+----------+-------------------------------+-------------------------------
 pgbench_accounts|   1000000 |       1523 |      0.2 | 2026-04-25 10:18:32.456+00    | 2026-04-25 10:18:33.789+00
 churn_test     |     100000 |        412 |      0.4 | 2026-04-25 10:25:01.234+00    | 2026-04-25 10:25:02.567+00
(2 rows)
```

If the query returns no rows, all tables are fully vacuumed. That is fine - it means autovacuum is keeping up.

### Step 2: Create some dead tuples so the query has data

If the previous query returned no rows, run this:

```sql
UPDATE churn_test SET status = 'monitoring_test', updated_at = now() WHERE id BETWEEN 1 AND 5000;
```

Then re-run the monitoring query from Step 1. You should now see `churn_test` with dead tuples.

---

## Section 7: Detecting Table Bloat with pgstattuple

Even after VACUUM runs, the table file does not shrink. VACUUM marks space as reusable, but the file stays the same size on disk. Over time, if dead tuples are created faster than vacuum can process them, the table becomes "bloated" - full of empty space.

### Step 1: Install the pgstattuple extension

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

The `IF NOT EXISTS` guard prevents an error if the extension is already installed.

Expected output (yours will differ):

```
CREATE EXTENSION
```

### Step 2: Check table bloat

```sql
SELECT * FROM pgstattuple('churn_test');
```

Expected output (yours will differ):

```
 table_len  | tuple_count | tuple_len  | tuple_percent | dead_tuple_count | dead_tuple_len | dead_tuple_percent | free_space | free_percent
------------+-------------+------------+---------------+------------------+----------------+--------------------+------------+--------------
  11075584  |      100000 |    6400000 |         57.79 |             5000 |         320000 |               2.89 |    1245184 |        11.24
(1 row)
```

Key columns explained:

- **table_len** - Total size of the table file on disk (in bytes)
- **tuple_count** - Number of live tuples
- **dead_tuple_count** - Number of dead tuples that vacuum has not yet reclaimed
- **dead_tuple_percent** - Percentage of the table occupied by dead tuples
- **free_space** - Space previously freed by VACUUM, available for reuse
- **free_percent** - What percentage of the table is free space

### Step 3: Understand what VACUUM does (and does not do)

**What VACUUM does:**
- Marks dead tuples as free space
- That free space is reused by future INSERTs and UPDATEs
- This is a lightweight operation that does not lock the table

**What VACUUM does NOT do:**
- It does not shrink the table file on disk
- It does not return free space to the operating system
- If a table grew to 1GB due to bloat, VACUUM will free space internally, but the file stays 1GB

### Step 4: When the table is too bloated

If `free_percent` is very high (above 30-40%), the table has significant bloat. At that point, you have two options:

**Option A: pg_repack (production-safe)**

pg_repack rewrites the table in the background without taking a heavy lock. It is safe to run during business hours. You would install it as an extension and run:

```
-- This is for reference only - pg_repack is not installed on this lab server
-- pg_repack --table churn_test -d labdb
```

**Option B: VACUUM FULL (last resort)**

VACUUM FULL rewrites the entire table and reclaims all the space, but it takes an **ACCESS EXCLUSIVE lock**. This means:

- No reads allowed during the operation
- No writes allowed during the operation
- On a large table, this could take minutes or hours

```sql
-- DO NOT run this on production during business hours
-- VACUUM FULL churn_test;
```

Only use VACUUM FULL during maintenance windows when the table is not in use.

### Step 5: Run pgstattuple after vacuum

If autovacuum has not run yet, trigger a manual vacuum:

```sql
VACUUM churn_test;
```

Expected output (yours will differ):

```
VACUUM
```

Now check the stats again:

```sql
SELECT dead_tuple_count, dead_tuple_percent, free_space, free_percent
FROM pgstattuple('churn_test');
```

Expected output (yours will differ):

```
 dead_tuple_count | dead_tuple_percent | free_space | free_percent
------------------+--------------------+------------+--------------
                0 |                  0 |    1565184 |        14.13
(1 row)
```

Notice: `dead_tuple_count` is 0, but `free_percent` went up. The dead tuples were converted to free space. The file did not shrink - the space is just marked as available for reuse.

---

## Cleanup

### Step 1: Drop the test table

```sql
DROP TABLE churn_test;
```

Expected output (yours will differ):

```
DROP TABLE
```

### Step 2: Exit psql

```
\q
```

### Step 3: Exit the postgres user

```bash
exit
```

You are now back as `ec2-user`.

---

## Summary

In this lab, you learned:

1. **Autovacuum has two jobs** - VACUUM reclaims dead tuples, ANALYZE refreshes statistics
2. **The default scale factor (0.2) is too conservative** for large tables - it waits until 20% of rows are dead
3. **Per-table tuning** lets you set aggressive settings (scale_factor = 0.01) on high-churn tables without affecting the rest of the database
4. **Cost-based vacuum delay** controls how fast vacuum runs - lower delay and higher cost limit for SSDs/NVMe
5. **VACUUM does not shrink files** - it marks space for reuse but the table file stays the same size on disk
6. **pgstattuple** shows you the real bloat picture - dead tuples, free space, and percentages
7. **pg_repack** is the production-safe way to reclaim bloated space, while **VACUUM FULL** is the last resort (requires an exclusive lock)
