# Tier 6 Concepts - Performance and Monitoring

This document covers all 12 topics at the conceptual level. Read this before working through the build guides. Come back to it when you need a reference.

---

## T6.1 - CloudWatch Metrics and Enhanced Monitoring

### Standard CloudWatch Metrics

RDS publishes metrics to CloudWatch every 60 seconds (configurable). These come from the hypervisor level - they measure what the hypervisor sees, not what the OS or PostgreSQL sees.

Key metrics and what they actually measure:

| Metric | Unit | What It Measures | Alert Threshold |
|--------|------|-----------------|-----------------|
| CPUUtilization | % | Hypervisor-level CPU | >80% sustained |
| DatabaseConnections | Count | Open connections to the instance | >80% of max_connections |
| FreeableMemory | Bytes | RAM available (not just free, includes cache) | <10% of total RAM |
| FreeStorageSpace | Bytes | Unallocated disk space | <20% of total |
| ReadIOPS / WriteIOPS | Count/s | Storage I/O operations | Varies by instance |
| ReadLatency / WriteLatency | Seconds | Average I/O latency | >20ms read, >10ms write |
| NetworkReceiveThroughput | Bytes/s | Inbound network | Near EBS bandwidth limit |
| ReplicaLag | Seconds | Read replica replication lag | >5 seconds = investigate |
| TransactionLogsDiskUsage | Bytes | WAL retained on disk | Growing = replication issue |
| MaximumUsedTransactionIDs | Count | Highest transaction ID in use | >1.5B = urgent |

### Enhanced Monitoring

Enhanced Monitoring runs a lightweight agent inside the DB instance OS. It reports at 1-second granularity, which standard CloudWatch cannot match. The data goes to CloudWatch Logs, not CloudWatch Metrics, which is why it looks different in the console.

```
Standard CloudWatch           Enhanced Monitoring
---------------------------------  ---------------------------------
Source: hypervisor             Source: OS agent inside instance
Granularity: 60s minimum       Granularity: 1s minimum
CPU: single aggregate number   CPU: per-process breakdown
Memory: freeable only          Memory: active, buffers, dirty pages
Disk: aggregate IOPS            Disk: per-partition I/O
Cost: included                 Cost: CloudWatch Logs ingestion
```

Enhanced Monitoring shows you things like:
- Which OS process is consuming CPU (usually `postgres` worker, but sometimes `autovacuum`)
- Memory broken into active, buffers, cached, dirty, free, swap
- Disk I/O per device
- Network packets per interface

**When to use it:** Any time you see high CPU or disk in standard metrics and need to know which process or query is responsible.

### Metric Math

CloudWatch Metric Math lets you combine metrics into derived values. Useful examples:

```
# Read hit ratio (you want this above 99%)
(BlocksRead_from_cache - BlocksRead_from_disk) / BlocksRead_from_cache * 100

# Connection utilization %
DatabaseConnections / max_connections_parameter * 100

# IOPS utilization %
(ReadIOPS + WriteIOPS) / provisioned_iops * 100
```

### CloudWatch Alarms - What to Monitor

Tier 1 (page immediately):
- CPUUtilization > 90% for 5 minutes
- FreeStorageSpace < 10 GB
- DatabaseConnections > 90% of max_connections
- MaximumUsedTransactionIDs > 1,500,000,000
- ReplicaLag > 30 seconds

Tier 2 (notify, investigate within 1 hour):
- CPUUtilization > 70% for 15 minutes
- FreeableMemory < 20% of total RAM
- ReadLatency > 20ms
- WriteLatency > 10ms

---

## T6.2 - Performance Insights

Performance Insights (PI) is AWS's answer to Oracle's Active Session History (ASH). It captures database state every second and shows you what queries were running and what they were waiting on.

### DB Load

DB Load is the central metric in Performance Insights. It measures average active sessions (AAS) - the number of sessions that were executing or waiting at any given second.

```
DB Load = 1.0 means: on average, 1 session was active every second
DB Load = 8.0 means: on average, 8 sessions were active every second
```

The horizontal line on the PI dashboard shows your vCPU count. When DB Load exceeds vCPU count, your database is saturated - you have more work than the CPU can handle simultaneously.

