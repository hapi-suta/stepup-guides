# Use Exercise 08 - Autovacuum Investigation

Investigate autovacuum behavior on a live database. Find tables that need attention, check if autovacuum is keeping up, and tune settings for a high-churn table.

**Server:** NODE1 only

---

## Setup

**Step 1 - SSH into NODE1.**

```bash
ssh -i /path/to/your-key.pem ec2-user@<NODE1_IP>
```

**Step 2 - Switch to the postgres OS user.**

The `postgres` OS user owns the database process. You need to be this user to run `psql`.

```bash
sudo su - postgres
```

**Step 3 - Connect to labdb.**

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

You should see the `labdb=#` prompt. You are now inside the database and ready to run queries.

---

## Task 1 - Find Tables Autovacuum Has Never Touched

`pg_stat_user_tables` is a system view that tracks vacuum and analyze activity for every user table. When `last_autovacuum` and `last_autoanalyze` are both NULL, PostgreSQL has never automatically maintained that table.

**Step 1 - Run this query inside psql.**

```sql
SELECT
    schemaname,
    relname AS table_name,
    last_autovacuum,
    last_autoanalyze,
    n_live_tup,
    n_dead_tup
FROM pg_stat_user_tables
WHERE last_autovacuum IS NULL
  AND last_autoanalyze IS NULL
ORDER BY n_live_tup DESC;
```

This query lists every table where autovacuum has never run, sorted by row count so the most important ones appear first.

Expected output (yours will differ):

```
 schemaname |    table_name     | last_autovacuum | last_autoanalyze | n_live_tup | n_dead_tup
------------+-------------------+-----------------+------------------+------------+------------
 public     | support_tickets   |                 |                  |       4500 |          0
 public     | orders            |                 |                  |       1200 |          0
...
```

**Answer this question before moving on:**

> Why might a table never have been autovacuumed?

Write your answer here before checking the answer key at the bottom.

---

## Task 2 - Dead Tuple Ratio

Dead tuples are rows that have been updated or deleted but not yet cleaned up. PostgreSQL keeps them around temporarily because older transactions might still need to see the old version. Autovacuum's job is to remove them once they are no longer needed.

**Step 1 - Query the dead tuple ratio for all user tables.**

```sql
SELECT
    relname AS table_name,
    n_live_tup,
    n_dead_tup,
    CASE
        WHEN (n_live_tup + n_dead_tup) > 0
        THEN round(
            (n_dead_tup::numeric / (n_live_tup + n_dead_tup)) * 100,
            2
        )
        ELSE 0
    END AS dead_pct
FROM pg_stat_user_tables
ORDER BY dead_pct DESC;
```

This query calculates what percentage of each table's total rows are dead. A high percentage means the table has bloat that autovacuum has not cleaned up yet.

Expected output (yours will differ):

```
      table_name      | n_live_tup | n_dead_tup | dead_pct
----------------------+------------+------------+----------
 pgbench_accounts     |     100000 |          0 |     0.00
 pgbench_history      |       2581 |          0 |     0.00
 orders               |       1200 |          0 |     0.00
 support_tickets      |       4500 |          0 |     0.00
...
```

**Answer this question before moving on:**

> At what threshold does PostgreSQL trigger autovacuum by default? (Hint: it involves two settings - a scale factor and a threshold.)

Write your answer here before checking the answer key at the bottom.

---

## Task 3 - Autovacuum Timing

Knowing when autovacuum last ran - and how long ago that was - helps you judge whether it is keeping up with writes. A table that is written to heavily but only vacuumed occasionally will accumulate bloat.

**Step 1 - Check autovacuum timing for all tables.**

```sql
SELECT
    relname AS table_name,
    last_autovacuum,
    last_autoanalyze,
    now() - last_autovacuum AS time_since_vacuum,
    now() - last_autoanalyze AS time_since_analyze,
    n_dead_tup,
    autovacuum_count
FROM pg_stat_user_tables
ORDER BY last_autovacuum NULLS LAST;
```

This query shows the last autovacuum timestamp and calculates how long ago it ran. `autovacuum_count` tracks how many times autovacuum has ever run on that table.

Expected output (yours will differ):

```
      table_name      |        last_autovacuum        |       last_autoanalyze        | time_since_vacuum | time_since_analyze | n_dead_tup | autovacuum_count
----------------------+-------------------------------+-------------------------------+-------------------+--------------------+------------+------------------
 pgbench_accounts     | 2026-04-25 10:14:02.123456+00 | 2026-04-25 10:14:03.654321+00 | 00:05:22          | 00:05:21           |          0 |                3
 pgbench_tellers      | 2026-04-25 10:13:58.987654+00 | 2026-04-25 10:13:59.112233+00 | 00:05:26          | 00:05:25           |          0 |                2
...
```

**Answer this question before moving on:**

> If a table gets 10,000 updates per minute but autovacuum only runs every 30 minutes, what happens?

Write your answer here before checking the answer key at the bottom.

---

## Task 4 - Per-Table Autovacuum Tuning

