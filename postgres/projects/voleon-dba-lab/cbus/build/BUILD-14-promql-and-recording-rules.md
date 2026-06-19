# Build Guide 14: PromQL Mastery and Advanced Grafana Dashboarding

| | |
|---|---|
| **Time** | 120 minutes |
| **Server** | pg-ops (34.228.32.17) for Prometheus and Grafana; pg-primary (100.26.54.122) and pg-replica (54.144.241.128) for PostgreSQL metrics |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- The difference between instant vectors and range vectors in PromQL
- How to use label matchers to filter metrics by database, instance, or job
- The key PromQL functions every DBA must know: rate(), irate(), increase(), and aggregation operators
- 15 PostgreSQL-specific PromQL queries that answer real operational questions
- 10 essential system-level queries for CPU, memory, disk, and network
- How to build Grafana dashboards from scratch using the UI
- How to use Grafana variables so one dashboard covers all your instances
- How to export, version, and provision dashboards as code

## Prerequisites

- You have completed BUILD-08 (Prometheus and Grafana Monitoring)
- You have completed BUILD-13 (Alertmanager Setup)
- Prometheus is running on pg-ops at port 9090
- Grafana is running on pg-ops at port 3000
- node_exporter is running on all four nodes
- postgres_exporter is running on pg-primary and pg-replica

---

## Section 1: PromQL Fundamentals

PromQL is the query language built into Prometheus. Every Grafana panel that shows metrics, every alert rule, and every recording rule is written in PromQL. Learning it well is the difference between copying dashboard snippets from the internet and actually understanding what your monitoring is telling you.

### 1.1 Instant Vectors vs Range Vectors

This distinction is the foundation of everything in PromQL. If you get confused about a query, it is almost always because of a mismatch between these two types.

**Instant vector** - a snapshot of a metric at a single point in time. Every raw metric selector returns an instant vector by default.

```
pg_stat_activity_count
```

This returns one value per label combination at the current scrape timestamp. If you have two databases being monitored, you get two values.

**Range vector** - a window of samples over a time range. You create a range vector by appending a duration in square brackets to a selector.

```
pg_stat_activity_count[5m]
```

This returns all samples collected in the last 5 minutes for each label combination. You cannot graph a range vector directly - Grafana cannot plot a list of samples. Range vectors exist to be fed into functions like `rate()` or `avg_over_time()` that reduce them back to a single value.

Think of it this way:
- Instant vector = current reading on a gauge
- Range vector = the log of readings over the last N minutes

### 1.2 Label Matchers

Prometheus stores every metric with a set of labels - key/value pairs that identify what the metric is about. For example, `node_cpu_seconds_total` has labels like `instance`, `cpu`, and `mode`. You filter metrics by matching on those labels.

There are four label matcher operators:

**Exact match** (`=`) - returns only series where the label equals this value exactly.

```
node_cpu_seconds_total{mode="idle"}
```

**Not equal** (`!=`) - excludes series where the label equals this value.

```
node_cpu_seconds_total{mode!="idle"}
```

**Regex match** (`=~`) - returns series where the label matches the regular expression.

```
node_cpu_seconds_total{instance=~"pg-primary.*"}
```

**Regex exclude** (`!~`) - excludes series where the label matches the regular expression.

```
node_cpu_seconds_total{mode!~"idle|iowait"}
```

You can combine multiple matchers inside one set of curly braces:

```
pg_stat_activity_count{datname="quantdb", state="active"}
```

This returns the count of active connections specifically on the quantdb database.

### 1.3 Time Durations

Whenever you write a range vector or use functions that accept a duration, you write the duration in a specific format:

| Symbol | Meaning |
|--------|---------|
| `s` | seconds |
| `m` | minutes |
| `h` | hours |
| `d` | days |
| `w` | weeks |
| `y` | years |

Examples:

```
pg_stat_activity_count[5m]     # last 5 minutes of samples
node_filesystem_free_bytes[1h] # last 1 hour of samples
pg_stat_bgwriter_checkpoints_timed_total[1d] # last 1 day
```

For `rate()` and `irate()`, the rule of thumb is: the range should be at least 4x your scrape interval. If Prometheus scrapes every 15 seconds, use at least `[1m]` for irate and `[5m]` for rate.

### 1.4 Basic Selectors - Exploring the Lab's Metrics

Before writing complex queries, explore what metrics exist. Open the Prometheus UI in your browser.

On your **local machine**, open a browser and go to:

```
http://34.228.32.17:9090
```

Click the metrics explorer button (the cube icon next to the query field) or type these selectors into the query field one at a time and click Execute.

**Check which targets are up:**

```
up
```

Expected output (yours will differ):

```
up{instance="localhost:9090",job="prometheus"}  1
up{instance="pg-primary:9187",job="postgres"}   1
up{instance="pg-replica:9187",job="postgres"}   1
up{instance="pg-ops:9100",job="node"}           1
up{instance="pg-primary:9100",job="node"}       1
up{instance="pg-replica:9100",job="node"}       1
up{instance="pg-backup:9100",job="node"}        1
```

A value of `1` means the target is reachable. A value of `0` means Prometheus cannot scrape it. This is always your first check when something looks wrong.

**CPU time broken down by mode:**

```
node_cpu_seconds_total
```

You will see many series - one per CPU core per mode (idle, user, system, iowait, steal, etc.).

**Active connections to PostgreSQL:**

```
pg_stat_activity_count
```

You will see series per database, per state (active, idle, idle in transaction).

Now that you know how to explore, let's learn the functions that make these metrics useful.