```
Low DB Load (below vCPU line):
  |████                |
  |████                |
  |████                |  <- DB load well below vCPU count = healthy
  +--------------------+

High DB Load (above vCPU line):
  |████████████████████|
  |████████████████████|  <- DB load exceeds vCPU count = bottleneck
  |████████████████████|
  +--------------------+
  [-- vCPU line -------]
```

### Wait Events

Wait events show what sessions are waiting on. They are the most actionable information in Performance Insights.

Common PostgreSQL wait events and what they mean:

| Wait Event | Category | Meaning | Action |
|------------|----------|---------|--------|
| Lock:relation | Lock | Table-level lock contention | Find blocking query, kill if needed |
| Lock:tuple | Lock | Row-level lock contention | Check long-running transactions |
| LWLock:buffer_mapping | LWLock | Shared buffer lookup contention | Check shared_buffers, hit ratio |
| LWLock:WALWrite | LWLock | WAL writer contention | Check wal_buffers, I/O bandwidth |
| IO:DataFileRead | IO | Reading from disk (cache miss) | Increase shared_buffers or instance RAM |
| IO:WALWrite | IO | Writing WAL to disk | Check storage IOPS, wal_sync_method |
| IO:BufFileRead | IO | Reading temp files (sort spill) | Increase work_mem |
| CPU | CPU | Active CPU computation | Check for full table scans, missing indexes |
| Client:ClientRead | Client | Waiting for client to send query | Network latency or slow client |
| Client:ClientWrite | Client | Waiting for client to receive results | Large result sets, slow network |

### Top SQL

The Top SQL tab shows queries ranked by DB Load contribution. Each query shows:
- Load (average active sessions contributed)
- Executions per minute
- Average latency
- Wait event breakdown

**Key insight:** The query consuming the most DB Load is not always the slowest individual query. A query running 10,000 times per minute at 1ms each contributes more load than one query running once per minute at 500ms.

### Performance Insights Retention

| Retention | Cost |
|-----------|------|
| 7 days | Free |
| Up to 2 years | $0.02 per vCPU per hour |

Enable long retention for production databases where you need to compare performance week-over-week.

---

## T6.3 - Tuning with Wait Events

Wait events tell you where time goes. The tuning strategy is: identify the dominant wait event, understand why it occurs, then eliminate or reduce it.

### Wait Event Tuning Playbook

```
Step 1: Look at the PI dashboard for the last 1 hour
Step 2: Find the dominant wait event (largest colored section)
Step 3: Use the table below to identify the root cause
Step 4: Apply the fix
Step 5: Monitor for 30 minutes to confirm improvement
```

### Wait Event to Root Cause Mapping

**IO:DataFileRead - Disk reads (buffer cache miss)**
- Root cause: working set larger than shared_buffers, or index missing
- Diagnostic: `SELECT * FROM pg_stat_bgwriter;` - check buffers_alloc vs buffers_clean
- Fix options: increase shared_buffers, add index, increase instance size

**Lock:relation - Table lock contention**
- Root cause: DDL operations (ALTER TABLE, VACUUM FULL, TRUNCATE) blocking reads/writes
- Diagnostic: `SELECT * FROM pg_locks JOIN pg_stat_activity USING (pid);`
- Fix: use concurrent operations (CREATE INDEX CONCURRENTLY), avoid VACUUM FULL on live tables

**Lock:tuple - Row lock contention**
- Root cause: long-running transactions holding row locks
- Diagnostic: `SELECT pid, now() - xact_start AS age, query FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY age DESC;`
- Fix: break up long transactions, add statement_timeout, application-level retry logic

**LWLock:buffer_mapping - Shared buffer contention**
- Root cause: too many sessions competing to find/load pages into shared_buffers
- Fix: increase shared_buffers, reduce connection count, use connection pooling

**IO:BufFileRead / IO:BufFileWrite - Temp file I/O (sort/hash spills)**
- Root cause: work_mem too low for query's sort or hash operations
- Diagnostic: `SELECT * FROM pg_stat_statements WHERE temp_blks_read > 0 ORDER BY temp_blks_read DESC;`
- Fix: increase work_mem (carefully - it multiplies per session)

**CPU - High CPU with no dominant wait**
- Root cause: sequential scans, complex aggregations, inefficient queries
- Diagnostic: check Top SQL in PI for queries with high calls * mean_exec_time
- Fix: add indexes, rewrite queries, use partitioning

