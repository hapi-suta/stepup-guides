# PostgreSQL Monitoring

## Why This Module Matters

A database that isn't monitored is a database waiting to surprise you. PostgreSQL
exposes deep internal statistics through system views - connection states, query
performance, vacuum progress, lock contention, and more. Knowing where to look
and what the numbers mean is the difference between proactive management and
firefighting.

---

## The Statistics System

PostgreSQL collects runtime statistics and exposes them through `pg_stat_*` and
`pg_statio_*` views. These views are populated by a background stats collector
process (in PG 15+, stats are stored in shared memory instead of a file).

The two families:
- **pg_stat_*** - activity and operation counts (queries, scans, tuples, vacuums)
- **pg_statio_*** - I/O counts (buffer hits, disk reads)

Stats can be reset:

```sql
-- Reset stats for a specific table
SELECT pg_stat_reset_single_table_counters('orders'::regclass);

-- Reset all stats for the current database
SELECT pg_stat_reset();
```

Resetting stats is useful to measure the impact of a change over a known time window.

---

## pg_stat_activity

This is the first view you check when something is wrong. It shows one row per
backend (connection).

```sql
SELECT pid, state, wait_event_type, wait_event,
       query, query_start,
       now() - query_start AS query_duration,
       usename, client_addr
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;
```

### Query States

| State                  | Meaning                                               |
|------------------------|-------------------------------------------------------|
| active                 | Currently executing a query                           |
| idle                   | Connected but not doing anything                      |
| idle in transaction    | Inside a BEGIN block but not running a query right now |
| idle in transaction (aborted) | Transaction had an error, waiting for ROLLBACK  |
| fastpath function call | Executing a simple function call                      |

**"idle in transaction" is dangerous.** It holds locks and prevents VACUUM from
cleaning dead tuples. Monitor these aggressively. Set a timeout:

```sql
-- Kill backends that sit idle in a transaction for more than 5 minutes
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
SELECT pg_reload_conf();
```

### Wait Events

When a backend is not on the CPU, it's waiting for something. The `wait_event_type`
and `wait_event` columns tell you what.

Common wait event types:
- **LWLock** - lightweight locks (internal PostgreSQL synchronization)
- **Lock** - heavyweight locks (table locks, row locks)
- **BufferPin** - waiting for a buffer pin
- **IO** - waiting for disk I/O
- **Client** - waiting for the client to send data or read results
- **Activity** - background process waiting for work

```sql
-- Find what backends are waiting on
SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity
WHERE state = 'active' AND wait_event IS NOT NULL
GROUP BY 1, 2
ORDER BY 3 DESC;
```

If you see many backends waiting on `Lock` of type `transactionid`, you have
lock contention - some transaction is holding a lock that others need.

---

## pg_stat_user_tables

One row per user table. Critical for understanding table health.

```sql
SELECT relname,
       seq_scan, seq_tup_read,
       idx_scan, idx_tup_fetch,
       n_tup_ins, n_tup_upd, n_tup_del,
       n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

### What to Watch

**seq_scan vs idx_scan** - a table with high seq_scan and low idx_scan is probably
missing an index. But context matters - small tables (under ~1000 rows) are faster
to seq scan.

```sql
-- Tables with more sequential scans than index scans (possible missing indexes)
SELECT relname, seq_scan, idx_scan,
       ROUND(seq_scan::numeric / NULLIF(seq_scan + idx_scan, 0) * 100) AS seq_pct
FROM pg_stat_user_tables
WHERE seq_scan + idx_scan > 100
ORDER BY seq_pct DESC;
```

**n_dead_tup** - high dead tuple count means VACUUM is behind. Check last_autovacuum
to see when it last ran.

**n_tup_hot_upd** - HOT updates (Heap-Only Tuple) are updates that don't need to
modify any index. High HOT update ratios are good - they reduce index bloat.

---

## pg_stat_bgwriter

Shows checkpoint and buffer allocation statistics for the entire cluster.

```sql
SELECT checkpoints_timed, checkpoints_req,
       buffers_checkpoint, buffers_clean, buffers_backend,
       buffers_alloc,
       pg_size_pretty(buffers_checkpoint * 8192::bigint) AS checkpoint_write_volume
FROM pg_stat_bgwriter;
```

### What to Watch

**checkpoints_req vs checkpoints_timed** - `checkpoints_req` are forced checkpoints
(WAL filled up before the scheduled checkpoint). If this number is high relative to
`checkpoints_timed`, increase `max_wal_size`.

**buffers_backend** - these are buffers that backends had to write themselves because
the background writer and checkpointer weren't fast enough. High numbers mean the
background writer needs tuning (`bgwriter_lru_maxpages`, `bgwriter_lru_multiplier`).

```
Ideal:   checkpoints_req << checkpoints_timed
         buffers_backend << buffers_checkpoint + buffers_clean