PostgreSQL lets you override the global autovacuum settings on a per-table basis using `ALTER TABLE ... SET (storage_parameter = value)`. This is useful for high-churn tables that need more aggressive cleanup than the defaults provide.

`pgbench_accounts` is a high-write table. The default `autovacuum_vacuum_scale_factor` of 0.2 means autovacuum will not run until 20% of the rows are dead - for a 100,000-row table, that is 20,000 dead tuples before cleanup starts. You will lower this significantly.

**Step 1 - Check the current settings on pgbench_accounts.**

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'pgbench_accounts';
```

This shows any per-table storage options. `NULL` means the table is using the global autovacuum defaults.

Expected output (yours will differ):

```
     relname      | reloptions
------------------+------------
 pgbench_accounts |
(1 row)
```

**Step 2 - Set a lower scale factor and threshold.**

```sql
ALTER TABLE pgbench_accounts
SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 100
);
```

`autovacuum_vacuum_scale_factor = 0.01` means autovacuum will trigger when 1% of the table's rows are dead. `autovacuum_vacuum_threshold = 100` adds a flat minimum of 100 dead tuples before autovacuum fires, which prevents unnecessary runs on nearly-empty tables.

**Step 3 - Verify the settings were applied.**

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'pgbench_accounts';
```

You should now see the `reloptions` column populated with the two settings you just applied.

Expected output (yours will differ):

```
     relname      |                                   reloptions
------------------+---------------------------------------------------------------------------------
 pgbench_accounts | {autovacuum_vacuum_scale_factor=0.01,autovacuum_vacuum_threshold=100}
(1 row)
```

**Answer this question before moving on:**

> What does `autovacuum_vacuum_scale_factor = 0.01` mean in plain English?

Write your answer here before checking the answer key at the bottom.

---

## Task 5 - Bloat Detection

You will deliberately create dead tuples, observe what happens to table size, run VACUUM, and check whether the space is returned to the OS. This is one of the most important things to understand about PostgreSQL storage.

**Step 1 - Check the current size of pgbench_accounts.**

```sql
SELECT
    pg_size_pretty(pg_relation_size('pgbench_accounts')) AS table_size;
```

`pg_relation_size` returns the size of the table's main data file in bytes. `pg_size_pretty` formats it as a human-readable string like `4096 kB`.

Expected output (yours will differ):

```
 table_size
------------
 13 MB
(1 row)
```

Record this number. You will compare it again after the UPDATE and after VACUUM.

**Step 2 - Create dead tuples by updating 10,000 rows.**

```sql
UPDATE pgbench_accounts
SET abalance = abalance + 1
WHERE aid <= 10000;
```

Every updated row leaves behind one dead tuple - the old version of the row. PostgreSQL keeps both versions until the dead one is safe to remove.

Expected output:

```
UPDATE 10000
```

**Step 3 - Check the table size again.**

```sql
SELECT
    pg_size_pretty(pg_relation_size('pgbench_accounts')) AS table_size;
```

The table should be larger now because PostgreSQL wrote new row versions alongside the old dead ones.

Expected output (yours will differ):

```
 table_size
------------
 14 MB
(1 row)
```

**Step 4 - Run VACUUM VERBOSE to clean up dead tuples.**

Exit psql first, because VACUUM VERBOSE output is very long and you want to see all of it cleanly.

```sql
\! /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "VACUUM VERBOSE pgbench_accounts;"
```

Alternatively, you can just run it directly in your current psql session:

```sql
VACUUM VERBOSE pgbench_accounts;
```

`VACUUM VERBOSE` does the same cleanup as regular VACUUM but prints a detailed report of what it found and removed. Look for lines mentioning "dead row versions" and "removable" tuples.

Expected output (yours will differ):

```
INFO:  vacuuming "public.pgbench_accounts"
INFO:  launched 1 parallel vacuum worker for index cleanup (planned: 1)
INFO:  scanned index "pgbench_accounts_pkey" to remove 10000 row versions
DETAIL:  CPU: user: 0.04 s, system: 0.01 s, elapsed: 0.08 s
INFO:  "pgbench_accounts": removed 10000 row versions in 56 pages
DETAIL:  CPU: user: 0.01 s, system: 0.00 s, elapsed: 0.01 s
INFO:  index "pgbench_accounts_pkey" now contains 100000 row versions in 276 pages
...
```

**Step 5 - Check the table size one more time.**

```sql
SELECT
    pg_size_pretty(pg_relation_size('pgbench_accounts')) AS table_size;
```

Expected output (yours will differ):

```
 table_size
------------
 14 MB
(1 row)
```

**Answer this question before moving on:**

> Did the table shrink after VACUUM? Why or why not?

Write your answer here before checking the answer key at the bottom.

---

## Task 6 - Statistics Freshness

PostgreSQL's query planner uses statistics to choose the best execution plan. If statistics are stale, the planner may make poor decisions - like choosing a sequential scan when an index scan would be faster. `n_mod_since_analyze` tracks how many rows have been modified since the last ANALYZE ran.

