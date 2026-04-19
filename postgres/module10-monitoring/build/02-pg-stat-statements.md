# Guide 02 - pg_stat_statements

Install and configure the pg_stat_statements extension so PostgreSQL tracks every query's execution time, call count, and resource use. Then use it to find your worst-performing queries.

**Run all commands on:** NODE1

---

## Overview

`pg_stat_statements` is a PostgreSQL extension that records statistics for every normalized query that runs. "Normalized" means query literals are replaced with `$1`, `$2`, etc., so `SELECT * FROM orders WHERE order_id = 1` and `SELECT * FROM orders WHERE order_id = 2` are tracked as a single entry.

By the end of this guide you will know:
- How to install and configure pg_stat_statements
- How to find the top queries by execution time, mean time, and call count
- How to reset statistics to start fresh
- How to watch the Pulse Query Stats panel reflect what you configure

---

## Section 1 - Understand the Prerequisite

`pg_stat_statements` must be loaded at server startup. This requires adding it to `shared_preload_libraries` and restarting PostgreSQL. A reload is not enough - the extension hooks into memory at startup time.

> **Concept - shared_preload_libraries**: This parameter tells PostgreSQL which shared libraries to load into memory when the server starts. Extensions that need to intercept every query (like pg_stat_statements) must be listed here. Unlike most parameters, changes to `shared_preload_libraries` require a full server restart, not just a reload.

---

## Section 2 - Check the Current Configuration

SSH into NODE1.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

Switch to the postgres user.

```
sudo -iu postgres
```

Check whether pg_stat_statements is already in shared_preload_libraries.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW shared_preload_libraries;"
```

Expected output (yours will differ):

```
 shared_preload_libraries
--------------------------

(1 row)
```

If the output is empty or does not include `pg_stat_statements`, continue to Section 3. If it already shows `pg_stat_statements`, skip to Section 5.

---

## Section 3 - Add pg_stat_statements to postgresql.conf

Open the main configuration file with vi.

```
vi /opt/pgsql/data/postgresql.conf
```

Search for the `shared_preload_libraries` line by typing `/shared_preload_libraries` and pressing Enter.

Find the line that looks like:

```
#shared_preload_libraries = ''
```

Uncomment it and set it to include pg_stat_statements. Position your cursor on the line, press `i` to enter insert mode, and change it to:

```
shared_preload_libraries = 'pg_stat_statements'
```

While you are in the file, also set the tuning parameters for pg_stat_statements. Scroll to the end of the file (press `G`) and add these lines:

```
pg_stat_statements.max = 10000
pg_stat_statements.track = all
```

Save and exit with `:wq`.

(`pg_stat_statements.max` = how many distinct normalized queries to track. When the limit is hit, the least-used entries are evicted. `pg_stat_statements.track = all` = track queries inside functions and stored procedures, not just top-level queries. The default `top` only tracks direct client queries.)

---

## Section 4 - Restart PostgreSQL

Exit the postgres user first.

```
exit
```

Restart the PostgreSQL service to load the new shared library.

```
sudo systemctl restart postgresql-16
```

Wait a few seconds, then confirm PostgreSQL is running.

```
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since Sun 2026-04-19 10:00:05 UTC; 3s ago
```

---

## Section 5 - Create the Extension

Switch to postgres user.

```
sudo -iu postgres
```

Connect to the stepup_store database and create the extension.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

Expected output:

```
CREATE EXTENSION
```

Verify the extension is installed.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
```

Expected output (yours will differ):

```
       extname       | extversion
---------------------+------------
 pg_stat_statements  | 1.10
(1 row)
```

---

## Section 6 - Query pg_stat_statements

Now open a psql session and start exploring.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### 6.1 - Top queries by total execution time

This is the most important query - it shows which queries are consuming the most total CPU and I/O time across all calls.

```sql
SELECT query,
       calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(stddev_exec_time::numeric, 2) AS stddev_ms,
       rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
              query               | calls | total_ms | mean_ms | stddev_ms |  rows
----------------------------------+-------+----------+---------+-----------+-------
 SELECT * FROM orders WHERE ...   |  9820 |  4821.34 |    0.49 |      0.12 | 98200
 UPDATE orders SET status = $1... |   320 |  1204.56 |    3.76 |      1.23 |   320
...
```