---

## Section 2: PromQL Functions and Operators

### 2.1 rate() vs irate()

These are the two most important functions in PromQL for a DBA. Both calculate the per-second rate of change of a counter. Counters are metrics that only go up (like total commits, total bytes written). Raw counter values are useless for graphing - you want the rate.

**rate()** calculates the average rate over the entire range window. It is smooth and reliable. Use it for dashboards and alert rules.

```
rate(pg_stat_database_xact_commit_total{datname="quantdb"}[5m])
```

This gives you the average commits per second over the last 5 minutes.

**irate()** calculates the rate using only the last two data points in the range window. It is spiky and reactive. Use it when you need to detect very short bursts.

```
irate(node_cpu_seconds_total{mode="user"}[5m])
```

The `[5m]` window in irate is not the averaging window - it is just how far back Prometheus looks to find two data points. irate still only uses the last two.

**When to use each:**

| Situation | Use |
|-----------|-----|
| Dashboard panels showing trends | rate() |
| Alert rules - avoid false positives | rate() |
| Detecting momentary CPU spikes | irate() |
| Transaction rate trends | rate() |
| Spotting sudden connection bursts | irate() |

### 2.2 increase()

`increase()` returns the total increase in a counter over the range window - not a per-second rate, but a total count.

```
increase(pg_stat_database_xact_commit_total{datname="quantdb"}[1h])
```

This tells you how many commits happened in the last hour. Useful for capacity planning questions like "how many transactions does quantdb process per hour?"

Note: `increase()` handles counter resets (like a PostgreSQL restart) gracefully. It will not give you a huge spike when the counter resets to zero.

### 2.3 over_time Functions

These functions work on range vectors and return statistical summaries over the time window.

**avg_over_time()** - the average value over the range:

```
avg_over_time(pg_stat_activity_count{datname="quantdb"}[30m])
```

**max_over_time()** - the highest value seen in the range:

```
max_over_time(pg_stat_activity_count{datname="quantdb"}[30m])
```

**min_over_time()** - the lowest value seen in the range:

```
min_over_time(pg_stat_activity_count{datname="quantdb"}[30m])
```

These are useful for gauges (metrics that go up and down), not counters. Use them when you want to know "what was the worst memory pressure in the last 30 minutes" or "what was the average connection count over the last hour."

### 2.4 Aggregation Operators

Aggregation operators collapse multiple series into fewer series, combining their values.

**sum** - adds up values across series:

```
sum(pg_stat_activity_count) by (datname)
```

This sums connections across all states, grouped by database name. If quantdb has 5 active and 10 idle connections, you get 15.

**avg** - averages values:

```
avg(node_cpu_seconds_total{mode="idle"}) by (instance)
```

**max** - returns the maximum value:

```
max(node_memory_MemAvailable_bytes) by (instance)
```

**min** - returns the minimum value:

```
min(node_filesystem_avail_bytes{mountpoint="/"}) by (instance)
```

**count** - counts the number of series:

```
count(up{job="node"})
```

This tells you how many node_exporter targets exist.

**topk** - returns the top N series by value:

```
topk(3, pg_stat_activity_count)
```

Returns the 3 label combinations with the highest connection counts.

**bottomk** - returns the bottom N series by value:

```
bottomk(3, node_filesystem_avail_bytes{fstype="xfs"})
```

Returns the 3 filesystems with the least free space - useful for finding which disk is closest to full.

### 2.5 by() and without() Clauses

When you aggregate, you control which labels are preserved in the output.

**by()** - keep only the listed labels, drop the rest:

```
sum(node_cpu_seconds_total{mode!="idle"}) by (instance)
```

The result has only the `instance` label. The `cpu`, `mode`, and `job` labels are dropped.

**without()** - drop the listed labels, keep the rest:

```
sum(node_cpu_seconds_total{mode!="idle"}) without (cpu, mode)
```

This keeps `instance` and `job` but drops `cpu` and `mode`. Use `without()` when there are many labels you want to keep and only a few to drop.

### 2.6 Binary Operators

You can perform arithmetic between two instant vectors or between a vector and a scalar.

**Arithmetic with scalars:**

```
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024
```

Converts bytes to gigabytes.

**Arithmetic between two vectors:**

```
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
```

This calculates memory utilization percentage. When you divide two vectors, Prometheus matches series by their labels. Both sides must have matching label sets or the result will be empty.

**Operator list:**

| Operator | Meaning |
|----------|---------|
| `+` | addition |
| `-` | subtraction |
| `*` | multiplication |
| `/` | division |
| `%` | modulo |
| `^` | exponentiation |

### 2.7 Comparison Operators for Filtering

Comparison operators can be used to filter series. By default, they return only the series where the condition is true, with the value being the left-hand side.

```
pg_stat_activity_count > 10
```

Returns only databases with more than 10 connections.

Add the `bool` modifier to return 0 or 1 instead of filtering:

```
pg_stat_activity_count > bool 10
```

This is useful in alert expressions and when you want to plot "is the threshold breached" as a 0/1 line.

**Comparison operators:**

| Operator | Meaning |
|----------|---------|
| `==` | equal |
| `!=` | not equal |
| `>` | greater than |
| `<` | less than |
| `>=` | greater than or equal |
| `<=` | less than or equal |

### 2.8 The offset Modifier

`offset` lets you look back at what a metric's value was at a previous point in time. This is useful for comparing current state to an earlier state.

```
pg_stat_database_xact_commit_total offset 1h
```

Returns what the commit counter was 1 hour ago. You can use this to calculate how much a counter grew over the last hour:

```
pg_stat_database_xact_commit_total - pg_stat_database_xact_commit_total offset 1h
```

---

## Section 3: PostgreSQL-Specific PromQL Queries

This section walks through 15 practical queries. Run each one in the Prometheus UI at `http://34.228.32.17:9090` as you read through them.

### Query 1: Active Connections by Database

**PromQL:**
```
pg_stat_activity_count{state="active"}
```

**What it measures:** The number of connections currently executing a query in each database. This is different from total connections - idle connections are not doing any work.

**What to watch for:** In a normal OLTP workload, active connections spike briefly and return to near zero. If you see sustained high active connection counts (above 50-100), queries may be taking too long or locking each other.

---

### Query 2: Connection Utilization Percentage

**PromQL:**
```
sum(pg_stat_activity_count) by (instance)
/
pg_settings_max_connections
* 100
```

**What it measures:** What percentage of PostgreSQL's `max_connections` limit is currently in use. PostgreSQL silently refuses new connections once this limit is hit.

**What to watch for:** Alert at 80%. At 90%, application errors from connection refusal are imminent. If you regularly hit 70%+, add PgBouncer or increase `max_connections` (with caution - more connections consume more memory).

---

### Query 3: Transaction Rate (Commits and Rollbacks per Second)

**PromQL:**
```
rate(pg_stat_database_xact_commit_total{datname="quantdb"}[5m])
+
rate(pg_stat_database_xact_rollback_total{datname="quantdb"}[5m])
```

**What it measures:** Total transactions processed per second (successful plus failed). This is your database throughput number.

**What to watch for:** Know your baseline. If your quantdb normally runs 500 TPS and suddenly drops to 50, something is wrong - a blocker, a long-running transaction, or a connectivity problem. Sudden spikes in rollback rate indicate application errors or contention.

To see rollbacks as a separate line:
```
rate(pg_stat_database_xact_rollback_total{datname="quantdb"}[5m])
```

---

### Query 4: Cache Hit Ratio

**PromQL:**
```
rate(pg_stat_database_blks_hit_total{datname="quantdb"}[5m])
/
(
  rate(pg_stat_database_blks_hit_total{datname="quantdb"}[5m])
  +
  rate(pg_stat_database_blks_read_total{datname="quantdb"}[5m])
)
* 100
```

**What it measures:** The percentage of block reads that were served from PostgreSQL's shared_buffers (memory) rather than disk. Higher is better.

**What to watch for:** In a well-tuned OLTP system, cache hit ratio should be above 95%. Below 90% is a warning sign. Below 80% means queries are hitting disk heavily - consider increasing `shared_buffers`, adding memory, or reviewing whether the working set fits in RAM.

---

### Query 5: Tuple Operations Rate

**PromQL:**

Inserts per second:
```
rate(pg_stat_database_tup_inserted_total{datname="quantdb"}[5m])
```

Updates per second:
```
rate(pg_stat_database_tup_updated_total{datname="quantdb"}[5m])
```

Deletes per second:
```
rate(pg_stat_database_tup_deleted_total{datname="quantdb"}[5m])
```

**What it measures:** The write workload on the database - how many rows are being inserted, updated, and deleted each second.

**What to watch for:** High update and delete rates drive dead tuple accumulation, which causes table bloat and slow queries. If updates are consistently above 1000/sec on a large table without autovacuum keeping up, you will see bloat develop over days.

---

### Query 6: Dead Tuple Ratio

**PromQL:**
```
pg_stat_user_tables_n_dead_tup
/
(pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup + 1)
```

The `+ 1` prevents division by zero on empty tables.

**What it measures:** The fraction of rows in each table that are dead tuples - rows that have been updated or deleted but not yet vacuumed away. Dead tuples waste disk space and slow down sequential scans.

**What to watch for:** Above 10% dead tuple ratio on large tables indicates autovacuum is not keeping up. Above 20% on a heavily-written table is a problem that needs immediate attention - either tune autovacuum aggressiveness or trigger a manual VACUUM.

---

### Query 7: Table Bloat Estimation

**PromQL:**
```
topk(10,
  pg_stat_user_tables_n_dead_tup
  /
  (pg_stat_user_tables_n_live_tup + 1)
)
```

**What it measures:** This ranks your top 10 most bloated tables by dead-to-live tuple ratio. It is a proxy for bloat - not a perfect measurement (for that you need pgstattuple), but useful for quick triage.

**What to watch for:** Tables with ratios above 0.2 (20% dead) deserve attention. Cross-reference with `pg_stat_user_tables_last_autovacuum` to see when autovacuum last ran on that table.

---

### Query 8: Replication Lag in Bytes

**PromQL:**
```
pg_replication_slots_pg_wal_lsn_diff
```

Or if your postgres_exporter exposes it differently:

```
pg_stat_replication_pg_wal_lsn_diff
```

**What it measures:** How many bytes of WAL the replica is behind the primary. This is a direct measure of replication lag at the byte level - independent of time.

**What to watch for:** In a healthy streaming replication setup, this should be near zero or a few kilobytes. Alert at 50MB (replica is getting behind). Alert critically at 1GB (replica is significantly behind and recovery after a failover will take time). If a replication slot is unused, bytes can accumulate indefinitely and exhaust disk on the primary.

---

### Query 9: WAL Generation Rate

**PromQL:**
```
rate(pg_wal_bytes_total[5m])
```

If that metric is not present in your postgres_exporter version, use:

```
rate(pg_stat_bgwriter_buffers_alloc_total[5m]) * 8192
```