```

---

## pg_stat_statements

The single most important extension for query performance analysis. It tracks
execution statistics for every query (normalized - constants replaced with $1, $2).

### Setup

```sql
-- 1. Add to shared_preload_libraries (requires restart)
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- Restart PostgreSQL

-- 2. Create the extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### Reading the Output

```sql
SELECT query,
       calls,
       total_exec_time,
       mean_exec_time,
       rows,
       shared_blks_hit,
       shared_blks_read,
       ROUND(shared_blks_hit::numeric /
             NULLIF(shared_blks_hit + shared_blks_read, 0) * 100, 1) AS cache_hit_pct
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

Key columns:

| Column              | What it tells you                                       |
|---------------------|---------------------------------------------------------|
| calls               | How many times this query ran                           |
| total_exec_time     | Total milliseconds spent executing (across all calls)   |
| mean_exec_time      | Average milliseconds per call                           |
| rows                | Total rows returned across all calls                    |
| shared_blks_hit     | Buffer cache hits                                       |
| shared_blks_read    | Disk reads (cache misses)                               |
| temp_blks_read/written | Temp file usage (work_mem too small)                 |

### Identifying Problem Queries

**Highest total time** - these are the queries consuming the most database resources
overall. Even if each call is fast, a query called 10 million times with 1ms average
still consumes 10,000 seconds of DB time.

**Highest mean time** - individually slow queries. Often need index or query plan work.

**High temp_blks_written** - queries spilling to disk. Increase `work_mem` for these
sessions or restructure the query.

**Low cache_hit_pct** - queries reading mostly from disk. May need more shared_buffers
or better indexes to reduce the working set.

Reset stats periodically to get fresh measurements:

```sql
SELECT pg_stat_statements_reset();
```

---

## Logging Configuration

PostgreSQL's log is the other half of monitoring - stats views show current state,
logs show what happened.

### Key Parameters

```
# What to log
log_statement = 'ddl'                  # none, ddl, mod, all
log_min_duration_statement = 1000      # log queries taking > 1 second (-1 = off)

# How to format log lines
log_line_prefix = '%m [%p] %u@%d '     # timestamp, PID, user@database

# Connection logging
log_connections = on
log_disconnections = on

# Checkpoint logging
log_checkpoints = on

# Lock wait logging
log_lock_waits = on                    # log when a query waits > deadlock_timeout for a lock
deadlock_timeout = 1s

# Temp file logging
log_temp_files = 0                     # log all temp file usage (0 = log all, -1 = off)
```

### log_statement Levels

| Level | Logs                                                     |
|-------|----------------------------------------------------------|
| none  | Nothing                                                   |
| ddl   | CREATE, ALTER, DROP statements                            |
| mod   | DDL + INSERT, UPDATE, DELETE, TRUNCATE                    |
| all   | Every SQL statement (high overhead, use only for debugging)|

### Recommended Production Setup

```
log_min_duration_statement = 500       # log queries > 500ms
log_statement = 'ddl'                  # log schema changes
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_line_prefix = '%m [%p] %u@%d %a '
log_autovacuum_min_duration = 0        # log all autovacuum activity
```

---

## Lock Monitoring

### Understanding pg_locks

```sql
SELECT l.pid, l.locktype, l.mode, l.granted, l.relation::regclass,
       a.state, a.query
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.granted = false
ORDER BY a.query_start;
```

`granted = false` means the lock is being waited for. The backend is blocked.

### Finding Lock Chains (Who Is Blocking Whom)

```sql
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.query AS blocking_query,
       blocking.state AS blocking_state
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid AND NOT bl.granted
JOIN pg_locks kl ON kl.locktype = bl.locktype
    AND kl.database IS NOT DISTINCT FROM bl.database
    AND kl.relation IS NOT DISTINCT FROM bl.relation
    AND kl.page IS NOT DISTINCT FROM bl.page
    AND kl.tuple IS NOT DISTINCT FROM bl.tuple
    AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid
    AND kl.granted