### Systematic Wait Analysis Query

```sql
-- Run this on your DB to see current wait events
SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions,
    array_agg(pid) AS pids
FROM pg_stat_activity
WHERE state != 'idle'
  AND wait_event IS NOT NULL
GROUP BY 1, 2
ORDER BY sessions DESC;
```

---

## T6.4 - DevOps Guru

Amazon DevOps Guru is a machine learning service that analyzes operational data and detects anomalies before they become outages.

### How It Works

```
CloudWatch Metrics ----+
CloudWatch Logs    ----|---> DevOps Guru ML Model ---> Insights ---> SNS/EventBridge
Config changes     ----|
CloudTrail events  ----+
```

DevOps Guru builds a baseline of normal behavior for your RDS instance over 2 weeks, then alerts when metrics deviate significantly. It correlates multiple signals - for example, it might notice that CPU spiked at the same time a parameter group was changed.

### Insight Types

**Reactive insights:** Problem already occurring. DevOps Guru detected an anomaly.
**Proactive insights:** Potential problem detected before it impacts users. For example, it might predict that your disk will fill up in 4 days based on growth rate.

### RDS-Specific Anomalies DevOps Guru Detects

- Sudden increase in database connections
- Unusual query latency patterns
- Replication lag growing beyond normal variance
- Storage growth rate acceleration
- CPU patterns inconsistent with historical baseline
- Autovacuum running more frequently than baseline

### Cost

DevOps Guru charges per resource analyzed per hour. For RDS, one instance = one resource = ~$0.0028/hr = ~$2/month. Enable it selectively on production instances.

### Integration Points

DevOps Guru can notify via:
- SNS topic (to PagerDuty, Slack, email)
- EventBridge (to Lambda for automated remediation)

---

## T6.5 - pg_stat_statements

`pg_stat_statements` is the most important PostgreSQL extension for performance work. It tracks execution statistics for every unique query (normalized - parameters replaced with $1, $2, etc.).

### Key Columns

| Column | What It Tells You |
|--------|------------------|
| query | Normalized query text |
| calls | Total executions since last reset |
| total_exec_time | Total ms spent executing |
| mean_exec_time | Average ms per execution |
| stddev_exec_time | Variance in execution time (high = inconsistent plans) |
| rows | Total rows returned |
| shared_blks_hit | Buffer cache hits |
| shared_blks_read | Disk reads (cache misses) |
| shared_blks_dirtied | Pages modified (writes) |
| temp_blks_read | Temp file reads (sort spills) |
| temp_blks_written | Temp file writes (sort spills) |
| blk_read_time | Time waiting on disk reads (requires track_io_timing=on) |
| blk_write_time | Time waiting on disk writes |
| wal_bytes | WAL generated (writes) |

### Essential Queries

**Top 10 queries by total time:**
```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

**Top queries by disk reads (most likely to benefit from indexing):**
```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    shared_blks_read,
    shared_blks_hit,
    round(shared_blks_read::numeric / nullif(calls, 0), 1) AS reads_per_call
FROM pg_stat_statements
WHERE shared_blks_read > 0
ORDER BY shared_blks_read DESC
LIMIT 10;
```

**Queries with high execution time variance (unstable plans):**
```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    round(stddev_exec_time / nullif(mean_exec_time, 0) * 100, 1) AS cv_pct
FROM pg_stat_statements
WHERE calls > 100
  AND mean_exec_time > 10
ORDER BY cv_pct DESC
LIMIT 10;
```

**Queries generating temp files (need more work_mem):**
```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    temp_blks_written,
    round(temp_blks_written::numeric / nullif(calls, 0), 1) AS temp_blks_per_call
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

### pg_stat_statements in AWS

On RDS/Aurora, enable it via parameter group:
```
shared_preload_libraries = pg_stat_statements
pg_stat_statements.track = all          # track top-level and nested statements
pg_stat_statements.max = 10000          # max unique queries tracked
track_io_timing = on                    # enables blk_read_time/blk_write_time
```

Requires instance restart. Performance Insights Top SQL is powered by pg_stat_statements under the hood.

### Resetting Statistics

```sql
-- Reset all statistics (do this at start of a performance investigation)
SELECT pg_stat_statements_reset();

-- Or reset per query (PostgreSQL 14+)
SELECT pg_stat_statements_reset(userid, dbid, queryid);
```

