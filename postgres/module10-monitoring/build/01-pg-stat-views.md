# Guide 01 - pg_stat Views

Learn the five core system views every DBA queries daily to understand what PostgreSQL is doing right now and over time.

**Run all commands on:** NODE1

---

## Overview

PostgreSQL exposes its internal state through a family of views that start with `pg_stat_`. These views are built into PostgreSQL - no installation needed. They are the foundation of all database monitoring.

By the end of this guide you will know:
- What each view shows and when to use it
- Which Pulse dashboard panels each view feeds
- The most useful queries for each view

---

## Section 1 - Connect to the Database

SSH into NODE1 first.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

Switch to the postgres user.

```
sudo -iu postgres
```

Open a psql session against the stepup_store database.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

(`-p 5432` = connect on port 5432. `-d stepup_store` = connect to the stepup_store database.)

---

## Section 2 - pg_stat_activity

`pg_stat_activity` shows one row for every server process, including what query it is running, what state it is in, and how long it has been there. This is the first view you open when something feels wrong.

**Pulse panels:** DB Status, Health Checks, App Metrics

### 2.1 - See all active connections

```sql
SELECT pid, usename, datname, state, wait_event_type, wait_event, query
FROM pg_stat_activity
ORDER BY state, pid;
```

Expected output (yours will differ):

```
  pid  | usename  |   datname    | state  | wait_event_type | wait_event |       query
-------+----------+--------------+--------+-----------------+------------+--------------------
   412 | postgres | stepup_store | active |                 |            | SELECT pid, ...
  1042 | app_user | stepup_store | idle   | Client          | ClientRead |
(2 rows)
```

(`pid` = process ID. `state` = active, idle, idle in transaction, etc. `wait_event` = what the process is currently waiting on.)

> **Concept - Connection States**: A process in `idle` state is connected but not executing a query - it is waiting for the client to send something. A process in `idle in transaction` is more dangerous: it has an open transaction but is doing nothing, which holds locks. A process in `active` state is executing a query right now.

### 2.2 - Find long-running queries

```sql
SELECT pid, usename, datname, state,
       now() - query_start AS duration,
       query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query_start IS NOT NULL
ORDER BY duration DESC;
```

Expected output (yours will differ):

```
  pid  | usename  |   datname    | state  | duration  |         query
-------+----------+--------------+--------+-----------+------------------------
   412 | postgres | stepup_store | active | 00:00:00  | SELECT pid, usename ...
(1 row)
```

(`now() - query_start` = how long the query has been running.)

### 2.3 - Count connections by state

```sql
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state
ORDER BY count DESC;
```

Expected output (yours will differ):

```
 state  | count
--------+-------
 idle   |     4
 active |     1
(2 rows)
```

---

## Section 3 - pg_stat_database

`pg_stat_database` shows cumulative statistics for each database since the last stats reset. It tells you overall traffic, cache effectiveness, and transaction rates.

**Pulse panels:** DB Status, Performance

### 3.1 - View database-level statistics

```sql
SELECT datname,
       numbackends,
       xact_commit,
       xact_rollback,
       blks_read,
       blks_hit,
       round(blks_hit * 100.0 / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       tup_inserted,
       tup_updated,
       tup_deleted
FROM pg_stat_database
WHERE datname = 'stepup_store';
```

Expected output (yours will differ):

```
   datname    | numbackends | xact_commit | xact_rollback | blks_read | blks_hit | cache_hit_pct | tup_inserted | tup_updated | tup_deleted
--------------+-------------+-------------+---------------+-----------+----------+---------------+--------------+-------------+-------------
 stepup_store |           1 |        8234 |            12 |       402 |   284950 |         99.86 |        50000 |        1200 |         300
(1 row)
```

(`numbackends` = current connections. `cache_hit_pct` = percentage of blocks read from shared_buffers instead of disk. Healthy systems are above 98%.)

> **Concept - Cache Hit Ratio**: When PostgreSQL reads data, it first checks shared_buffers (RAM). A cache hit means the block was already in RAM. A cache miss means PostgreSQL had to read from disk, which is 100x slower. A cache hit ratio below 95% is a signal to investigate - either shared_buffers is too small, or queries are doing full table scans.

### 3.2 - Check rollback ratio

```sql
SELECT datname,
       xact_commit,
       xact_rollback,
       round(xact_rollback * 100.0 / nullif(xact_commit + xact_rollback, 0), 2) AS rollback_pct
FROM pg_stat_database
WHERE datname = 'stepup_store';
```

Expected output (yours will differ):

```
   datname    | xact_commit | xact_rollback | rollback_pct
--------------+-------------+---------------+--------------
 stepup_store |        8234 |            12 |         0.15
(1 row)
```

A rollback rate above 5% is worth investigating - it may indicate application errors or lock conflicts.

---

## Section 4 - pg_stat_user_tables

`pg_stat_user_tables` shows per-table statistics: sequential scans, index scans, row operations, and autovacuum timing. This is where you spot missing indexes and bloat problems.

**Pulse panels:** MVCC/Vacuum, Performance

### 4.1 - Find tables with the most sequential scans