**What it measures:** How many bytes of WAL PostgreSQL is generating per second. WAL is written for every data-changing transaction. High WAL generation means high write workload and more data that replicas need to apply.

**What to watch for:** Sudden spikes in WAL generation during unexpected times (like off-hours) indicate bulk loads, batch jobs, or unintended large updates. Sustained WAL rates above 50MB/sec on a system with slow disks will cause checkpoint pressure.

---

### Query 10: Checkpoint Frequency and Duration

**PromQL:**

Checkpoints per minute (timed - triggered by checkpoint_timeout):
```
rate(pg_stat_bgwriter_checkpoints_timed_total[5m]) * 60
```

Background writer buffer cleaning rate:
```
rate(pg_stat_bgwriter_buffers_clean_total[5m])
```

Background writer maxpages limit hits (indicates bgwriter cannot keep up):
```
rate(pg_stat_bgwriter_maxwritten_clean_total[5m])
```

**What it measures:** How actively the background writer is cleaning dirty buffers. `buffers_clean_total` shows the rate of buffer writes. `maxwritten_clean_total` counts how often the bgwriter stopped because it hit the `bgwriter_lru_maxpages` limit - a sign it cannot keep up with the write load.

**What to watch for:** If `maxwritten_clean_total` is increasing, consider raising `bgwriter_lru_maxpages` or `bgwriter_lru_multiplier`. This reduces the I/O burden on checkpoints.

---

### Query 11: Lock Waits

**PromQL:**
```
pg_stat_activity_count{wait_event_type="Lock"}
```

**What it measures:** The number of connections currently waiting to acquire a lock. Lock waits cause query latency to pile up and, if the holder never releases, can cause cascading timeouts.

**What to watch for:** Any nonzero value deserves investigation during business hours. More than 5 lock waiters on a single database is a potential incident. Combine this with active session information in PostgreSQL (`pg_locks` and `pg_stat_activity`) to identify the blocking query.

---

### Query 12: Temp File Usage

**PromQL:**

Temp files created per second:
```
rate(pg_stat_database_temp_files_total{datname="quantdb"}[5m])
```

Temp bytes written per second:
```
rate(pg_stat_database_temp_bytes_total{datname="quantdb"}[5m])
```

**What it measures:** PostgreSQL writes temp files when a sort or hash operation cannot fit in `work_mem`. Temp file writes hit the filesystem directly and can be extremely slow compared to in-memory operations.

**What to watch for:** Any temp file activity is worth investigating. Frequent temp file writes indicate either `work_mem` is too low for the query workload, or queries are doing large unoptimized sorts/joins. Check `pg_stat_statements` for the queries generating temp files.

---

### Query 13: Database Size Growth Rate

**PromQL:**
```
rate(pg_database_size_bytes{datname="quantdb"}[1h]) * 3600
```

Multiplying by 3600 converts bytes-per-second to bytes-per-hour, which is easier to reason about.

**What it measures:** How fast the database is growing in size. This includes both live data and dead tuple bloat that has not been vacuumed yet.

**What to watch for:** Use this to project disk exhaustion. If quantdb is growing at 500MB/hour and you have 100GB free, you have about 200 hours. Sudden unexpected growth (10x the baseline) indicates a bloat problem, a bulk load, or an application bug generating excessive data.

---

### Query 14: Index Scan vs Sequential Scan Ratio

**PromQL:**

Sequential scans per second:
```
rate(pg_stat_user_tables_seq_scan[5m])
```

Index scans per second:
```
rate(pg_stat_user_tables_idx_scan[5m])
```

Ratio (higher means more sequential scans relative to index scans):
```
rate(pg_stat_user_tables_seq_scan[5m])
/
(rate(pg_stat_user_tables_idx_scan[5m]) + 1)
```

**What it measures:** How often PostgreSQL is using indexes versus reading entire tables. Sequential scans on large tables are expensive. Index scans are efficient for selective queries.

**What to watch for:** High sequential scan rates on large tables (check `pg_stat_user_tables_seq_tup_read` for the tuple count) indicate missing indexes or queries that are not using available indexes. On small tables, sequential scans are expected and efficient - do not alarm on those.

---

### Query 15: Slow Query Count via pg_stat_statements

If your postgres_exporter is configured with the `pg_stat_statements` collector enabled, you can query:

**PromQL:**
```
topk(10,
  rate(pg_stat_statements_total_time_seconds_total[5m])
  /
  rate(pg_stat_statements_calls_total[5m])
)
```

**What it measures:** The average execution time per call for the top 10 slowest query patterns. `pg_stat_statements` normalizes queries (replacing literal values with `$1`, `$2`, etc.) so you see the query pattern, not every individual query.

**What to watch for:** Any query averaging above 100ms that is called frequently is a tuning candidate. A query averaging 10 seconds called 100 times per minute will cripple a production system.

Note: This metric requires `pg_stat_statements` to be installed in PostgreSQL (`CREATE EXTENSION pg_stat_statements`) and the postgres_exporter to be configured with the statements collector. Verify it is available:

```
pg_stat_statements_calls_total
```

If this returns results, the collector is active.

---

## Section 4: Node/System PromQL Queries

### Query 1: CPU Utilization Percentage