---

## T6.6 - Optimized Reads

Optimized Reads is an AWS storage feature available on certain RDS and Aurora instance families. It uses local NVMe SSD to accelerate read performance.

### RDS Optimized Reads

Available on: db.m6gd, db.m7gd, db.r6gd, db.r7gd, db.x2gd instance families (the "d" suffix = NVMe local storage).

How it works:
- PostgreSQL temporary files (from sort/hash spills) are written to NVMe instead of EBS
- NVMe is 10-100x faster than EBS for sequential I/O
- Benefit is proportional to how often your queries spill to disk

```
Without Optimized Reads:          With Optimized Reads:
  Sort needs 2GB work              Sort needs 2GB work
  work_mem = 256MB                 work_mem = 256MB
  Spills 1.75GB to EBS    --->     Spills 1.75GB to NVMe
  EBS latency: 1-5ms               NVMe latency: <0.1ms
  Sort time: 30s                   Sort time: 3s
```

**Important:** The NVMe is used only for temp files, not for your actual data. Your data still lives on EBS. This is why Optimized Reads helps only for query-heavy workloads with large sorts.

### Aurora Optimized Reads (Tiered Cache)

Aurora Optimized Reads on compatible instance types (r6gd, r7gd) uses NVMe as a second-tier cache:

```
Tier 1 Cache: shared_buffers (in RAM)
     - Fast, limited by RAM
     - Default: ~75% of RAM

Tier 2 Cache: NVMe local SSD (Aurora tiered cache)
     - Still very fast, much larger than RAM
     - Can be 4-8x the size of RAM

Tier 3: Aurora distributed storage (S3-backed)
     - Slower, always available
```

When Aurora needs a page not in RAM, it checks the NVMe cache before going to distributed storage. This significantly reduces distributed storage reads (which have higher latency than NVMe).

**Enabling Aurora tiered cache:** Set `aurora_tiered_cache_enabled = 1` in the parameter group. No restart required on Aurora.

### When Optimized Reads Helps Most

- Analytical queries with large sorts (ORDER BY large datasets, GROUP BY, DISTINCT)
- Hash joins on large tables
- Queries that regularly spill to temp files (visible as IO:BufFileRead wait events)
- Reporting workloads running alongside OLTP

---

## T6.7 - Optimized Writes and Aurora I/O-Optimized

### RDS Optimized Writes

Standard PostgreSQL uses double-write: it writes a page to the WAL, then writes it to the data file. This protects against partial page writes during a crash.

RDS Optimized Writes eliminates the full-page write by using a checksum-protected write path at the storage layer. The result is:
- ~2x write throughput improvement for write-heavy workloads
- Significant reduction in WAL volume (fewer full-page images)

```
Standard writes:              Optimized writes:
  WAL: full page image (8KB)    WAL: only changed bytes (often <1KB)
  + data file write (8KB)       + data file write (8KB)
  = 16KB per modified page      = fewer KB per modified page
```

Available on: db.m6i, db.m7g, db.r6i, db.r7g, db.x2g, and newer families.
Enable via: `rds.optimized_writes = ON` in parameter group.

### Aurora I/O-Optimized

Aurora storage pricing has two modes:

**Standard mode:**
- Pay per I/O operation ($0.20 per million IOs in us-east-1)
- Pay per GB of storage
- Good for low-to-moderate I/O workloads

**I/O-Optimized mode:**
- No per-I/O charge
- Higher storage per-GB price (+25% storage)
- Good for I/O-heavy workloads

```
Break-even calculation:
  I/O-Optimized costs more when: storage_GB * 0.25 > monthly_IO_cost
  I/O-Optimized saves money when: monthly_IO_cost > storage_GB * 0.25

  Example: 500GB database, 2B monthly IOs
  Standard:   $0.10/GB * 500 + $0.20/million * 2000 = $50 + $400 = $450/month
  Optimized:  $0.125/GB * 500 + $0 IO = $62.50/month
  Savings:    $387.50/month
```

Use the AWS Console cost calculator or this rule of thumb: if your Aurora I/O bill is more than 25% of your storage bill, switch to I/O-Optimized.

---

## T6.8 - Cluster Cache Management (CCM)

### The Failover Cache Problem