(`total_exec_time` = sum of all execution time for this query pattern in milliseconds. `mean_exec_time` = average time per call. `calls` = how many times this query has been executed.)

### 6.2 - Top queries by mean execution time (slowest on average)

```sql
SELECT query,
       calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
WHERE calls > 5
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
                    query                     | calls | mean_ms |  total_ms
----------------------------------------------+-------+---------+-----------
 SELECT * FROM orders o JOIN order_items ...  |    12 |  124.35 |   1492.20
 SELECT count(*) FROM orders WHERE date ...   |     8 |   98.40 |    787.20
...
```

(`WHERE calls > 5` filters out one-off queries that might show a high average just because they ran once slowly.)

> **Concept - Total vs Mean Time**: Total time identifies queries that consume the most resources overall (important for capacity). Mean time identifies queries that are slow per call (important for user experience). A query called 100,000 times with 1ms mean has 100 seconds total - fix that before a query called 5 times with 200ms mean (1 second total).

### 6.3 - Top queries by call count

```sql
SELECT query,
       calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

Expected output (yours will differ):

```
              query               |  calls  | mean_ms | total_ms
----------------------------------+---------+---------+----------
 SELECT $1                        | 1824000 |    0.01 |   182.40
 SELECT * FROM orders WHERE or... |   98200 |    0.49 |  4821.34
...
```

High-call-count queries with low mean time are fine. High-call-count queries with even moderate mean time can dominate total load.

### 6.4 - Check I/O statistics

```sql
SELECT query,
       calls,
       shared_blks_hit,
       shared_blks_read,
       round(shared_blks_hit * 100.0 / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS cache_hit_pct,
       temp_blks_written
FROM pg_stat_statements
ORDER BY shared_blks_read DESC
LIMIT 10;
```

Expected output (yours will differ):

```
            query             | calls | shared_blks_hit | shared_blks_read | cache_hit_pct | temp_blks_written
------------------------------+-------+-----------------+------------------+---------------+-------------------
 SELECT * FROM orders JOIN... |    12 |            2400 |             8400 |          22.2 |                 0
...
```

(`shared_blks_read` = blocks read from disk. Low cache_hit_pct per-query means that query is doing a lot of disk I/O - often a sign of a missing index or a query scanning a large table.)

---

## Section 7 - Reset Statistics

You can reset all pg_stat_statements data to start fresh. This is useful after making a change and wanting clean data.

```sql
SELECT pg_stat_statements_reset();
```

Expected output:

```
 pg_stat_statements_reset
--------------------------

(1 row)
```

> **Concept - Stats Reset Timing**: After calling `pg_stat_statements_reset()`, all counters go to zero. The view will be empty until queries run again. This is useful when you make a schema or index change and want to measure the before/after cleanly. In production, never reset stats during a high-traffic period - wait for a maintenance window so you get clean baseline data.

---

## Section 8 - Watch the Pulse Query Stats Panel

With pg_stat_statements installed, the Pulse dashboard Query Stats panel should now show populated data. To confirm:

Open a browser and navigate to:

```
http://<NODE1-IP>:8080
```

Click the "Query Stats" panel. You should see the top queries populating. Generate some activity first by running a few queries:

```sql
SELECT count(*) FROM orders;
```

```sql
SELECT * FROM orders LIMIT 100;
```

```sql
SELECT o.order_id, o.status, sum(oi.unit_price) FROM orders o JOIN order_items oi ON o.order_id = oi.order_id GROUP BY o.order_id, o.status LIMIT 20;
```

Then refresh the Pulse panel. You should see these query patterns appear in the Query Stats view.

---

## Section 9 - Exit

```sql
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should have:

- [ ] Added `pg_stat_statements` to `shared_preload_libraries` in postgresql.conf
- [ ] Set `pg_stat_statements.max` and `pg_stat_statements.track`
- [ ] Restarted PostgreSQL to load the library
- [ ] Created the extension with `CREATE EXTENSION`
- [ ] Queried top queries by total time, mean time, and call count
- [ ] Used `pg_stat_statements_reset()` to clear stats
- [ ] Confirmed the Pulse Query Stats panel shows data

---

Proceed to: [Guide 03 - Logging Configuration](./03-logging-configuration.md)
