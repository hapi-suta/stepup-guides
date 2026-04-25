# Build 10 - pg_stat Views - Your Production Dashboard

**Estimated time:** 30-35 minutes

PostgreSQL ships with a set of statistics views that tell you exactly what is happening inside your database. Think of them as a live dashboard - they show you running queries, table health, cache performance, and more. In this lab you will query six of these views and learn what each one reveals.

---

## Prerequisites

- SSH access to your lab server
- PostgreSQL 16 running at `/opt/pgsql/data`
- Database `labdb` created from a previous lab
- An `orders` table with data (from earlier labs)

---

## Section 1: pg_stat_activity - What is Running Right Now

This view shows every connection to your PostgreSQL server - who is connected, what they are running, and how long they have been running it. This is the first place you look when something feels slow.

### Step 1: Log into your server

Open a terminal and SSH into your lab server.

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_SERVER_IP
```

### Step 2: Switch to the postgres user

The `su -` command switches you to the postgres user. The dash loads that user's environment.

```bash
sudo su - postgres
```

### Step 3: Connect to labdb

Start psql and connect to your lab database. The `-d` flag specifies which database to connect to.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

### Step 4: Query all active (non-idle) sessions

This query filters out idle connections so you only see sessions that are actually doing something. The `state` column tells you what stage the session is in.

```sql
SELECT pid, usename, state, wait_event_type, wait_event,
       left(query, 60) AS query, query_start
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;
```

Expected output (yours will differ):

```
  pid  | usename  | state  | wait_event_type | wait_event |                          query                           |         query_start
-------+----------+--------+-----------------+------------+----------------------------------------------------------+------------------------------
 12345 | postgres | active |                 |            | SELECT pid, usename, state, wait_event_type, wait_event, | 2026-04-25 10:15:32.123456-04
(1 row)
```

Here is what each column means:

- **pid** - The process ID of this connection. You need this to cancel or terminate a query.
- **state** - Where the session is right now: `active` (running a query), `idle` (connected but doing nothing), `idle in transaction` (inside a BEGIN block but not running a query).
- **wait_event_type** - If the session is waiting, this tells you what category of wait (Lock, IO, Client, etc.). NULL means not waiting.
- **wait_event** - The specific event being waited on. Combined with wait_event_type, this tells you exactly what is blocking progress.
- **query** - The last (or current) SQL statement. We use `left(query, 60)` to truncate long queries so the output fits on screen.
- **query_start** - When the current query started. Subtract this from `now()` to see how long it has been running.

### Step 5: Find long-running queries

This query shows anything running longer than 5 seconds. The `age()` function calculates elapsed time. In production, queries running longer than a few seconds often deserve investigation.

```sql
SELECT pid, usename, state,
       age(clock_timestamp(), query_start) AS runtime,
       left(query, 60) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND query_start < now() - interval '5 seconds'
ORDER BY query_start;
```

You will likely see zero rows right now because nothing is running long. That is normal - this query is most useful during incidents.

### Step 6: Find "idle in transaction" sessions

An "idle in transaction" session has started a transaction (BEGIN) but is sitting there doing nothing. This holds locks and prevents VACUUM from cleaning up dead rows. These are a common source of production problems.

```sql
SELECT pid, usename, state,
       age(clock_timestamp(), xact_start) AS xact_duration,
       left(query, 60) AS last_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY xact_start;
```

### Step 7: Cancel vs terminate a query

PostgreSQL gives you two ways to stop a query:

- `pg_cancel_backend(pid)` - Sends a cancel signal. The query stops but the connection stays open. **Try this first.** It is the polite option.
- `pg_terminate_backend(pid)` - Kills the entire connection. The client gets disconnected. **Use this only if cancel does not work.**

To cancel a query (replace 12345 with a real PID):

```sql
SELECT pg_cancel_backend(12345);
```

To terminate a connection (last resort):

```sql
SELECT pg_terminate_backend(12345);
```

Do not run these right now unless you have a stuck query. Just know they exist.

---

## Section 2: pg_stat_statements - The Most Important Extension

pg_stat_statements tracks execution statistics for every SQL statement your server runs. It records how many times each query ran, how long it took, and how many rows it touched. This is the single most valuable tool for finding slow queries in production.

It is an extension, not a built-in view, so you need to install it.

### Step 1: Create the extension

Run this inside psql. The `IF NOT EXISTS` guard prevents an error if it is already installed.

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

You may see this error:

```
ERROR:  pg_stat_statements must be loaded via shared_preload_libraries
```

That means the extension needs to be loaded at server startup. Continue to Step 2.

### Step 2: Add pg_stat_statements to shared_preload_libraries

This command writes the setting to `postgresql.auto.conf`. The extension requires a restart because it allocates shared memory at startup.

```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
```

### Step 3: Exit psql

```sql
\q
```

### Step 4: Restart PostgreSQL

The `-D` flag points to your data directory. A restart is required because shared_preload_libraries only takes effect at startup.

```bash
/usr/pgsql-16/bin/pg_ctl restart -D /opt/pgsql/data
```

Expected output (yours will differ):

```
waiting for server to shut down.... done
server stopped
waiting for server to start.... done
server started
```

### Step 5: Reconnect to labdb

```bash
/usr/pgsql-16/bin/psql -d labdb
```

### Step 6: Create the extension again

Now that the library is loaded, this will succeed.

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Expected output (yours will differ):

```
CREATE EXTENSION
```

### Step 7: Run a few queries to generate data

Run these queries so pg_stat_statements has something to track.

```sql
SELECT count(*) FROM orders;
SELECT * FROM orders WHERE order_id = 1;
SELECT status, count(*) FROM orders GROUP BY status;
SELECT count(*) FROM orders;
SELECT count(*) FROM orders;
```

### Step 8: View top 5 queries by total execution time

This is the query you will use most in production. It shows which queries are consuming the most total time on your server.

```sql
SELECT left(query, 50) AS query,
       calls,
       round(total_exec_time::numeric, 1) AS total_ms,
       round(mean_exec_time::numeric, 1) AS mean_ms,
       rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