**PromQL:**
```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**What it measures:** The percentage of CPU time that is NOT idle, averaged across all cores on each instance. This is the standard CPU utilization metric.

**What to watch for:** PostgreSQL is CPU-intensive during query processing, sorting, and cryptographic operations. Alert at 80% sustained. At 90%+, query latency degrades rapidly. Correlate CPU spikes with transaction rate spikes to distinguish planned load from runaway queries.

---

### Query 2: Memory Utilization (Excluding Buffers and Cache)

**PromQL:**
```
(
  node_memory_MemTotal_bytes
  - node_memory_MemFree_bytes
  - node_memory_Buffers_bytes
  - node_memory_Cached_bytes
) / node_memory_MemTotal_bytes * 100
```

**What it measures:** The percentage of memory in use by actual processes - excluding the OS page cache and buffers. The OS page cache is not really "used" memory in the problematic sense; it gets released when a process needs more RAM.

**What to watch for:** Alert at 85% real memory utilization. At 95%, the system starts swapping, which causes catastrophic performance for a database server. PostgreSQL itself uses `shared_buffers` (which appears in cached memory) plus per-connection memory for sorts and hash joins.

For a quick available memory check:
```
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024
```

This gives available memory in gigabytes - the most practical number.

---

### Query 3: Disk I/O Utilization

**PromQL:**

Read throughput in MB/s:
```
rate(node_disk_read_bytes_total{device=~"nvme.*|sd.*|xvd.*"}[5m]) / 1024 / 1024
```

Write throughput in MB/s:
```
rate(node_disk_written_bytes_total{device=~"nvme.*|sd.*|xvd.*"}[5m]) / 1024 / 1024
```

**What it measures:** How many megabytes per second are being read from and written to each disk device. For PostgreSQL servers, this is your most important I/O metric.

**What to watch for:** Know your disk's rated throughput (AWS EBS gp3 = 125MB/s baseline, up to 1000MB/s with provisioned IOPS). If you are consistently saturating your disk, queries will queue behind I/O and latency will spike. WAL writes are synchronous by default, so write saturation hits transaction latency directly.

---

### Query 4: Network Throughput

**PromQL:**

Bytes received per second:
```
rate(node_network_receive_bytes_total{device!="lo"}[5m]) / 1024 / 1024
```

Bytes transmitted per second:
```
rate(node_network_transmit_bytes_total{device!="lo"}[5m]) / 1024 / 1024
```

The `{device!="lo"}` filter excludes the loopback interface.

**What it measures:** Network traffic in megabytes per second on the primary network interface. For a database server, outbound traffic is typically query results being sent to clients. High inbound traffic often means replication or bulk data loads.

**What to watch for:** On a streaming replication setup, outbound traffic from the primary should roughly match inbound traffic on the replica. A sudden jump in network traffic with no application deployment is worth investigating.

---

### Query 5: Filesystem Usage Percentage

**PromQL:**
```
100 - (node_filesystem_avail_bytes{fstype=~"xfs|ext4"} / node_filesystem_size_bytes{fstype=~"xfs|ext4"} * 100)
```

**What it measures:** What percentage of each filesystem is occupied. Filtering by `xfs` and `ext4` excludes tmpfs and other virtual filesystems.

**What to watch for:** Alert at 80% full. At 85%, PostgreSQL may struggle to write WAL or temp files. At 95%, a PostgreSQL server can crash or corrupt data. The PostgreSQL data directory, WAL directory, and backup destination all need separate monitoring.

To see the least available filesystem:
```
bottomk(1, node_filesystem_avail_bytes{fstype=~"xfs|ext4"} / 1024 / 1024 / 1024)
```

---

### Query 6: Load Average vs CPU Count

**PromQL:**
```
node_load1 / count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})
```

**What it measures:** The 1-minute load average divided by the number of CPU cores. A value of 1.0 means the system is fully loaded. Above 1.0 means processes are queuing for CPU time.

**What to watch for:** Alert at 2.0 (load average is twice the CPU count - heavy queuing). At 5.0+, the system is severely overloaded. Load average above CPU count is not always a crisis (short bursts are normal) but sustained high load indicates capacity problems.

Also check 5-minute and 15-minute load averages for trend direction:
```
node_load5 / count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})
node_load15 / count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})
```

---

### Query 7: Context Switches Rate

**PromQL:**
```
rate(node_context_switches_total[5m])
```

**What it measures:** How many times per second the kernel is switching between processes or threads. High context switch rates indicate heavy process contention - too many threads competing for CPU time.

**What to watch for:** Baseline varies significantly by workload and CPU count. On a 4-core server, 10,000 context switches per second is normal. Above 100,000 per second consistently indicates a possible problem - too many connections, a thread-heavy application, or kernel scheduling issues. Correlate with CPU utilization.

---

### Query 8: Disk Latency

**PromQL:**

Average read latency in milliseconds:
```
rate(node_disk_read_time_seconds_total{device=~"nvme.*|sd.*|xvd.*"}[5m])
/
rate(node_disk_reads_completed_total{device=~"nvme.*|sd.*|xvd.*"}[5m])
* 1000
```

Average write latency in milliseconds:
```
rate(node_disk_write_time_seconds_total{device=~"nvme.*|sd.*|xvd.*"}[5m])
/
rate(node_disk_writes_completed_total{device=~"nvme.*|sd.*|xvd.*"}[5m])
* 1000
```

**What it measures:** The average time each disk read or write operation takes to complete, in milliseconds.

**What to watch for:** SSD/NVMe drives should complete I/O in under 1ms. EBS gp3 typically shows 1-5ms. Above 20ms write latency means WAL commits are slow and transaction rate will suffer. Above 100ms is a serious problem for a database server.

---

### Query 9: Available Entropy

**PromQL:**
```
node_entropy_available_bits
```

**What it measures:** The number of bits of entropy available in the kernel's random pool. PostgreSQL uses entropy for generating UUIDs and for SSL/TLS operations.

**What to watch for:** Below 1000 bits, PostgreSQL SSL connections may slow down or stall while waiting for entropy. This is more common on virtual machines with low activity. If you see this metric consistently below 500 on a server doing SSL, install `haveged` or `rng-tools` to supplement entropy generation.

---

### Query 10: System Uptime

**PromQL:**
```
node_time_seconds - node_boot_time_seconds
```

To convert to days:
```
(node_time_seconds - node_boot_time_seconds) / 86400
```

**What it measures:** How long the system has been running since its last boot, in seconds (or days with the division).

**What to watch for:** A sudden drop to near zero means the server rebooted unexpectedly. Track this in Grafana with a stat panel. If a database server reboots without a change control, that is an incident.

---

## Section 5: Building Grafana Dashboards

### 5.1 Accessing Grafana

On your **local machine**, open a browser and go to:

```
http://34.228.32.17:3000
```

Log in with:
- Username: `admin`
- Password: `admin` (or whatever was set during BUILD-08)

### 5.2 Create a New Dashboard

From the left sidebar, click the grid icon labeled **Dashboards**, then click the **New** button in the top right, and select **New dashboard**.

You will see a blank dashboard with a prompt to add your first panel. Click **Add visualization**.

You will be asked to select a data source. Click **Prometheus**. This opens the panel editor.

### 5.3 Adding a Panel - Active Connections

In the panel editor, you will see a query field at the bottom. Type this PromQL into the field labeled **Metrics browser** or the expression field:

```
sum(pg_stat_activity_count) by (datname)
```

Click **Run queries**. You should see a graph appear showing connection counts per database.

On the right side of the editor, find the **Panel options** section. Set:
- **Title**: `Active Connections by Database`

Find the **Visualization** dropdown at the top right (it may say "Time series"). Keep it as **Time series** for this panel.

Click **Apply** (top right) to save the panel to the dashboard.

### 5.4 Adding a Stat Panel - Connection Utilization

Click **Add panel** (the `+` button that appears when you hover over the dashboard) or from the top bar click **Add** then **Visualization**.

Select **Prometheus** as the data source.

Enter this query:

```
sum(pg_stat_activity_count) by (instance)
/
pg_settings_max_connections
* 100
```

On the right, change the visualization type from **Time series** to **Stat**.

Set:
- **Title**: `Connection Utilization %`
- Under **Standard options**, set **Unit** to `Percent (0-100)`

Under **Thresholds**, add two thresholds:
- Green base: 0
- Yellow: 70
- Red: 90

Click **Apply**.

### 5.5 Adding a Replication Lag Panel

Add another panel. Enter:

```
pg_replication_slots_pg_wal_lsn_diff
```

Change the visualization to **Stat**.

Set:
- **Title**: `Replication Lag (bytes)`
- **Unit**: `bytes`

Add thresholds:
- Green base: 0
- Yellow: 52428800 (50MB = 50 * 1024 * 1024)
- Red: 1073741824 (1GB)

Click **Apply**.

### 5.6 Adding a System Health Panel - CPU

Add another panel. Enter:

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

Keep as **Time series**.

Set:
- **Title**: `CPU Utilization %`
- **Unit**: `Percent (0-100)`

Under **Standard options**, set **Min** to `0` and **Max** to `100`.

Click **Apply**.

### 5.7 Save the Dashboard

Click the **Save dashboard** icon (floppy disk icon) at the top right of the dashboard.

Name it: `PostgreSQL Overview - quantdb`

Click **Save**.

### 5.8 Panel Types Reference

| Panel Type | Best For |
|-----------|---------|
| Time series | Trends over time - connection count, TPS, cache hit ratio |
| Stat | Single current value - connection %, replication lag |
| Table | Multiple metrics side by side - top tables by dead tuples |
| Gauge | Current value with visual fill - disk usage % |
| Bar chart | Comparing values across instances |
| Heatmap | Distribution of query latencies over time |

---

## Section 6: Advanced Dashboard Techniques

### 6.1 Dashboard Variables for Dynamic Dashboards

Variables make one dashboard work across all your instances instead of hardcoding `pg-primary` into every query.

From the dashboard, click the **gear icon** (Dashboard settings) at the top right. Click **Variables** in the left menu. Click **Add variable**.

Configure the variable:
- **Select variable type**: Query
- **Name**: `instance`
- **Label**: `PostgreSQL Instance`
- **Data source**: Prometheus
- **Query**: `label_values(pg_stat_activity_count, instance)`

This query asks Prometheus: "give me all unique values of the `instance` label from the `pg_stat_activity_count` metric." Prometheus returns `pg-primary:9187` and `pg-replica:9187`.

Set:
- **Multi-value**: enabled (allows selecting multiple instances at once)
- **Include All option**: enabled

Click **Run query** to verify it returns your instances. Click **Update**, then **Save dashboard**.

Now edit any panel and change hardcoded instance references to use the variable:

```
pg_stat_activity_count{instance=~"$instance"}
```

The `=~` is required because `$instance` with multi-value becomes a regex-joined string like `pg-primary:9187|pg-replica:9187`.

### 6.2 Repeating Panels Per Instance

Instead of writing separate panels for each server, use Grafana's repeat feature.

Add a panel. In the panel editor, find **Panel options** and scroll down to **Repeat options**. Set:
- **Repeat by variable**: `instance`
- **Repeat direction**: Horizontal

Now the single panel definition will render once per selected instance value. Change the panel query to use `$instance`:

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m])) * 100)
```

