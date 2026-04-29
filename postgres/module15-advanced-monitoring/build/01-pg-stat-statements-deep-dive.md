# Build Guide 01 - pg_stat_statements Deep Dive

**Module:** 15 - Advanced Monitoring
**Node:** pg-primary
**Time:** ~30 minutes

---

## Overview

`pg_stat_statements` is a PostgreSQL extension that tracks execution statistics for every SQL statement your database runs. It tells you which queries are slow, how often they run, and how much I/O they consume. In this guide you will enable the extension, generate query traffic with pgbench, and learn to read the statistics it collects.

The extension was already added to `shared_preload_libraries` during server provisioning, so the module is loaded into memory. You just need to create the extension object inside the database before you can query it.

---

## Step 1 - Connect to the server

Log in to your server as `ec2-user`.

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

---

## Step 2 - Switch to the postgres user

The `postgres` OS user owns the PostgreSQL process and has full access to run `psql`.

```bash
sudo -i -u postgres
```

---

## Step 3 - Connect to the stepup_store database

```bash
psql -d stepup_store
```

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

---

## Step 4 - Create the pg_stat_statements extension

This command registers the extension inside the `stepup_store` database. It creates the `pg_stat_statements` view you will query later.

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Expected output (yours will differ):

```
CREATE EXTENSION
```

---

## Step 5 - Verify the extension is active

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

Expected output (yours will differ):

```
        name        | default_version | installed_version
--------------------+-----------------+-------------------
 pg_stat_statements | 1.10            | 1.10
(1 row)
```

The `installed_version` column confirms the extension is installed and ready.

---

## Step 6 - Reset existing statistics

Before you generate test traffic, clear any stats that accumulated during provisioning. This gives you a clean baseline.

```sql
SELECT pg_stat_statements_reset();
```

Expected output (yours will differ):

```
 pg_stat_statements_reset
--------------------------

(1 row)
```

---

## Step 7 - Exit psql and switch back to ec2-user

```sql
\q
```

```bash
exit
```

---

## Step 8 - Run a pgbench workload to generate statistics

`pgbench` is PostgreSQL's built-in benchmarking tool. The `-c 5` flag runs 5 concurrent clients, `-T 60` runs for 60 seconds, and `-d stepup_store` targets your database. This fills `pg_stat_statements` with real query data.

```bash
sudo -u postgres /usr/pgsql-16/bin/pgbench -c 5 -T 60 -d stepup_store
```

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
number of clients: 5
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 8432
...
tps = 140.5 (without initial connection time)
```

---

## Step 9 - Switch back to postgres user and reconnect

```bash
sudo -i -u postgres
```

```bash
psql -d stepup_store
```

---

## Step 10 - Query top queries by total execution time

`total_exec_time` is measured in milliseconds. This query shows you which statements consumed the most cumulative database time. These are your highest-priority tuning targets.

```sql
SELECT
  left(query, 80)          AS query_snippet,
  calls,
  round(total_exec_time::numeric, 2)  AS total_ms,
  round(mean_exec_time::numeric, 4)   AS mean_ms,
  rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
                      query_snippet                       | calls | total_ms | mean_ms |  rows
----------------------------------------------------------+-------+----------+---------+-------
 UPDATE pgbench_accounts SET abalance = abalance + $1 ... |  8432 | 12843.21 |  1.5231 |  8432
 SELECT abalance FROM pgbench_accounts WHERE aid = $1    |  8432 |  2341.88 |  0.2778 |  8432
 INSERT INTO pgbench_history (tid, bid, aid, delta, ...  |  8432 |  1923.44 |  0.2282 |  8432
...
(10 rows)
```

---

## Step 11 - Query top queries by call count

High call count with low mean time is normal. High call count with high mean time means you have a query running too often and too slowly.

```sql
SELECT
  left(query, 80)          AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 4) AS mean_ms,
  round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

---

## Step 12 - Query top queries by mean execution time

`mean_exec_time` reveals the slowest individual executions. One slow query that runs 10,000 times a day is a bigger problem than a fast query that runs millions of times.

```sql
SELECT
  left(query, 80)          AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 4)  AS mean_ms,
  round(stddev_exec_time::numeric, 4) AS stddev_ms,
  round(total_exec_time::numeric, 2)  AS total_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

The `stddev_exec_time` column shows variability. A high standard deviation means the query sometimes runs fast and sometimes runs slow - that often points to cache misses or lock contention.

---

## Step 13 - Examine cache efficiency per query

`shared_blks_hit` counts 8KB blocks served from PostgreSQL's shared buffer cache. `shared_blks_read` counts blocks that had to be fetched from disk. A healthy cache hit ratio is above 99%.

```sql
SELECT
  left(query, 60)           AS query_snippet,
  calls,
  shared_blks_hit,
  shared_blks_read,
  CASE
    WHEN (shared_blks_hit + shared_blks_read) = 0 THEN NULL
    ELSE round(
      100.0 * shared_blks_hit /
      (shared_blks_hit + shared_blks_read), 2
    )
  END AS cache_hit_pct
FROM pg_stat_statements
WHERE shared_blks_hit + shared_blks_read > 0
ORDER BY shared_blks_read DESC
LIMIT 10;
```

Expected output (yours will differ):

```
              query_snippet               | calls | shared_blks_hit | shared_blks_read | cache_hit_pct
------------------------------------------+-------+-----------------+------------------+---------------
 UPDATE pgbench_accounts SET abalance ... |  8432 |           84320 |              421 |         99.51
 SELECT abalance FROM pgbench_account ... |  8432 |           16864 |               88 |         99.48
...
(10 rows)
```

---

## Step 14 - Understand the key columns

| Column | What it means |
|---|---|
| `calls` | Number of times this statement was executed since last reset |
| `total_exec_time` | Cumulative execution time in milliseconds |
| `mean_exec_time` | Average execution time per call in milliseconds |
| `stddev_exec_time` | Standard deviation - measures how variable execution time is |
| `rows` | Total rows returned or affected across all calls |
| `shared_blks_hit` | Blocks served from PostgreSQL shared buffer cache (fast) |
| `shared_blks_read` | Blocks read from OS page cache or disk (slower) |
| `shared_blks_written` | Dirty blocks written to disk |
| `temp_blks_read` | Blocks read from temp files - high values indicate sorts/hashes spilling to disk |
| `temp_blks_written` | Blocks written to temp files |

---

## Step 15 - Find queries with high temp file usage

Queries that spill to temp files are slow because they exhaust `work_mem`. These are good candidates for index additions or `work_mem` increases.

```sql
SELECT
  left(query, 80)          AS query_snippet,
  calls,
  temp_blks_read,
  temp_blks_written,
  round(mean_exec_time::numeric, 2) AS mean_ms
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

---

## Step 16 - Reset statistics again

When you are done investigating a specific time window, reset the stats to start fresh. Do this at the start of each investigation so older noise does not skew your analysis.

```sql
SELECT pg_stat_statements_reset();
```

---

## Step 17 - Exit cleanly

```sql
\q
```

```bash
exit
```

---

## Summary

You have learned to:
- Enable `pg_stat_statements` with `CREATE EXTENSION`
- Generate test query traffic with pgbench
- Find slow queries by `total_exec_time`, `calls`, and `mean_exec_time`
- Measure cache efficiency using `shared_blks_hit` and `shared_blks_read`
- Reset statistics with `pg_stat_statements_reset()`

In the next guide you will install `postgres_exporter` to push these metrics into Prometheus automatically.