Expected output (yours will differ):

```
                       query                        | calls | total_ms | mean_ms | rows
----------------------------------------------------+-------+----------+---------+------
 SELECT count(*) FROM orders                        |     3 |      2.5 |     0.8 |    3
 SELECT status, count(*) FROM orders GROUP BY status|     1 |      1.2 |     1.2 |    3
 SELECT * FROM orders WHERE order_id = $1           |     1 |      0.3 |     0.3 |    1
 CREATE EXTENSION IF NOT EXISTS pg_stat_statements  |     1 |      0.2 |     0.2 |    0
(4 rows)
```

Notice that PostgreSQL normalizes queries - it replaces literal values with `$1`, `$2`, etc. This groups identical queries with different parameters together.

### Step 9: Reset statistics

When you want a fresh start (for example, after a deployment), reset all counters.

```sql
SELECT pg_stat_statements_reset();
```

---

## Section 3: pg_stat_user_tables - Table Health

This view shows health metrics for every table you own. It tells you whether queries are using indexes or doing full table scans, how many dead rows are waiting for cleanup, and when autovacuum last ran.

### Step 1: Check scan ratios and dead tuples

This query shows the most important table health indicators. You want `idx_scan` to be much higher than `seq_scan` for tables that get queried frequently.

```sql
SELECT relname,
       seq_scan,
       idx_scan,
       n_live_tup,
       n_dead_tup,
       last_autovacuum,
       last_autoanalyze
FROM pg_stat_user_tables
ORDER BY seq_scan DESC;
```

Expected output (yours will differ):

```
 relname  | seq_scan | idx_scan | n_live_tup | n_dead_tup |        last_autovacuum        |       last_autoanalyze
----------+----------+----------+------------+------------+-------------------------------+-------------------------------
 orders   |       12 |        3 |       1000 |          5 | 2026-04-25 09:30:00.123456-04 | 2026-04-25 09:30:01.234567-04
 products |        4 |        1 |        200 |          0 |                               |
(2 rows)
```

Here is what to look for:

- **seq_scan vs idx_scan** - If seq_scan is high and idx_scan is low, your queries are doing full table scans. You probably need an index.
- **n_live_tup** - Number of live (current) rows in the table.
- **n_dead_tup** - Number of dead rows waiting for VACUUM to clean up. If this is high relative to n_live_tup, autovacuum may be falling behind.
- **last_autovacuum** - When autovacuum last cleaned this table. NULL means it has never run on this table.
- **last_autoanalyze** - When autovacuum last updated statistics. Stale statistics lead to bad query plans.

### Step 2: The diagnostic query - tables that need attention

This query calculates the percentage of index scans and flags tables where seq_scans dominate.

```sql
SELECT relname,
       seq_scan,
       idx_scan,
       CASE WHEN (seq_scan + idx_scan) > 0
            THEN round(100.0 * idx_scan / (seq_scan + idx_scan), 1)
            ELSE 0
       END AS idx_scan_pct,
       n_dead_tup,
       n_live_tup
FROM pg_stat_user_tables
WHERE (seq_scan + idx_scan) > 0
ORDER BY idx_scan_pct ASC;
```

Tables with a low `idx_scan_pct` are candidates for new indexes.

---

## Section 4: pg_stat_user_indexes - Index Usage

This view tells you which indexes are being used and which are not. Unused indexes waste disk space, slow down writes (every INSERT/UPDATE/DELETE must update every index), and add work for VACUUM.

### Step 1: Find unused indexes

Any index with `idx_scan = 0` has never been used for a query since the last statistics reset. These are candidates for removal.

```sql
SELECT schemaname, relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

Expected output (yours will differ):

```
 schemaname | relname | indexrelname       | idx_scan | index_size
