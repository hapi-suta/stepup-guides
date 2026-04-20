# Guide 05 - Custom Monitoring Queries

Build a reusable monitoring script that captures the vital signs of a PostgreSQL server, exports them to CSV for trending, and compares what you see manually against what the Pulse dashboard shows.

**Run all commands on:** NODE1

---

## Overview

The built-in Pulse dashboard shows many metrics automatically. But every environment has unique queries and thresholds. Knowing how to write your own monitoring queries gives you:
- The ability to catch what generic dashboards miss
- CSV exports you can trend in a spreadsheet
- The foundation for custom alerting

By the end of this guide you will have a working monitoring script and understand every metric it captures.

---

## Section 1 - Connect

SSH into NODE1.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

Switch to the postgres user.

```
sudo -iu postgres
```

---

## Section 2 - The Six Vital Signs

A healthy PostgreSQL server can be checked with six key metrics. We will build one query for each, then combine them into a script.

Open a psql session to understand each query before scripting.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### 2.1 - Connection count and limit

```sql
SELECT count(*) AS current_connections,
       max_conn,
       round(count(*) * 100.0 / max_conn, 1) AS used_pct
FROM pg_stat_activity,
     (SELECT setting::int AS max_conn FROM pg_settings WHERE name = 'max_connections') AS mc
GROUP BY max_conn;
```

Expected output (yours will differ):

```
 current_connections | max_conn | used_pct
---------------------+----------+----------
                   5 |      100 |      5.0
(1 row)
```

Alert threshold: above 80% is a warning. Above 90% is critical.

### 2.2 - Cache hit ratio

```sql
SELECT datname,
       round(blks_hit * 100.0 / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct
FROM pg_stat_database
WHERE datname = 'stepup_store';
```

Expected output (yours will differ):

```
   datname    | cache_hit_pct
--------------+---------------
 stepup_store |         99.86
(1 row)
```

Alert threshold: below 95% is worth investigating.

### 2.3 - Replication lag

```sql
SELECT client_addr,
       state,
       sent_lsn,
       write_lsn,
       flush_lsn,
       replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

Expected output (yours will differ):

```
 client_addr | state | sent_lsn | write_lsn | flush_lsn | replay_lsn | lag_bytes
-------------+-------+----------+-----------+-----------+------------+-----------
(0 rows)
```

On a single-node lab with no replicas, this returns zero rows. That is expected. In a replication setup, `lag_bytes` above 100MB is worth alerting on.

### 2.4 - Bloat detection (dead tuples)

```sql
SELECT schemaname,
       relname,
       n_live_tup,
       n_dead_tup,
       round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_pct DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 schemaname |  relname  | n_live_tup | n_dead_tup | dead_pct | last_autovacuum
------------+-----------+------------+------------+----------+-----------------
 public     | orders    |     100000 |       2100 |      2.1 | 2026-04-19 ...
(1 row)
```

Alert threshold: `dead_pct` above 20% on an active table means autovacuum may be falling behind.

### 2.5 - Long-running queries

```sql
SELECT pid, usename, datname, state,
       extract(epoch FROM (now() - query_start))::int AS seconds,
       left(query, 80) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
  AND query_start IS NOT NULL
  AND now() - query_start > interval '30 seconds'
ORDER BY seconds DESC;
```

Expected output (yours will differ):

```
  pid  | usename  |   datname    | state           | seconds |        query_snippet
-------+----------+--------------+-----------------+---------+------------------------------
  2841 | postgres | stepup_store | idle in trans   |     245 | UPDATE orders SET status ...
(1 row)
```

Alert threshold: any query running longer than 5 minutes is a concern. `idle in transaction` queries are especially dangerous because they hold locks.

### 2.6 - Checkpoint pressure

```sql
SELECT checkpoints_timed,
       checkpoints_req,
       round(checkpoints_req * 100.0 / nullif(checkpoints_timed + checkpoints_req, 0), 1) AS forced_pct,
       buffers_backend,
       buffers_checkpoint
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | forced_pct | buffers_backend | buffers_checkpoint
-------------------+-----------------+------------+-----------------+--------------------
               142 |               2 |        1.4 |              48 |             284200