When an Aurora cluster fails over from primary to reader, the new primary starts with a cold buffer cache. The old primary's shared_buffers had your hot working set. The new primary has nothing cached.

This causes a "cold start" performance hit: immediately after failover, all queries miss the cache and hit storage. This can take 30-60 minutes to warm up on large instances.

### How CCM Solves This

Cluster Cache Management lets you designate one reader instance as the "failover target." Aurora continuously replicates the primary's buffer cache state to this reader. On failover, the promoted reader already has a warm cache.

```
Without CCM:
  Primary (warm cache) --> fails --> Reader promoted (cold cache)
  Post-failover: 30-60 min of degraded performance

With CCM:
  Primary (warm cache) --> cache state replicated --> Designated failover target
  Primary fails --> Designated reader promoted (warm cache already there)
  Post-failover: <2 min of degraded performance
```

### CCM Configuration

CCM is controlled by cluster-level parameter:
```
apg_ccm_enabled = 1   (Aurora PostgreSQL only)
```

And the instance-level parameter on the designated failover target:
```
apg_ccm_instance_mode = read-only-writer
```

The designated failover target must be the same instance class as the primary (because it holds the same amount of cache).

### CCM Limitations

- Only one reader can be the designated failover target
- The target reader has slightly higher memory overhead (maintaining two cache states)
- Only effective if you use the designated reader as the failover target (set via RDS failover priority)
- Available only on Aurora PostgreSQL (not RDS PostgreSQL)

---

## T6.9 - Connection Management and RDS Proxy

### The Connection Problem

PostgreSQL spawns one OS process per connection. Each process uses 5-10MB of RAM just for overhead, before any query memory. At 500 connections, that's 2.5-5GB of overhead RAM gone.

More importantly, PostgreSQL's process-per-connection model does not scale linearly. Context switching between hundreds of processes degrades performance faster than adding more RAM helps.

```
Connections vs. Performance:
  <100 connections: linear performance improvement
  100-500 connections: diminishing returns
  >500 connections: performance can degrade despite more capacity
```

### max_connections Formula

```
max_connections should be approximately:
  (RAM in GB * 1000) / 10  = rough max before RAM pressure

  More precisely:
  OLTP workloads: (vCPUs * 4) to (vCPUs * 10)
  Analytical workloads: (vCPUs * 2) to (vCPUs * 4)

  For production: always use a connection pooler
```

### RDS Proxy Architecture

```
Application Servers
    |    |    |    |     (hundreds of short-lived connections)
    v    v    v    v
  +-----------------+
  |    RDS Proxy    |    (connection pool - maintains few long-lived connections)
  |  (multiplexes)  |
  +-----------------+
         |
    (small pool of persistent connections)
         v
  +-----------------+
  |   RDS Instance  |
  |  (sees 20-50    |
  |   connections)  |
  +-----------------+
```

### RDS Proxy Key Features

- **Connection multiplexing:** Many app connections share few DB connections
- **Connection pinning:** Transactions with session-level state (SET, advisory locks, temp tables) get pinned to one DB connection for their duration
- **Automatic failover:** Proxy detects failover and reconnects to the new primary, masking the event from the application
- **IAM authentication:** Proxy can authenticate via IAM instead of requiring the DB password in every application
- **Secrets Manager integration:** Proxy fetches and rotates DB credentials automatically

### Connection Pinning

Connection pinning is when RDS Proxy cannot multiplex a connection because the application is using session-level state. A pinned connection = one app connection = one DB connection. Pinning eliminates the multiplexing benefit.

Causes of pinning:
- `SET` commands (SET search_path, SET work_mem, etc.)
- Session-level advisory locks (`pg_advisory_lock`)
- Temporary tables (`CREATE TEMPORARY TABLE`)
- Prepared statements (some drivers)
- `LISTEN` / `NOTIFY`

To minimize pinning: set parameters at the parameter group level rather than via SET, use transaction-level advisory locks, avoid temp tables in pooled connections.

---

## T6.10 - Autovacuum at Scale

### Why Autovacuum Matters

PostgreSQL's MVCC (Multi-Version Concurrency Control) model means every UPDATE creates a new row version, and every DELETE marks the old version as dead. Dead rows (dead tuples) accumulate over time. Autovacuum reclaims this space and updates table statistics for the query planner.