When you select multiple instances from the dropdown, you get a column of CPU panels, one per server.

### 6.3 Annotations for Deployments and Events

Annotations mark a point on the timeline with a label - useful for showing when a deployment happened, when maintenance occurred, or when a failover was triggered.

To add a manual annotation to a time series panel: hold Ctrl and click on the graph at the point in time you want to annotate. A dialog appears. Type a description like "Released app v2.3.1" and click Save.

To configure automatic annotations from Prometheus (e.g., mark when an alert fires):

Go to **Dashboard settings** (gear icon), click **Annotations**, click **Add annotation query**.

Set:
- **Name**: `Alert events`
- **Data source**: Prometheus
- **Query**: `ALERTS{alertstate="firing"}`
- **Title**: `{{alertname}}`
- **Tags**: `{{instance}}`

Now every time an alert fires, a vertical line appears on all time series panels at the moment the alert triggered.

### 6.4 Dashboard Links and Drilldowns

You can link panels to other dashboards for drilldown navigation.

From the panel editor, click the **Panel links** section. Click **Add link**. Set:
- **Title**: `View Node Detail`
- **Type**: Dashboard
- **Dashboard**: (select your node health dashboard)
- **Include current time range**: enabled

When a viewer clicks the panel title, they jump to the detailed dashboard. This lets you build a "summary" dashboard that links to "detail" dashboards.