(1 row)
```

Alert threshold: `forced_pct` above 10% or `buffers_backend` above 1% of `buffers_checkpoint` indicates write pressure.

---

## Section 3 - Exit psql

```sql
\q
```

---

## Section 4 - Write the Monitoring Script

Create the script file.

```
vi /opt/pgsql/monitor.sh
```

Paste in the following content (press `i` to enter insert mode, paste, then `:wq` to save).

Key flags used in the script:
- `set -euo pipefail` = `-e` exit on any error, `-u` treat unset variables as errors, `-o pipefail` fail if any command in a pipe fails
- `-t` = tuples only (no column headers or row counts), `-A` = unaligned output (no padding spaces) - both make psql output easy to parse in scripts

```bash
#!/usr/bin/env bash
# monitor.sh - PostgreSQL vital signs snapshot for stepup_store
# Usage: ./monitor.sh [--csv]
# Outputs a human-readable report or CSV for trending.

set -euo pipefail

PSQL="/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -t -A"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
CSV_MODE="${1:-}"

run_sql() {
  $PSQL -c "$1"
}

# ---------- connection count ----------
CONN_DATA=$(run_sql "
  SELECT count(*), max_conn,
         round(count(*) * 100.0 / max_conn, 1)
  FROM pg_stat_activity,
       (SELECT setting::int AS max_conn FROM pg_settings WHERE name = 'max_connections') mc
  GROUP BY max_conn;
")
CONN_CURRENT=$(echo "$CONN_DATA" | cut -d'|' -f1)
CONN_MAX=$(echo "$CONN_DATA" | cut -d'|' -f2)
CONN_PCT=$(echo "$CONN_DATA" | cut -d'|' -f3)

# ---------- cache hit ratio ----------
CACHE_HIT=$(run_sql "
  SELECT round(blks_hit * 100.0 / nullif(blks_hit + blks_read, 0), 2)
  FROM pg_stat_database WHERE datname = 'stepup_store';
")

# ---------- long-running queries ----------
LONG_QUERIES=$(run_sql "
  SELECT count(*) FROM pg_stat_activity
  WHERE state != 'idle'
    AND query_start IS NOT NULL
    AND now() - query_start > interval '5 minutes';
")

# ---------- idle in transaction ----------
IDLE_IN_TXN=$(run_sql "
  SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction';
")

# ---------- dead tuple bloat ----------
BLOAT_TABLES=$(run_sql "
  SELECT count(*) FROM pg_stat_user_tables
  WHERE n_dead_tup > 1000
    AND n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0) > 20;
")

# ---------- forced checkpoints ----------
FORCED_PCT=$(run_sql "
  SELECT round(checkpoints_req * 100.0 / nullif(checkpoints_timed + checkpoints_req, 0), 1)
  FROM pg_stat_bgwriter;
")

# ---------- output ----------
if [[ "$CSV_MODE" == "--csv" ]]; then
  echo "timestamp,connections,max_conn,conn_pct,cache_hit_pct,long_queries,idle_in_txn,bloat_tables,forced_ckpt_pct"
  echo "${TIMESTAMP},${CONN_CURRENT},${CONN_MAX},${CONN_PCT},${CACHE_HIT},${LONG_QUERIES},${IDLE_IN_TXN},${BLOAT_TABLES},${FORCED_PCT}"
else
  echo "=== PostgreSQL Health Check: ${TIMESTAMP} ==="
  echo ""
  printf "  Connections:     %s / %s (%s%%)\n" "$CONN_CURRENT" "$CONN_MAX" "$CONN_PCT"
  printf "  Cache Hit Ratio: %s%%\n" "$CACHE_HIT"
  printf "  Long Queries:    %s (over 5 min)\n" "$LONG_QUERIES"
  printf "  Idle in Txn:     %s\n" "$IDLE_IN_TXN"
  printf "  Bloated Tables:  %s (>20%% dead tuples)\n" "$BLOAT_TABLES"
  printf "  Forced Ckpts:    %s%%\n" "$FORCED_PCT"
  echo ""
fi
```

Save and exit vi with `:wq`.

Make the script executable.

```
chmod +x /opt/pgsql/monitor.sh
```

---

## Section 5 - Run the Script

Run the human-readable report.

```
/opt/pgsql/monitor.sh
```

Expected output (yours will differ):

```
=== PostgreSQL Health Check: 2026-04-19T10:30:00 ===

  Connections:     5 / 100 (5.0%)
  Cache Hit Ratio: 99.86%
  Long Queries:    0 (over 5 min)
  Idle in Txn:     0
  Bloated Tables:  0 (>20% dead tuples)
  Forced Ckpts:    1.4%
```

Run with CSV output for trending.

```
/opt/pgsql/monitor.sh --csv
```

Expected output (yours will differ):

```
timestamp,connections,max_conn,conn_pct,cache_hit_pct,long_queries,idle_in_txn,bloat_tables,forced_ckpt_pct
2026-04-19T10:30:00,5,100,5.0,99.86,0,0,0,1.4
```

---

## Section 6 - Export to CSV for Trending

Append a snapshot to a CSV file every time you run the script.

```
/opt/pgsql/monitor.sh --csv >> /opt/pgsql/log/pg_health_trend.csv
```

Run it a second time to see multiple rows building up.

```
/opt/pgsql/monitor.sh --csv >> /opt/pgsql/log/pg_health_trend.csv
```

View the CSV file.

```
cat /opt/pgsql/log/pg_health_trend.csv
```

Expected output (yours will differ):

```
timestamp,connections,max_conn,conn_pct,cache_hit_pct,long_queries,idle_in_txn,bloat_tables,forced_ckpt_pct
2026-04-19T10:30:00,5,100,5.0,99.86,0,0,0,1.4
2026-04-19T10:30:05,5,100,5.0,99.86,0,0,0,1.4
```

> **Concept - Trending vs Alerting**: A single metric snapshot tells you the current state. A trend tells you whether things are getting better or worse. Collecting CSV snapshots on a cron every 5 minutes gives you a lightweight trending dataset you can open in a spreadsheet to spot creeping problems - a connection count that grows 2% per hour, a cache hit ratio that slowly degrades after a new feature ships.

---

## Section 7 - Compare with Pulse Dashboard

Open a browser and navigate to:

```
http://<NODE1-IP>:8080
```

Compare what you see in the Pulse panels against what your script reported:

| Pulse Panel | Your Script Metric |
|---|---|
| DB Status | Connection count, conn_pct |
| Health Checks | Long queries, idle in transaction |
| MVCC/Vacuum | Bloated tables (dead_pct) |
| Performance | Cache hit ratio, forced checkpoint pct |
| Replication | Would appear in replication output |

Both Pulse and your script read from the same underlying pg_stat views. If they disagree, check for differences in the database being queried or whether stats were recently reset.

---

## Section 8 - Exit

```
exit
```

---

## Checkpoint

By the end of this guide you should have:

- [ ] Written individual queries for connection count, cache hit ratio, replication lag, dead tuple bloat, long-running queries, and checkpoint pressure
- [ ] Built a monitoring script that accepts `--csv` flag
- [ ] Appended CSV snapshots to a trending file
- [ ] Compared script output against Pulse dashboard panels

---

This is the last BUILD guide for Module 10. Proceed to the USE exercises.

Proceed to: [Use Exercise 01 - Build a Health Check Script](../use/01-build-health-check.md)