```sql
SELECT schemaname,
       relname,
       seq_scan,
       seq_tup_read,
       idx_scan,
       n_live_tup,
       n_dead_tup,
       last_autovacuum,
       last_autoanalyze
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 schemaname |    relname    | seq_scan | seq_tup_read | idx_scan | n_live_tup | n_dead_tup | last_autovacuum | last_autoanalyze
------------+---------------+----------+--------------+----------+------------+------------+-----------------+------------------
 public     | orders        |     2450 |    245000000 |    98234 |     100000 |       2400 | 2026-04-19 ...  | 2026-04-19 ...
 public     | order_items   |      340 |      3400000 |   220000 |     300000 |       8100 | 2026-04-19 ...  | 2026-04-19 ...
...
```

(`seq_scan` = full table scans. High seq_scan on a large table often means a missing index. `n_dead_tup` = dead rows waiting for vacuum.)

> **Concept - Sequential vs Index Scans**: A sequential scan reads every row in the table. An index scan jumps directly to matching rows. For large tables, sequential scans are expensive. If a table has many sequential scans, check whether an appropriate index exists. However, for very small tables (under ~1000 rows), sequential scans are often faster than index scans - the query planner makes this call automatically.

### 4.2 - Check dead tuple bloat

```sql
SELECT schemaname,
       relname,
       n_live_tup,
       n_dead_tup,
       round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 schemaname |  relname  | n_live_tup | n_dead_tup | dead_pct | last_autovacuum
------------+-----------+------------+------------+----------+-----------------
 public     | orders    |     100000 |       2400 |      2.3 | 2026-04-19 ...
(1 row)
```

Dead tuple percentage above 10-20% on an active table means autovacuum may be falling behind.

---

## Section 5 - pg_stat_user_indexes

`pg_stat_user_indexes` shows how often each index is used. This helps you find indexes that are never used (wasted write overhead and disk space) and confirm that expected indexes are being hit.

**Pulse panels:** Performance

### 5.1 - Find unused indexes

```sql
SELECT schemaname,
       relname,
       indexrelname,
       idx_scan,
       idx_tup_read,
       idx_tup_fetch
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY schemaname, relname;
```

Expected output (yours will differ):

```
 schemaname | relname | indexrelname | idx_scan | idx_tup_read | idx_tup_fetch
------------+---------+--------------+----------+--------------+---------------
 public     | orders  | idx_orders_x |        0 |            0 |             0
(1 row)
```

(`idx_scan = 0` means the index has never been used since the last stats reset. These are candidates for removal after confirming they are not needed for unique constraints or foreign keys.)

### 5.2 - Find most-used indexes

```sql
SELECT schemaname,
       relname,
       indexrelname,
       idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 schemaname |   relname   |        indexrelname        | idx_scan
------------+-------------+----------------------------+----------
 public     | orders      | orders_pkey                |   140320
 public     | order_items | order_items_order_id_idx   |    98210
...
```

---

## Section 6 - pg_stat_bgwriter

`pg_stat_bgwriter` shows statistics about the background writer process and checkpoint activity. It tells you whether checkpoints are happening on schedule or being forced early (a sign of write pressure).

**Pulse panels:** Performance, Config

### 6.1 - Check checkpoint health

```sql
SELECT checkpoints_timed,
       checkpoints_req,
       round(checkpoints_req * 100.0 / nullif(checkpoints_timed + checkpoints_req, 0), 1) AS forced_pct,
       buffers_checkpoint,
       buffers_clean,
       buffers_backend,
       maxwritten_clean,
       stats_reset
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | forced_pct | buffers_checkpoint | buffers_clean | buffers_backend | maxwritten_clean |         stats_reset
-------------------+-----------------+------------+--------------------+---------------+-----------------+------------------+------------------------------
               142 |               3 |        2.1 |             284200 |          8400 |            1200 |                0 | 2026-04-10 00:00:01.123456+00
(1 row)
```

(`checkpoints_req` = checkpoints forced by WAL pressure, not by the timer. High `forced_pct` means `max_wal_size` or `checkpoint_completion_target` needs tuning. `buffers_backend` = pages written directly by backend processes because the bgwriter was too slow - this is expensive.)

> **Concept - Checkpoint Pressure**: PostgreSQL periodically flushes dirty pages from shared_buffers to disk in a "checkpoint." There are two kinds: timed checkpoints (triggered by `checkpoint_timeout`, default 5 minutes) and required checkpoints (triggered because WAL grew too large). A high ratio of required checkpoints means PostgreSQL cannot flush data fast enough. This creates I/O spikes. Tuning `max_wal_size` larger gives PostgreSQL more room to spread the work out.

---

## Section 7 - Exit psql

```sql
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should have:

- [ ] Queried `pg_stat_activity` to see active connections and their states
- [ ] Calculated cache hit ratio from `pg_stat_database`
- [ ] Identified sequential scan patterns in `pg_stat_user_tables`
- [ ] Found unused indexes with `pg_stat_user_indexes`
- [ ] Checked checkpoint health in `pg_stat_bgwriter`

---

Proceed to: [Guide 02 - pg_stat_statements](./02-pg-stat-statements.md)
