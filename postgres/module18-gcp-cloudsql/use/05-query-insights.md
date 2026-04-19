# USE 05 - Query Insights

## Objective

Enable Query Insights, generate database load with pgbench, identify slow queries, and analyze wait events.

---

## Exercise 1 - Enable Query Insights

Verify Query Insights is enabled (it should be from BUILD 04).

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.insightsConfig)"
```

If not enabled, turn it on.

```bash
gcloud sql instances patch suta-pg-lab \
  --insights-config-query-insights-enabled \
  --insights-config-query-string-length=4096 \
  --insights-config-record-application-tags \
  --insights-config-record-client-address
```

Ensure pg_stat_statements is active.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Reset existing statistics so you start clean.

```sql
SELECT pg_stat_statements_reset();
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 2 - Generate Load with pgbench

Initialize pgbench tables in the suta_lab database. The `-i` flag initializes, `-s 10` creates 1 million rows.

```bash
pgbench -h 127.0.0.1 -U postgres -d suta_lab -i -s 10
```

Expected output (yours will differ):

```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done
vacuuming...
creating primary keys...
done in 18.45 s
```

Run a 120-second load test with 10 concurrent connections.

```bash
pgbench -h 127.0.0.1 -U postgres -d suta_lab -c 10 -j 2 -T 120
```

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
number of clients: 10
duration: 120 s
number of transactions actually processed: 24567
latency average = 48.85 ms
tps = 204.72 (without initial connection time)
```

---

## Exercise 3 - Identify Slow Queries

Connect and query pg_stat_statements for the slowest queries.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Top 10 queries by total execution time.

```sql
SELECT
    left(query, 80) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round((stddev_exec_time)::numeric, 2) AS stddev_ms,
    rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
                              query_preview                               | calls | total_ms  | avg_ms | stddev_ms | rows
--------------------------------------------------------------------------+-------+-----------+--------+-----------+-------
 UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2      | 24567 | 156789.12 |   6.38 |      3.21 | 24567
 UPDATE pgbench_tellers SET tbalance = tbalance + $1 WHERE tid = $2       | 24567 |  34567.89 |   1.41 |      0.87 | 24567
 UPDATE pgbench_branches SET bbalance = bbalance + $1 WHERE bid = $2      | 24567 |  23456.78 |   0.95 |      0.56 | 24567
 INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ...     | 24567 |  12345.67 |   0.50 |      0.23 | 24567
...
```

The `pgbench_accounts` UPDATE is always the slowest because it hits 1 million rows randomly.

---

## Exercise 4 - Analyze Query Patterns

Find queries with the highest average time (potential optimization targets).

```sql
SELECT
    left(query, 80) AS query_preview,
    calls,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(min_exec_time::numeric, 2) AS min_ms,
    round(max_exec_time::numeric, 2) AS max_ms
FROM pg_stat_statements
WHERE calls > 10
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Find queries with the most rows returned (potential I/O hogs).

```sql
SELECT
    left(query, 80) AS query_preview,
    calls,
    rows,
    round((rows::numeric / calls), 2) AS rows_per_call
FROM pg_stat_statements
WHERE calls > 0
ORDER BY rows DESC
LIMIT 10;
```

---

## Exercise 5 - View Wait Events

Check current wait events. These show what PostgreSQL is waiting on.

```sql
SELECT
    pid,
    wait_event_type,
    wait_event,
    state,
    left(query, 60) AS query_preview
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY wait_event_type;
```

If pgbench is still running, you will see active backends. If not, most will show idle.

Check the most common wait events from recent activity.

```sql
SELECT
    wait_event_type,
    wait_event,
    count(*) AS occurrences
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
GROUP BY wait_event_type, wait_event
ORDER BY occurrences DESC;
```

Expected output (yours will differ):

```
 wait_event_type |   wait_event    | occurrences
-----------------+-----------------+-------------
 Client          | ClientRead      |           5
 LWLock          | WALWriteLock    |           2
 IO              | DataFileRead    |           1
...
```

---

## Exercise 6 - Check Table and Index Statistics

After the load test, check table statistics.

```sql
SELECT
    relname,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_live_tup
FROM pg_stat_user_tables
ORDER BY n_tup_upd DESC;
```

Expected output (yours will differ):

```
      relname       | seq_scan | seq_tup_read | idx_scan | idx_tup_fetch | n_tup_ins | n_tup_upd | n_live_tup
--------------------+----------+--------------+----------+---------------+-----------+-----------+------------
 pgbench_accounts   |        1 |      1000000 |    24567 |         24567 |   1000000 |     24567 |    1000000
 pgbench_tellers    |        1 |          100 |    24567 |         24567 |       100 |     24567 |        100
 pgbench_branches   |        1 |           10 |    24567 |         24567 |        10 |     24567 |         10
 pgbench_history    |        0 |            0 |        0 |             0 |     24567 |         0 |      24567
...
```

The `pgbench_accounts` table has the most index scans and updates, matching the slow query pattern.

Type `\q` to exit psql.

```
\q
```

---

## Checklist

- [ ] Query Insights enabled and verified
- [ ] pg_stat_statements reset and active
- [ ] pgbench initialized with scale factor 10
- [ ] Load test completed (120 seconds, 10 clients)
- [ ] Identified top 10 slowest queries
- [ ] Analyzed query patterns (avg time, rows per call)
- [ ] Checked wait events
- [ ] Reviewed table and index statistics