Neglected autovacuum leads to:
- Table and index bloat (wasted disk space, slower scans)
- Degraded query performance (stale statistics, planner chooses bad plans)
- Transaction ID wraparound (catastrophic - PostgreSQL shuts down to prevent data corruption)

### Autovacuum Architecture

```
autovacuum launcher (1 process)
    |
    +--- autovacuum worker 1 --> working on table A
    +--- autovacuum worker 2 --> working on table B
    +--- autovacuum worker 3 --> working on table C
    (max workers controlled by autovacuum_max_workers)
```

### When Autovacuum Triggers

A table gets vacuumed when:
```
dead_tuples > autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor * table_rows)

Default:
  autovacuum_vacuum_threshold = 50       # always vacuum if 50+ dead tuples
  autovacuum_vacuum_scale_factor = 0.2   # vacuum if 20% of rows are dead
```

For a table with 100 million rows, this means autovacuum waits until 20 million rows are dead. That is too late for large tables.

### Tuning for Large Tables

Set table-level storage parameters to override autovacuum defaults:
```sql
ALTER TABLE large_table SET (
    autovacuum_vacuum_scale_factor = 0.01,    -- vacuum when 1% dead (not 20%)
    autovacuum_vacuum_threshold = 1000,        -- or when 1000 dead rows
    autovacuum_analyze_scale_factor = 0.005,  -- analyze when 0.5% changed
    autovacuum_vacuum_cost_delay = 2           -- less throttling (default 20ms)
);
```

### Autovacuum Cost-Based Throttling

Autovacuum throttles itself to avoid impacting live queries. It uses a cost model:

```
autovacuum_vacuum_cost_delay = 20ms   # sleep 20ms between cost periods
autovacuum_vacuum_cost_limit = 200    # cost budget per period

Cost per operation:
  vacuum_cost_page_hit = 1            # reading from shared_buffers
  vacuum_cost_page_miss = 10          # reading from disk
  vacuum_cost_page_dirty = 20         # writing a modified page
```

When autovacuum is consistently behind (tables bloating despite running), reduce cost_delay or increase cost_limit.

### Transaction ID Wraparound

PostgreSQL uses 32-bit transaction IDs. After ~2.1 billion transactions, the IDs wrap around. PostgreSQL protects against this by marking pages as "frozen" (frozen pages are considered older than any transaction ID).

```
Wraparound danger zones:
  > 1.0B from oldest unfrozen XID: autovacuum starts freezing aggressively
  > 1.5B from oldest: Warning in logs
  > 1.6B from oldest: PostgreSQL refuses new connections!

Monitor with:
  SELECT max(age(datfrozenxid)) FROM pg_database;
  -- Alert if this exceeds 1,500,000,000
```

---

## T6.11 - Query Plan Management (Aurora)

### The Problem: Plan Instability

PostgreSQL's query planner re-plans every statement (unless you use prepared statements). When table statistics change, the planner may choose a different execution plan. Sometimes the new plan is better. Sometimes it is dramatically worse.

Plan instability is common after:
- ANALYZE runs (statistics update)
- Large data loads
- planner-related parameter changes
- PostgreSQL minor version upgrades

### Aurora Query Plan Management

Aurora PostgreSQL provides `apg_plan_mgmt`, an extension that captures and manages query execution plans.

**Plan states:**
```
Unapproved: Plan has been captured but not reviewed
Approved:   Plan has been reviewed and is allowed to run
Rejected:   Plan is explicitly blocked (optimizer will not use it)
Preferred:  Plan should be used over other approved plans
```

### Plan Management Workflow

```
Step 1: Enable automatic capture
  SET apg_plan_mgmt.capture_plan_baselines = automatic;

Step 2: Plans execute normally, Aurora captures them

Step 3: Review captured plans
  SELECT * FROM apg_plan_mgmt.dba_plans;

Step 4: Approve good plans
  SELECT apg_plan_mgmt.set_plan_status(sql_hash, plan_hash, 'Approved');

Step 5: Use managed plans
  SET apg_plan_mgmt.use_plan_baselines = true;
  -- Now only Approved plans run; new plans run as Unapproved (and execute)
  -- unless use_plan_baselines is set, in which case unapproved plans
  -- are blocked in favor of approved ones
```

### Evolving Plans