------------+---------+--------------------+----------+------------
 public     | orders  | idx_orders_notes   |        0 | 32 kB
(1 row)
```

### Step 2: Find heavily-used indexes

These are your most valuable indexes. Make sure they stay healthy.

```sql
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY idx_scan DESC;
```

### Step 3: Calculate wasted space from unused indexes

This query sums up the total space used by indexes that have never been scanned.

```sql
SELECT pg_size_pretty(sum(pg_relation_size(indexrelid))) AS total_wasted
FROM pg_stat_user_indexes
WHERE idx_scan = 0;
```

In production databases, unused indexes can waste gigabytes of space. Always check this view before and after adding new indexes.

---

## Section 5: pg_statio_user_tables - Cache Hit Ratio

PostgreSQL keeps frequently-accessed data in shared buffers (RAM). When a query needs a block of data, it first checks shared buffers. If the block is there, that is a "hit." If not, PostgreSQL reads it from disk - that is a "read." You want almost everything to come from cache.

### Step 1: Calculate cache hit ratio per table

```sql
SELECT relname,
       heap_blks_hit,
       heap_blks_read,
       CASE WHEN (heap_blks_hit + heap_blks_read) > 0
            THEN round(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)
            ELSE 0
       END AS hit_pct
FROM pg_statio_user_tables
ORDER BY (heap_blks_hit + heap_blks_read) DESC;
```

Expected output (yours will differ):

```
 relname  | heap_blks_hit | heap_blks_read | hit_pct
----------+---------------+----------------+---------
 orders   |           450 |             12 |   97.40
 products |            85 |              5 |   94.44
(2 rows)
```

### Step 2: Understand the target

- **OLTP systems** (web apps, APIs) - Target 99% or higher. If you are below 99%, you likely need more shared_buffers or your working set does not fit in memory.
- **Reporting/analytics** - Lower hit ratios are normal because these queries scan large amounts of data that may not fit in cache.

### Step 3: Check the overall database hit ratio

This gives you a single number for the whole database.

```sql
SELECT round(100.0 * sum(heap_blks_hit) / sum(heap_blks_hit + heap_blks_read), 2) AS overall_hit_pct
FROM pg_statio_user_tables
WHERE (heap_blks_hit + heap_blks_read) > 0;
```

---

## Section 6: pg_stat_bgwriter - Checkpoint Health

Checkpoints flush dirty pages from memory to disk. PostgreSQL tries to do this on a schedule (`checkpoint_timeout`), but if too much data changes too fast, it forces an unscheduled checkpoint. This view tells you whether checkpoints are happening smoothly.

### Step 1: Query the bgwriter stats

```sql
SELECT checkpoints_timed,
       checkpoints_req,
       buffers_checkpoint,
       buffers_clean,
       buffers_backend
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | buffers_checkpoint | buffers_clean | buffers_backend
-------------------+-----------------+--------------------+---------------+-----------------
                42 |               3 |              12500 |           800 |             150
(1 row)
```

### Step 2: Understand the columns

- **checkpoints_timed** - Checkpoints that happened on schedule. You want this number to be much larger than checkpoints_req.
- **checkpoints_req** - Checkpoints that were forced because too much WAL was generated. A high number here means you should increase `max_wal_size`.
- **buffers_checkpoint** - Pages written to disk during checkpoints. This is normal.
- **buffers_clean** - Pages written by the background writer process. This is also normal.
- **buffers_backend** - Pages written directly by backend processes (your queries). **This is the bad one.** If this number is high, it means your queries had to flush dirty pages to disk themselves because the background writer and checkpoints could not keep up. This causes latency spikes.

### Step 3: Check the ratio

```sql
SELECT round(100.0 * checkpoints_timed / (checkpoints_timed + checkpoints_req), 1) AS timed_pct,
       buffers_backend
FROM pg_stat_bgwriter
WHERE (checkpoints_timed + checkpoints_req) > 0;
```

- **timed_pct** should be above 90%. If it is low, increase `max_wal_size`.
- **buffers_backend** should be as low as possible relative to buffers_checkpoint and buffers_clean.

---

## Cleanup

### Step 1: Exit psql

```sql
\q
```

### Step 2: Exit the postgres user

```bash
exit
```

---

## Summary

You now know the six most important pg_stat views:

| View | What It Tells You |
|------|-------------------|
| pg_stat_activity | Running queries, blocked sessions, idle transactions |
| pg_stat_statements | Historical query performance (total time, calls, rows) |
| pg_stat_user_tables | Table scan ratios, dead rows, autovacuum timing |
| pg_stat_user_indexes | Which indexes are used and which are wasted |
| pg_statio_user_tables | Cache hit ratio per table |
| pg_stat_bgwriter | Checkpoint and buffer write health |

In production, you will query these views daily. Many monitoring tools (pgwatch2, Datadog, pganalyze) pull from these same views automatically. Understanding what each column means helps you interpret those dashboards and act on the alerts they generate.