**Step 1 - Check n_mod_since_analyze for all tables.**

```sql
SELECT
    relname AS table_name,
    n_mod_since_analyze,
    last_autoanalyze,
    now() - last_autoanalyze AS time_since_analyze
FROM pg_stat_user_tables
ORDER BY n_mod_since_analyze DESC NULLS LAST;
```

This query shows which tables have the most unanalyzed modifications. Tables at the top of the list have the stalest statistics.

Expected output (yours will differ):

```
      table_name      | n_mod_since_analyze |        last_autoanalyze       | time_since_analyze
----------------------+---------------------+-------------------------------+--------------------
 pgbench_accounts     |               10000 | 2026-04-25 10:14:03.654321+00 | 00:12:47
 pgbench_history      |                   0 | 2026-04-25 10:13:59.112233+00 | 00:12:51
 orders               |                   0 |                               |
...
```

**Step 2 - Manually refresh statistics on pgbench_accounts.**

```sql
ANALYZE pgbench_accounts;
```

`ANALYZE` scans a sample of the table and updates the statistics in `pg_statistic`. The planner will use these updated numbers for all future queries against this table.

**Step 3 - Confirm n_mod_since_analyze reset to 0.**

```sql
SELECT
    relname AS table_name,
    n_mod_since_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE relname = 'pgbench_accounts';
```

Expected output (yours will differ):

```
     table_name   | n_mod_since_analyze |        last_autoanalyze
------------------+---------------------+-------------------------------
 pgbench_accounts |                   0 | 2026-04-25 10:14:03.654321+00
(1 row)
```

**Answer this question before moving on:**

> What does a high `n_mod_since_analyze` mean, and what command fixes it?

Write your answer here before checking the answer key at the bottom.

---

## Cleanup

When you are done, exit psql and return to ec2-user.

**Step 1 - Exit psql.**

```sql
\q
```

**Step 2 - Exit the postgres OS user.**

```bash
exit
```

You are now back as ec2-user.

---

## Answer Key

**Task 1 - Why might a table never have been autovacuumed?**

Several reasons:
- The table was just created and has never received enough writes to cross the autovacuum threshold (20% dead tuples + 50 dead tuple minimum by default).
- The table is read-only or rarely written to, so no dead tuples accumulate.
- The table has always been below the threshold since the last manual VACUUM or ANALYZE.
- `autovacuum` is disabled on that table via `ALTER TABLE ... SET (autovacuum_enabled = false)`.

Note: a table with 0 live rows and 0 dead rows will never trigger autovacuum because the threshold is never crossed.

---

**Task 2 - At what threshold does PostgreSQL trigger autovacuum by default?**

PostgreSQL triggers autovacuum on a table when the number of dead tuples exceeds:

```
autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor * n_live_tup)
```

The defaults are:
- `autovacuum_vacuum_threshold = 50` (flat minimum)
- `autovacuum_vacuum_scale_factor = 0.2` (20% of live rows)

So for a 100,000-row table: `50 + (0.2 * 100000) = 20,050 dead tuples` before autovacuum fires.

---

**Task 3 - If a table gets 10,000 updates per minute but autovacuum only runs every 30 minutes, what happens?**

The table accumulates 300,000 dead tuples over 30 minutes. Each dead tuple takes up space on disk. The table grows larger (bloat) even though the actual live data has not changed. Queries slow down because PostgreSQL must read past all those dead rows during sequential scans. Index scans also degrade because the index still points to dead row versions that need to be skipped. Eventually the table file becomes much larger than the live data actually requires, and that space is not returned to the OS until VACUUM FULL is run.

---

**Task 4 - What does autovacuum_vacuum_scale_factor = 0.01 mean in plain English?**

It means: "run autovacuum on this table as soon as 1% of its rows are dead." For a 100,000-row table, that is 1,000 dead tuples - much more aggressive than the default 20% (20,000 dead tuples). On high-write tables, this keeps bloat small and prevents the table from growing excessively between vacuum runs.

---

**Task 5 - Did the table shrink after VACUUM? Why or why not?**

No. Regular VACUUM marks the space occupied by dead tuples as reusable, but it does not return that space to the operating system. The table file stays the same size on disk. PostgreSQL will reuse those freed pages for future inserts and updates on that same table.

To return space to the OS, you must run `VACUUM FULL` - but that locks the table exclusively and rewrites it completely, which is disruptive on production. The recommended approach is to let autovacuum run frequently enough that bloat never accumulates significantly in the first place.

---

**Task 6 - What does a high n_mod_since_analyze mean, and what command fixes it?**

A high `n_mod_since_analyze` means many rows have been inserted, updated, or deleted since the last time PostgreSQL collected statistics on that table. The query planner is working with stale information and may choose inefficient execution plans - for example, estimating 100 matching rows when the real answer is 50,000.

The command that fixes it is `ANALYZE table_name;`. This scans a random sample of the table and updates the statistics in `pg_statistic`. For an immediate fix across all tables in a database, use `ANALYZE;` with no table name.