When a new plan is discovered, you can compare it to the approved plan:
```sql
SELECT apg_plan_mgmt.evolve_plan_baselines(
    sql_hash,
    plan_hash,
    0.1,           -- approve if new plan is at least 10% faster
    'approve'      -- action: 'approve' or 'reject'
);
```

This function actually executes both plans and compares the results. Use it during maintenance windows.

---

## T6.12 - Memory Parameter Tuning

### PostgreSQL Memory Architecture

```
Instance RAM
├── shared_buffers          (~25% of RAM)     - shared cache for all sessions
├── OS page cache           (~50% of RAM)     - used by PostgreSQL for WAL + sequential scans
└── Per-session memory:
    ├── work_mem            (per sort/hash)   - multiplied by sessions and operations
    ├── maintenance_work_mem (per vacuum)     - used by autovacuum and VACUUM
    └── temp_buffers        (per session)     - for temporary tables
```

### shared_buffers

The shared buffer cache holds recently-accessed data pages. All sessions share this single pool.

```
Rule of thumb:
  shared_buffers = 25% of RAM

  On RDS, this is the default. Do NOT set it above 40% of RAM.
  PostgreSQL also relies on the OS page cache for sequential scans,
  and stealing too much RAM for shared_buffers hurts overall performance.

  Example:
  db.r6g.xlarge = 32GB RAM
  shared_buffers = 8GB (25%)
```

Monitor with:
```sql
SELECT
    sum(heap_blks_hit) AS cache_hits,
    sum(heap_blks_read) AS disk_reads,
    round(sum(heap_blks_hit)::numeric / nullif(sum(heap_blks_hit + heap_blks_read), 0) * 100, 2) AS hit_ratio
FROM pg_statio_user_tables;
-- hit_ratio should be > 99% for OLTP
```

### work_mem

work_mem is the memory allocated for each sort or hash operation. One query can have multiple sort/hash operations. With 100 sessions each running a query with 3 sort operations, that's 300 * work_mem in use.

```
Calculating safe work_mem:
  Available for sessions = RAM - shared_buffers - OS overhead
  Max concurrent sort ops = max_connections * 3   (rough estimate)
  Safe work_mem = available_for_sessions / max_concurrent_sort_ops

  Example:
  32GB RAM, shared_buffers = 8GB
  Available = 32 - 8 - 4 (OS) = 20GB
  max_connections = 200, 3 ops each = 600 ops
  Safe work_mem = 20GB / 600 = ~34MB

  Default: 4MB (very conservative, many queries will spill to disk)
  Reasonable for OLTP: 16MB to 64MB
  Analytical queries: set higher per-session: SET work_mem = '512MB';
```

### maintenance_work_mem

Used by VACUUM, ANALYZE, CREATE INDEX, and ALTER TABLE ... ADD FOREIGN KEY.

```
Rule of thumb: 256MB to 2GB for production
Autovacuum uses autovacuum_work_mem (defaults to maintenance_work_mem)

Set higher for initial index builds:
  SET maintenance_work_mem = '2GB';
  CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
```

### effective_cache_size

This is NOT a memory allocation. It is a hint to the planner about how much memory the OS page cache is likely to have available. The planner uses it to estimate whether an index scan will find its pages in cache.

```
Rule of thumb: effective_cache_size = 75% of RAM

If set too low: planner prefers sequential scans over index scans
               (thinks indexes are expensive because pages won't be cached)
If set too high: planner overestimates cache hits, may choose bad plans

On RDS: AWS sets this to 75% of RAM by default. Usually leave it alone.
```

### Memory Parameter Reference Table

| Parameter | Default | Recommended | When to Change |
|-----------|---------|-------------|----------------|
| shared_buffers | 128MB | 25% of RAM | Default on RDS is already tuned |
| work_mem | 4MB | 16-64MB OLTP | Queries spilling to disk (IO:BufFileRead) |
| maintenance_work_mem | 64MB | 256MB-2GB | Slow VACUUM, slow index builds |
| effective_cache_size | 4GB | 75% of RAM | Default on RDS is already tuned |
| temp_buffers | 8MB | 8-64MB | Heavy temp table usage |
| wal_buffers | -1 (auto) | auto (16MB) | High-write workloads, WAL bottlenecks |
| autovacuum_work_mem | -1 (uses maintenance_work_mem) | 256MB-1GB | autovacuum running slow |