JOIN pg_stat_activity blocking ON kl.pid = blocking.pid
WHERE blocked.pid != blocking.pid;
```

This shows blocked queries alongside the queries that are blocking them.

### Lock Modes to Know

| Lock Mode            | Conflicts With                        | Acquired By             |
|----------------------|---------------------------------------|-------------------------|
| AccessShareLock      | AccessExclusiveLock only              | SELECT                  |
| RowShareLock         | Exclusive, AccessExclusive            | SELECT FOR UPDATE       |
| RowExclusiveLock     | Share, ShareRow, Exclusive, AccessExcl| INSERT, UPDATE, DELETE  |
| ShareLock            | RowExcl, ShareRowExcl, Excl, AccessExcl | CREATE INDEX          |
| AccessExclusiveLock  | Everything                            | ALTER TABLE, VACUUM FULL|

Key insight: `ALTER TABLE` takes `AccessExclusiveLock`, which blocks ALL other
operations including SELECT. On busy tables, even adding a column can cause an outage
if other queries are queued behind the lock.

---

## Monitoring Tools Ecosystem

### pgwatch2

Open-source monitoring with built-in dashboards (Grafana). Collects stats from
pg_stat views and stores them in a metrics database. Good for teams that want
a self-hosted solution.

### pg_stat_monitor

Drop-in replacement for pg_stat_statements with additional features:
- Query plans alongside stats
- Histogram of query times
- Client information (application_name, client address)
- Bucket-based time periods for trend analysis

### Prometheus + Exporters

The standard approach for cloud-native monitoring:
- **postgres_exporter** - exposes pg_stat metrics as Prometheus metrics
- **Grafana** - dashboards and alerting
- Custom queries can be added as additional metrics

### pganalyze

SaaS tool that provides EXPLAIN plan analysis, index advisor, and query
normalization. Useful for teams that want analysis, not just data collection.

---

## Building a Monitoring Checklist

### Every 5 Minutes (Automated Alerts)

- [ ] Active connections vs `max_connections` (alert at 80%)
- [ ] Replication lag (bytes and time)
- [ ] Long-running queries (> 5 minutes)
- [ ] Idle in transaction (> 2 minutes)
- [ ] Lock waits (> 30 seconds)
- [ ] Disk space usage (alert at 80%)

### Daily

- [ ] Dead tuple counts across large tables
- [ ] Top 10 queries by total execution time (pg_stat_statements)
- [ ] Cache hit ratio (should be > 99% for OLTP)
- [ ] Temp file usage (queries spilling to disk)
- [ ] Checkpoint frequency (checkpoints_req should be low)
- [ ] Table bloat estimates for top 20 largest tables
- [ ] Autovacuum activity (any tables not getting vacuumed?)

### Weekly

- [ ] Index usage - identify unused indexes
- [ ] Table growth trends - which tables are growing fastest?
- [ ] Sequence exhaustion check (how close to max value?)
- [ ] Connection pool stats (if using PgBouncer)
- [ ] WAL generation rate
- [ ] Review slow query log for new patterns

### Monthly

- [ ] Full bloat analysis (pgstattuple on large tables)
- [ ] Index bloat check (pgstatindex)
- [ ] XID age across all databases (wraparound risk)
- [ ] Extension version check (any updates available?)
- [ ] Review and tune autovacuum thresholds for top tables
- [ ] Capacity planning: project disk/connection needs 3 months out

### Key Queries for Your Toolkit

**Cache hit ratio:**

```sql
SELECT sum(blks_hit)::numeric / sum(blks_hit + blks_read) * 100 AS cache_hit_pct
FROM pg_stat_database
WHERE datname = current_database();
```

**Connection usage:**

```sql
SELECT count(*) AS total,
       count(*) FILTER (WHERE state = 'active') AS active,
       count(*) FILTER (WHERE state = 'idle') AS idle,
       count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn,
       (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn
FROM pg_stat_activity;
```

**Replication lag:**

```sql
SELECT client_addr,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;
```

**XID age (wraparound risk):**

```sql
SELECT datname, age(datfrozenxid) AS xid_age,
       ROUND(age(datfrozenxid)::numeric / 2000000000 * 100, 1) AS pct_to_wraparound
FROM pg_database
ORDER BY xid_age DESC;
```

---

## Key Takeaways

1. pg_stat_activity is your go-to for live troubleshooting - check state, wait events, and query duration
2. pg_stat_statements is non-negotiable for production - install it on every database
3. Sort queries by total_exec_time, not mean_exec_time, to find the biggest resource consumers
4. High buffers_backend in pg_stat_bgwriter means the background writer can't keep up
5. Lock monitoring requires joining pg_locks with pg_stat_activity to find the blocker
6. Configure log_min_duration_statement, log_checkpoints, and log_lock_waits at minimum
7. Build automated alerts for connections, replication lag, long queries, and disk space
8. Check XID age monthly - wraparound is rare but catastrophic when it happens