### 6.5 Alert State on Panels

If you have alert rules configured in Grafana (separate from Prometheus alert rules), you can display the alert state as a colored band on time series panels. When an alert is in a pending or firing state, the panel background changes to yellow or red automatically.

This is configured in the panel's **Alert** tab (available on time series panels only when using the legacy alerting engine). With Grafana Unified Alerting (the default in Grafana 8+), alert state visualization is linked to annotation markers instead.

### 6.6 Row-Level Organization

As dashboards grow, organize panels into rows.

Click **Add** then **Row** from the top menu. Give the row a name like `PostgreSQL Health`. Drag panels into the row by clicking and holding the panel title, then dragging up or into the row header.

Rows can be collapsed by clicking the row header - useful for large dashboards where you only want to see the relevant section.

Suggested row organization for a DBA dashboard:

```
Row: Overview (connection utilization, transaction rate, cache hit ratio)
Row: Replication (lag bytes, lag time, slot status)
Row: I/O and Bloat (dead tuple ratio, temp files, checkpoint frequency)
Row: System Health (CPU, memory, disk usage, disk I/O)
Row: Alerts (panels showing alert state for all rules)
```

---

## Section 7: Dashboard as Code

Hardcoded dashboards in Grafana's database are a liability. If the Grafana container is recreated or the database is reset, you lose your dashboards. The professional approach is to store dashboard JSON in git and provision dashboards programmatically.

### 7.1 Export a Dashboard to JSON

Open your dashboard in Grafana. Click the **Share** icon (box with an arrow) at the top right. Click the **Export** tab. Enable **Export for sharing externally** if you want to use it across different Grafana instances. Click **Save to file**.

This downloads a `.json` file. Open it - it is a complete representation of every panel, variable, and threshold in your dashboard.

### 7.2 Store Dashboard JSON on pg-ops

On **pg-ops**, as **ec2-user** - create a directory for dashboard files:

```
sudo mkdir -p /opt/monitoring/dashboards
```

```
sudo chown ec2-user:ec2-user /opt/monitoring/dashboards
```

Create a placeholder JSON file to test with (you will replace this content with your real exported JSON):

```
vi /opt/monitoring/dashboards/postgres-overview.json
```

Paste your exported dashboard JSON content, then save and exit vi.

### 7.3 Provision Dashboards via the Grafana API

Grafana exposes a REST API at port 3000. You can push dashboard JSON to this API to create or update dashboards.

The API endpoint is `POST /api/dashboards/db`. It expects the dashboard JSON wrapped in a specific request structure - not the raw exported JSON on its own.

On **pg-ops**, as **ec2-user** - install `jq` for JSON manipulation:

```
sudo dnf install -y jq
```

Expected output (yours will differ):

```
Last metadata expiration check: 0:02:14 ago on Wed Jun 18 14:00:00 2025.
Dependencies resolved.
...
Installed:
  jq-1.6-15.el9.x86_64
Complete!
```

Test a single dashboard provision with curl directly:

```
jq -n \
  --argjson dashboard "$(cat /opt/monitoring/dashboards/postgres-overview.json)" \
  '{"dashboard": $dashboard, "folderId": 0, "message": "Provisioned from git", "overwrite": true}' \
| curl -s -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin \
  http://localhost:3000/api/dashboards/db \
  -d @-
```

Expected output (yours will differ):

```
{"id":2,"slug":"postgresql-overview-quantdb","status":"success","uid":"abc123","url":"/d/abc123/postgresql-overview-quantdb","version":1}
```

A `"status":"success"` response means the dashboard was created or updated in Grafana.

### 7.4 Automating Provisioning with a Shell Script

On **pg-ops**, as **ec2-user** - create a provisioning script:

```
vi /opt/monitoring/provision-dashboards.sh
```

Paste this content:

```bash
#!/bin/bash
# Provision all Grafana dashboards from the dashboards directory.
# Usage: ./provision-dashboards.sh

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
DASHBOARD_DIR="/opt/monitoring/dashboards"

for dashboard_file in "${DASHBOARD_DIR}"/*.json; do
    dashboard_name=$(basename "${dashboard_file}")
    echo "Provisioning: ${dashboard_name}"

    payload=$(jq -n \
        --argjson dashboard "$(cat "${dashboard_file}")" \
        '{
            "dashboard": $dashboard,
            "folderId": 0,
            "message": "Provisioned from git",
            "overwrite": true
        }'
    )

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
        "${GRAFANA_URL}/api/dashboards/db" \
        -d "${payload}"
    )

    http_code=$(echo "${response}" | tail -1)
    body=$(echo "${response}" | head -1)

    if [ "${http_code}" = "200" ]; then
        echo "  OK: ${dashboard_name}"
    else
        echo "  FAILED (HTTP ${http_code}): ${body}"
    fi
done

echo "Done."
```

Save and exit vi.

Make the script executable:

```
chmod +x /opt/monitoring/provision-dashboards.sh
```

Run the provisioning script:

```
/opt/monitoring/provision-dashboards.sh
```

Expected output (yours will differ):

```
Provisioning: postgres-overview.json
  OK: postgres-overview.json
Done.
```

### 7.5 Grafana File-Based Provisioning (Alternative Method)

Grafana also supports provisioning from YAML config files that point to dashboard JSON files on disk. This runs at Grafana startup without needing API calls.

On **pg-ops**, as **ec2-user** - check where Grafana provisioning config lives:

```
sudo ls /etc/grafana/provisioning/dashboards/
```

Expected output (yours will differ):

```
sample.yaml
```

Create a provisioning config file:

```
sudo vi /etc/grafana/provisioning/dashboards/voleon-lab.yaml
```

Paste this content:

```yaml
apiVersion: 1

providers:
  - name: voleon-lab
    orgId: 1
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: false
    options:
      path: /opt/monitoring/dashboards
      foldersFromFilesStructure: false
```

Save and exit.

Restart Grafana to pick up the provisioning config:

```
sudo systemctl restart grafana-server
```

Verify Grafana came back up:

```
sudo systemctl status grafana-server
```

Expected output (yours will differ):

```
grafana-server.service - Grafana instance
     Loaded: loaded (/usr/lib/systemd/system/grafana-server.service; enabled; vendor preset: disabled)
     Active: active (running) since Wed 2025-06-18 14:05:22 UTC; 4s ago
   Main PID: 18421 (grafana)
```

Open Grafana in your browser and navigate to **Dashboards**. Your provisioned dashboards now appear automatically. Dashboards loaded this way cannot be edited through the UI (the `allowUiUpdates: false` setting prevents it) - changes must be made to the JSON file on disk and Grafana will reload them every 30 seconds.

### 7.6 Git Workflow for Dashboard as Code

The professional workflow for managing dashboards as code:

On **pg-ops**, as **ec2-user** - initialize a git repository for your monitoring configs:

```
cd /opt/monitoring
```

```
git init
```

```
git add dashboards/postgres-overview.json provision-dashboards.sh
```

```
git commit -m "feat: add postgres overview dashboard and provisioning script"
```

Over time, when you modify a dashboard, export the updated JSON, replace the file, and commit the change:

```
git add dashboards/postgres-overview.json
```

```
git commit -m "feat: add replication lag panel to postgres overview dashboard"
```

Your dashboard git history becomes a record of how your monitoring evolved alongside your database infrastructure. In a real environment, you would push this to a remote repository and run the provisioning script as part of a CI/CD pipeline after each merge to main.

---

## Verification Checklist

After completing this guide, verify the following:

**PromQL - on pg-ops Prometheus UI (http://34.228.32.17:9090):**

- [ ] You can run `up` and see all 7 targets returning 1
- [ ] You can run `rate(pg_stat_database_xact_commit_total{datname="quantdb"}[5m])` and see a nonzero result
- [ ] You can run `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` and see CPU percentages for all nodes
- [ ] You understand the difference between an instant vector and a range vector
- [ ] You can explain when to use rate() vs irate()

**Grafana - on pg-ops Grafana UI (http://34.228.32.17:3000):**

- [ ] You have a dashboard with at least 4 panels saved
- [ ] You have a `$instance` variable configured on the dashboard
- [ ] You can change the instance dropdown and panels update their queries
- [ ] You have exported a dashboard to JSON

**Dashboard as Code:**

- [ ] `/opt/monitoring/dashboards/` contains at least one JSON file
- [ ] `/opt/monitoring/provision-dashboards.sh` exists and is executable
- [ ] Running the script returns `OK` for each dashboard file
- [ ] `/opt/monitoring` is a git repository with at least one commit

---

## Key Concepts Summary

| Concept | One-Line Definition |
|---------|-------------------|
| Instant vector | A single value per metric and label set at a point in time |
| Range vector | A window of samples over a time range - fed into rate(), avg_over_time(), etc. |
| rate() | Average per-second rate of a counter over a range - smooth, for dashboards |
| irate() | Per-second rate using only the last two samples - spiky, for burst detection |
| increase() | Total count increase of a counter over a range |
| by() | Aggregation: keep only these labels |
| without() | Aggregation: drop only these labels |
| Label matcher =~ | Regex match on a label value |
| offset modifier | Compare current value to a past value |
| Grafana variable | A dropdown that substitutes into query labels dynamically |
| Dashboard provisioning | Loading dashboards from JSON files at Grafana startup |
| Dashboard API | REST endpoint at /api/dashboards/db for create and update operations |

---

## What Is Next

Proceed to **BUILD-15** to learn recording rules - how to pre-compute expensive PromQL queries and store the results as new metrics, reducing Prometheus query load on dashboards with many panels.
