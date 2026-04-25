# PostgreSQL Performance Tuning - Complete Reference

A production DBA triages performance problems from the outside in: operating system first, then database configuration, then the specific query. This document follows that order.

---

## 1. OS-Level Diagnostics - Start Here, Always

Before opening `psql`, check the machine. A PostgreSQL problem is often a server problem.

### top / htop

```bash
top -bn1 | head -15
```

Expected output (yours will differ):

```
top - 14:32:01 up 45 days,  3:12,  2 users,  load average: 12.50, 8.30, 4.10
Tasks: 312 total,   5 running, 307 sleeping,   0 stopped,   0 zombie
%Cpu(s): 45.2 us, 12.1 sy,  0.0 ni, 28.4 id,  13.8 wa,  0.0 hi,  0.5 si,  0.0 st
MiB Mem :  64000.0 total,   2100.0 free,  48000.0 used,  13900.0 buff/cache
MiB Swap:   8192.0 total,   6500.0 free,   1692.0 used.  14800.0 avail Mem

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
  14523 postgres  20   0   18.2g   4.1g   4.0g S  89.0  6.4  12:34.56 postgres: backend
  14601 postgres  20   0   18.2g   2.3g   2.2g S  67.0  3.6   8:12.34 postgres: autovacuum
```

**Load Average** - the three numbers (`12.50, 8.30, 4.10`) represent the average number of processes waiting for CPU over the last 1, 5, and 15 minutes. Compare to your CPU count:

- On a **16-core** server, load average 16.0 = 100% utilized, every core busy
- Load average 12.5 on 16 cores = 78% utilized - getting warm
- Load average 32.0 on 16 cores = 200% - processes are queuing, performance degrades
- Trending up (4 -> 8 -> 12) = problem is getting worse right now

**CPU Breakdown:**

| Field | Meaning | What to watch |
|-------|---------|---------------|
| **us** (user) | Time running application code | High us = CPU-bound queries, missing indexes |
| **sy** (system) | Time in kernel calls | High sy = excessive context switching, too many connections |
| **wa** (iowait) | Time waiting for disk I/O | High wa = disk is the bottleneck, check iostat |
| **id** (idle) | Idle time | Low id = server is fully loaded |
| **st** (steal) | Time stolen by hypervisor (VMs) | High st = noisy neighbor, need a bigger instance |

**Memory Fields:**

| Field | Meaning |
|-------|---------|
| **total** | Physical RAM installed |
| **free** | Completely unused (low is normal on Linux - the OS caches aggressively) |
| **used** | Actively used by processes |
| **buff/cache** | Used by OS for disk caching (reclaimable under pressure) |
| **avail Mem** | Memory available without swapping (free + reclaimable cache) - THIS is what matters |

**Swap** - if `used` swap is anything above zero on a PostgreSQL server, investigate immediately. PostgreSQL performance collapses when shared_buffers pages get swapped to disk. A query that takes 5ms from RAM takes 5 seconds from swap.

### vmstat

```bash
vmstat 2 5
```

Expected output (yours will differ):

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 3  0      0 2100000 120000 13800000  0    0   450  1200 8500 12000 45 12 28 14  0
 5  2      0 2050000 120000 13750000  0    0  2800  5600 9200 15000 52 15 18 14  0
12  8   1024 1900000 120000 13600000  4   12  8500 12000 11000 22000 65 20  2 12  0
```

**Key columns:**

- **r** (run queue) - processes waiting for CPU. Consistently > 2x CPU count = CPU saturated
- **b** (blocked) - processes blocked on I/O. Any value > 0 = disk bottleneck
- **si/so** (swap in/out) - should ALWAYS be 0. Any swap activity = emergency
- **bi/bo** (blocks in/out) - disk read/write throughput
- **cs** (context switches) - high values (>50,000) often mean too many connections or lock contention

### iostat

```bash
iostat -xz 2 5
```

Expected output (yours will differ):

```
Device   r/s     w/s   rkB/s    wkB/s  await  avgqu-sz  %util
nvme0n1  850.00  1200.00  54400  76800   1.20    2.45    72.00
nvme1n1   45.00   320.00   2880  20480   0.80    0.29    12.00
```

**Key columns:**

| Column | Meaning | Red flag |
|--------|---------|----------|
| **r/s, w/s** | Read/write IOPS | Compare to your disk's rated IOPS |
| **await** | Average I/O latency in ms | > 10ms on SSD = saturated |
| **avgqu-sz** | Average queue depth | > 4 = requests are queuing |
| **%util** | Percentage of time disk is busy | > 80% = approaching saturation |

On NVMe: await should be < 1ms, %util > 90% is concerning.
On spinning disk: await < 10ms is acceptable, %util > 70% is concerning.

### sar (historical data)

When the problem already passed and you need to find when it started:

```bash
sar -u -f /var/log/sa/sa25 -s 08:00:00 -e 12:00:00
```

Shows CPU history. Use `-r` for memory, `-d` for disk, `-b` for I/O.

### iotop

```bash
sudo iotop -oP
```

Shows which processes are doing the most disk I/O right now. Look for PostgreSQL backends doing unexpected amounts of I/O - often a sign of missing indexes causing full table scans, or temp file spills from under-sized work_mem.

---

## 2. OS Kernel Tuning for PostgreSQL

### vm.swappiness

```bash
sysctl vm.swappiness
# vm.swappiness = 60    <-- default, too high for PostgreSQL
```

Set to 1 (not 0):

```bash
echo 'vm.swappiness = 1' >> /etc/sysctl.d/99-postgresql.conf
sysctl -p /etc/sysctl.d/99-postgresql.conf
```

**Why 1, not 0?** Setting it to 0 tells the kernel to never swap until absolutely forced - which can trigger the OOM killer suddenly instead of gradually swapping. A value of 1 means "avoid swapping as much as possible but don't refuse when memory is critically low."

### vm.dirty_ratio and vm.dirty_background_ratio

These control when the OS flushes dirty pages (modified data in cache) to disk.

```bash
echo 'vm.dirty_ratio = 10' >> /etc/sysctl.d/99-postgresql.conf
echo 'vm.dirty_background_ratio = 3' >> /etc/sysctl.d/99-postgresql.conf
```

- **dirty_background_ratio = 3** - background flushing starts when 3% of RAM is dirty pages. Prevents large write spikes.
- **dirty_ratio = 10** - processes block (stop writing) when 10% of RAM is dirty. Safety valve.

Lower values = more frequent, smaller flushes = smoother I/O. This interacts with PostgreSQL checkpoints - both are trying to flush data to disk.

### vm.overcommit_memory

```bash
echo 'vm.overcommit_memory = 2' >> /etc/sysctl.d/99-postgresql.conf
echo 'vm.overcommit_ratio = 80' >> /etc/sysctl.d/99-postgresql.conf
```

**Why?** The Linux OOM killer can randomly kill the PostgreSQL postmaster, crashing the entire database. Setting overcommit_memory to 2 prevents memory overcommit - the kernel refuses allocations that would exceed physical RAM + swap, rather than allowing them and killing processes later.

With `overcommit_ratio = 80`, the kernel allows allocations up to 80% of RAM + 100% of swap.

### Huge Pages

PostgreSQL allocates shared_buffers as a large contiguous block. Without huge pages, the OS manages this as millions of 4KB pages, each with a TLB (Translation Lookaside Buffer) entry. With huge pages (2MB each), you need 1/512th the TLB entries.

**Step 1 - Check how many huge pages PostgreSQL needs:**

```bash
# With PostgreSQL running:
grep ^VmPeak /proc/$(head -1 /opt/pgsql/data/postmaster.pid)/status
# VmPeak:  18874368 kB
```

```bash
# Calculate: VmPeak / hugepage size (2MB = 2048KB)
echo $((18874368 / 2048 + 1))
# 9208
```

**Step 2 - Configure the kernel:**

```bash
echo 'vm.nr_hugepages = 9208' >> /etc/sysctl.d/99-postgresql.conf
sysctl -p /etc/sysctl.d/99-postgresql.conf
```

**Step 3 - Enable in PostgreSQL:**

```
# postgresql.conf
huge_pages = try    # Use 'on' to fail if unavailable, 'try' to fall back
```

Verify after restart:

```bash
grep HugePages /proc/meminfo
```

Expected output:

```
HugePages_Total:    9208
HugePages_Free:     1024
HugePages_Rsvd:      512
HugePages_Surp:        0
Hugepagesize:       2048 kB
```

### Transparent Huge Pages (THP)

THP must be **disabled** for PostgreSQL. THP causes memory allocation stalls, fragmentation, and latency spikes because the kernel tries to defragment memory in the background to create huge pages.

```bash
echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag
```

Make persistent via a systemd service or add to `/etc/rc.local`.

Verify:

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
# always madvise [never]
```

### ulimits

PostgreSQL needs sufficient file descriptors and processes:

```bash
# /etc/security/limits.d/99-postgresql.conf
postgres  soft  nofile  65536
postgres  hard  nofile  65536
postgres  soft  nproc   65536
postgres  hard  nproc   65536
```

Default is 1024 open files, which limits max_connections and the number of tables PostgreSQL can have open simultaneously.

### File System

**XFS vs ext4:**

- **XFS** - better for large files, better parallel I/O, better for WAL writes. Recommended for PostgreSQL data directories.
- **ext4** - fine for smaller databases, slightly better for many small files.

Mount options for both:

```
/dev/nvme1n1  /opt/pgsql  xfs  defaults,noatime,nodiratime  0 2
```

- **noatime** - disables access time updates on reads. PostgreSQL reads pages constantly - writing access timestamps for each read is pure overhead.
- **nodiratime** - same for directory access times.

### NUMA

On multi-socket servers, Non-Uniform Memory Access (NUMA) means each CPU socket has "local" RAM (fast) and "remote" RAM (slow). PostgreSQL's shared_buffers should be spread across all NUMA nodes, not pinned to one.

```bash
# Start PostgreSQL with interleave mode:
numactl --interleave=all /usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data

# Or in the systemd service file:
# ExecStart=/usr/bin/numactl --interleave=all /usr/pgsql-16/bin/postmaster -D /opt/pgsql/data
```

Check current NUMA status:

```bash
numactl --hardware
```

### Network Tuning for Replication

For streaming replication, keep TCP connections alive to detect failures faster:

```bash
echo 'net.ipv4.tcp_keepalive_time = 60' >> /etc/sysctl.d/99-postgresql.conf
echo 'net.ipv4.tcp_keepalive_intvl = 10' >> /etc/sysctl.d/99-postgresql.conf
echo 'net.ipv4.tcp_keepalive_probes = 6' >> /etc/sysctl.d/99-postgresql.conf
```

This sends a keepalive every 60 seconds, retries every 10 seconds, and gives up after 6 failures (120 seconds to detect a dead connection vs the default 2+ hours).

---

## 3. PostgreSQL Memory Architecture

```
+------------------------------------------------------------------+
|                        Total Server RAM (64 GB)                   |
|                                                                   |
|  +---------------------------+  +------------------------------+  |
|  |    shared_buffers (16 GB) |  |    OS Page Cache (~32 GB)    |  |
|  |    PostgreSQL page cache  |  |    Caches disk reads         |  |
|  |    Shared by all backends |  |    Managed by Linux kernel   |  |
|  +---------------------------+  +------------------------------+  |
|                                                                   |
|  +---------------------------+  +------------------------------+  |
|  |  Per-backend memory       |  |  Background workers          |  |
|  |  - work_mem (per sort/    |  |  - autovacuum workers        |  |
|  |    hash op, NOT per conn) |  |    (maintenance_work_mem)    |  |
|  |  - temp_buffers           |  |  - WAL writer                |  |
|  |  - connection overhead    |  |  - checkpointer              |  |
|  |    (~5-10 MB each)        |  |  - bgwriter                  |  |
|  +---------------------------+  +------------------------------+  |
+------------------------------------------------------------------+
```

### shared_buffers

PostgreSQL's own page cache. Every data page read goes through shared_buffers first. If the page is there (a "hit"), no disk I/O needed. If not (a "miss"), PostgreSQL reads it from disk (which may come from the OS page cache).

**Sizing: 25% of total RAM.**

```sql
ALTER SYSTEM SET shared_buffers = '16GB';  -- on a 64GB server
```

**Why not higher?** PostgreSQL relies on the OS page cache as a second layer. If shared_buffers takes 50% of RAM, the OS cache shrinks, and pages evicted from shared_buffers can't be found in the OS cache either - resulting in more disk reads, not fewer. The 25% rule balances both caches.

- 16 GB server: `shared_buffers = 4GB`
- 64 GB server: `shared_buffers = 16GB`
- 256 GB server: `shared_buffers = 64GB` (some workloads benefit from slightly less)

### work_mem

Memory allocated **per sort or hash operation** within a query - not per connection, not per query. A single complex query with 3 sorts and 2 hash joins uses up to 5 x work_mem.

```sql
ALTER SYSTEM SET work_mem = '16MB';  -- conservative global default
```

**Danger:** If you have 200 connections, each running queries with 3 sort operations:
200 x 3 x 64MB = 38.4 GB - this can blow out your RAM.

**Best practice:** Set a conservative global default, raise per-session for analytics:

```sql
-- For a specific reporting session:
SET work_mem = '256MB';
-- Resets when session ends
```

**Detecting spills:** In EXPLAIN output, look for:

```
Sort Method: external merge  Disk: 45600kB    <-- SPILLED TO DISK
```

vs the healthy version:

```
Sort Method: quicksort  Memory: 2048kB        <-- FITS IN MEMORY
```

If you see "external merge Disk", raise work_mem for that session or globally.

### maintenance_work_mem

Used by VACUUM, CREATE INDEX, ALTER TABLE ADD FOREIGN KEY. These run infrequently, so this can be much higher than work_mem.

```sql
ALTER SYSTEM SET maintenance_work_mem = '2GB';  -- on a 64GB server
```

Larger values make VACUUM and index creation faster. Limited benefit above 2GB for most workloads.

### effective_cache_size

**Not a memory allocation.** This tells the planner how much total cache is available (shared_buffers + OS page cache). It affects whether the planner chooses index scans (expects data to be cached) vs sequential scans.

```sql
ALTER SYSTEM SET effective_cache_size = '48GB';  -- 75% of 64GB RAM
```

Setting this too low makes the planner pessimistic about caching and favor sequential scans.

### temp_buffers

Memory for temporary tables per session. Default 8MB is fine for most workloads. Raise if you use large temp tables in stored procedures.

```sql
ALTER SYSTEM SET temp_buffers = '32MB';
```

### wal_buffers

Shared memory for WAL records before flushing to disk. Default is 1/32 of shared_buffers, capped at 64MB. Almost never needs tuning - leave at default unless you have extremely high write throughput.

---

## 4. Storage and I/O Tuning

### WAL on Separate Disk

WAL writes are sequential and constant. Data writes are random. Putting WAL on a separate volume prevents WAL writes from competing with data I/O.

```
# postgresql.conf
# Symlink pg_wal to a separate mount:
# ln -s /mnt/wal/pg_wal /opt/pgsql/data/pg_wal
```

On cloud instances with high-performance EBS/NVMe, this matters less. On spinning disks, it is critical.

### Checkpoint Tuning

A **checkpoint** flushes all dirty pages from shared_buffers to disk. Checkpoints are triggered by:
1. Time interval (checkpoint_timeout, default 5 minutes)
2. WAL volume (max_wal_size, default 1GB)

```sql
ALTER SYSTEM SET max_wal_size = '4GB';            -- more WAL between checkpoints
ALTER SYSTEM SET min_wal_size = '1GB';            -- keep at least this much WAL
ALTER SYSTEM SET checkpoint_timeout = '15min';     -- longer interval
ALTER SYSTEM SET checkpoint_completion_target = 0.9;  -- spread I/O over 90% of interval
```

```
checkpoint_completion_target = 0.5:  |||||||........  (burst write, then idle)
checkpoint_completion_target = 0.9:  |..|..|..|..|.  (spread out - smoother I/O)
```

**Larger max_wal_size** = fewer checkpoints = less I/O overhead, but longer crash recovery (more WAL to replay). On a 64GB server with NVMe, `4GB-8GB` is a good balance.

### wal_compression

```sql
ALTER SYSTEM SET wal_compression = 'lz4';  -- PG15+, or 'pglz' for older versions
```

Compresses full-page images in WAL records. Reduces WAL volume by 30-60%, which means:
- Less disk I/O for WAL writes
- Faster replication (less data shipped to standbys)
- Trade-off: small CPU cost for compression

### full_page_writes

```sql
SHOW full_page_writes;  -- default: on
```

After each checkpoint, the first write to any page writes the entire 8KB page to WAL (not just the changed bytes). This protects against partial page writes during a crash. **Do not turn this off** unless your file system guarantees atomic 8KB writes (ZFS does, ext4/XFS do not).

### Temp Files

When work_mem is too small, PostgreSQL spills sort and hash operations to disk as temp files.

```sql
-- Log temp file creation above 10MB:
ALTER SYSTEM SET log_temp_files = '10MB';
```

Monitor temp file usage:

```sql
SELECT datname, temp_files, temp_bytes,
       pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE temp_bytes > 0;
```

If temp_bytes is consistently high, increase work_mem.

### Benchmarking Storage with fio

Before blaming PostgreSQL, know what your disk can do:

```bash
# Random 4K read IOPS (simulates index lookups):
fio --name=randread --ioengine=libaio --direct=1 --bs=4k --size=1G \
    --numjobs=4 --runtime=30 --rw=randread --group_reporting

# Sequential write throughput (simulates WAL writes):
fio --name=seqwrite --ioengine=libaio --direct=1 --bs=8k --size=1G \
    --numjobs=1 --runtime=30 --rw=write --group_reporting
```

Minimum targets for PostgreSQL:
- Random 4K reads: > 10,000 IOPS (SSD), > 200 IOPS (spinning)
- Sequential writes: > 200 MB/s (SSD), > 50 MB/s (spinning)

---

## 5. Connection Management

### The Cost Per Connection

PostgreSQL forks a new OS process for each connection. Each backend uses:
- ~5-10 MB of private memory
- Kernel resources (file descriptors, scheduling overhead)
- Lock table entries
- Proc array slots (scanned on every snapshot)

At 500 connections, that is 2.5-5 GB just for connection overhead - before any queries run. Worse, PostgreSQL performance **degrades** with too many active connections due to lock contention and proc array scanning.

**Rule of thumb:** `max_connections` should be 2-4x your CPU core count for OLTP workloads.

```sql
-- On a 16-core server:
ALTER SYSTEM SET max_connections = 50;  -- let PgBouncer handle the rest
```

### PgBouncer

PgBouncer sits between applications and PostgreSQL, maintaining a small pool of real connections:

```
Application (2000 connections)
       |
   PgBouncer (pool_size = 30)
       |
   PostgreSQL (30 backend processes)
```

**Pool modes:**

| Mode | Connection returned when | Use case | Restrictions |
|------|--------------------------|----------|--------------|
| **session** | Client disconnects | Legacy apps, LISTEN/NOTIFY | Least efficient |
| **transaction** | Transaction ends (COMMIT/ROLLBACK) | Web apps (most common) | No SET, no prepared statements, no LISTEN |
| **statement** | Each statement completes | Simple read-heavy apps | No multi-statement transactions |

**Transaction mode** is standard for web applications. It provides the best connection reuse.

### idle_in_transaction_session_timeout

A connection that starts a transaction but never commits holds locks and prevents VACUUM from cleaning dead tuples.

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
```

This kills sessions that sit idle inside a transaction for more than 30 seconds. Prevents one stuck application from degrading the entire database.

### Connection Storms

When an application deploys or recovers from an outage, hundreds of connections hit PostgreSQL simultaneously. Each triggers a fork(), TLS handshake, and authentication query.

**Symptoms:** load average spikes, `top` shows many short-lived postgres processes, application logs show connection timeouts.

**Solutions:**
1. PgBouncer absorbs the storm
2. Connection retry with exponential backoff in the application
3. `pre_auth_delay` (testing only) to throttle connection rate

---

## 6. The Query Planner and Statistics

### How the Planner Works

PostgreSQL uses a **cost-based optimizer**. For every query, it generates multiple possible execution plans (different scan types, join orders, join methods), estimates the cost of each, and picks the cheapest.

The planner's cost estimates depend entirely on **statistics** - without accurate statistics, it picks wrong plans.

### Cost Model Parameters

| Parameter | Default | Meaning | SSD setting |
|-----------|---------|---------|-------------|
| seq_page_cost | 1.0 | Cost of one sequential page read | 1.0 |
| random_page_cost | 4.0 | Cost of one random page read | 1.1 - 1.5 |
| cpu_tuple_cost | 0.01 | Cost of processing one row | 0.01 |
| cpu_index_tuple_cost | 0.005 | Cost of processing one index entry | 0.005 |
| effective_cache_size | 4GB | Planner's estimate of total cache | 75% of RAM |

The ratio of `random_page_cost` to `seq_page_cost` drives most scan decisions. On SSDs, random reads are nearly as fast as sequential:

```sql
ALTER SYSTEM SET random_page_cost = 1.1;  -- SSD/NVMe
-- Leave at 4.0 for spinning disks
```

This makes the planner more willing to choose index scans over sequential scans.

### What the Planner Reads

**pg_class** - row count and page count per table:

```sql
SELECT relname, reltuples::bigint AS estimated_rows, relpages
FROM pg_class WHERE relname = 'orders';
```

```
 relname | estimated_rows | relpages
---------+----------------+----------
 orders  |         500000 |     6250
```

**pg_statistic** - column-level distribution data (most common values, histograms, null fractions, distinct value counts). Queried via the friendlier view:

```sql
SELECT attname, n_distinct, most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'orders' AND attname = 'status';
```

### ANALYZE

`ANALYZE` reads a sample of rows from the table and updates `pg_statistic`. It is the **only way** to refresh column statistics. VACUUM does NOT update statistics.

```sql
ANALYZE VERBOSE orders;
```

Expected output (yours will differ):

```
INFO:  analyzing "public.orders"
INFO:  "orders": scanned 6250 of 6250 pages, containing 500000 live rows and 0 dead rows;
       30000 rows in sample, 500000 estimated total rows
```

**When autovacuum triggers ANALYZE:**

Autovacuum runs auto-analyze when changed rows exceed:
`autovacuum_analyze_threshold + autovacuum_analyze_scale_factor * reltuples`

Defaults: threshold = 50, scale_factor = 0.1. So for a 100,000-row table, auto-analyze fires after 10,050 row changes.

Check when ANALYZE last ran:

```sql
SELECT relname, n_live_tup, n_mod_since_analyze, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_mod_since_analyze DESC;
```

### default_statistics_target

Controls how many rows ANALYZE samples per column. Default is 100 (samples 300 x 100 = 30,000 rows). For columns with many distinct values used in complex queries, raise it:

```sql
ALTER TABLE orders ALTER COLUMN customer_id SET STATISTICS 500;
ANALYZE orders;
```

Higher values = better estimates for skewed distributions, but ANALYZE takes longer and plans take slightly longer to generate.

### Extended Statistics

When two columns are correlated, the planner assumes independence and underestimates result sizes. Example: `city` and `zip_code` are correlated, but the planner doesn't know that.

```sql
CREATE STATISTICS orders_city_zip (dependencies, ndistinct, mcv)
ON city, zip_code FROM orders;

ANALYZE orders;
```

Now the planner knows these columns are correlated and produces better row estimates for queries filtering on both.

### Stale Statistics - The #1 Cause of Sudden Degradation

From a real production incident: a bulk data deletion job removed 90% of rows but did not run ANALYZE afterward. The planner thought a 60MB table had 2 rows. Every query across all application modules ran with catastrophically wrong execution plans - sequential scans everywhere, wrong join strategies, and no parallel execution.

**Diagnosis:**

```sql
SELECT relname, reltuples::bigint AS planner_estimate,
       pg_size_pretty(pg_relation_size(oid)) AS actual_size
FROM pg_class
WHERE relname = 'support_tickets';
```

```
     relname       | planner_estimate | actual_size
-------------------+------------------+-------------
 support_tickets   |                2 | 60 MB
```

**Fix:** `ANALYZE VERBOSE support_tickets;`

**Prevention:** After any bulk DELETE, INSERT, or UPDATE affecting > 10% of a table, always run ANALYZE.

See **SURVIVE Scenario 11** for hands-on practice with this exact incident.

---

## 7. EXPLAIN Deep Dive

### EXPLAIN Options

```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, WAL) SELECT ...;
```

| Option | What it adds | Caution |
|--------|-------------|---------|
| **ANALYZE** | Actual timing and row counts (runs the query) | Wrap destructive queries in BEGIN/ROLLBACK |
| **BUFFERS** | Buffer hit/read/dirty/write counts | Requires ANALYZE |
| **SETTINGS** | Non-default planner settings affecting the plan | Useful for debugging |
| **WAL** | WAL bytes generated | For INSERT/UPDATE/DELETE |
| **VERBOSE** | Schema-qualified names, output columns | |
| **FORMAT JSON** | Machine-parseable output | For tools like pgMustard, explain.depesz.com |

### Reading the Output

```
Index Scan using orders_pkey on orders  (cost=0.42..8.44 rows=1 width=64) (actual time=0.015..0.016 rows=1 loops=1)
                                         ^^^^        ^^^^      ^            ^^^^^^^^^^^^^^^^^^^      ^^^^
                                         |           |         |            |                        |
                                   startup cost  total cost  estimated   actual time range      actual rows
                                                              rows
```

- **startup cost** - cost before the first row is returned (high for sorts, zero for seq scans)
- **total cost** - cost to return all rows
- **rows** - estimated rows. Compare to actual rows. Large differences = stale statistics
- **loops** - how many times this node was executed (e.g., inner side of Nested Loop)
- **actual time** - real wall-clock time in milliseconds. Multiply by loops for total time.

### Scan Types

**Seq Scan** - reads every page in the table sequentially.

```
Seq Scan on orders  (cost=0.00..15000.00 rows=500000 width=64)
```

Not always bad. For queries returning > 5-10% of rows, a Seq Scan is often cheaper than an Index Scan because sequential disk reads are faster than random. Also optimal for small tables (< 1000 rows).

**Index Scan** - traverses a B-tree index to find matching rows, then fetches each row from the table heap (random I/O).

```
Index Scan using orders_customer_id_idx on orders  (cost=0.42..8.44 rows=12 width=64)
  Index Cond: (customer_id = 42)
```

Best for queries returning < 5% of rows.

**Index Only Scan** - reads all needed data from the index itself. Never touches the table heap. The fastest scan type.

```
Index Only Scan using orders_cust_status_idx on orders  (cost=0.42..4.44 rows=12 width=8)
  Index Cond: (customer_id = 42)
  Heap Fetches: 0
```

`Heap Fetches: 0` means the visibility map confirmed all matching rows are visible, so no heap access was needed. Requires a **covering index** that includes all columns the query needs.

**Bitmap Index Scan + Bitmap Heap Scan** - two-step process:
1. Scan the index, build a bitmap of matching page numbers
2. Read those pages in physical order (sequential I/O, not random)

```
Bitmap Heap Scan on orders  (cost=12.50..520.00 rows=500 width=64)
  Recheck Cond: (status = 'pending')
  ->  Bitmap Index Scan on orders_status_idx  (cost=0.00..12.37 rows=500 width=0)
        Index Cond: (status = 'pending')
```

Used when too many rows for an Index Scan (random I/O too expensive) but too few for a Seq Scan. Also used to combine multiple indexes with BitmapAnd / BitmapOr.

**TID Scan** - fetches a specific row by its physical location (ctid). Rarely seen in normal queries.

### Join Types

**Nested Loop** - for each row in the outer input, scan the inner input.

```
Nested Loop  (cost=0.42..125.00 rows=12 width=128)
  ->  Index Scan using customers_pkey on customers  (cost=0.42..8.44 rows=1 width=64)
  ->  Index Scan using orders_customer_id_idx on orders  (cost=0.42..8.50 rows=12 width=64)
```

Best when the outer side has few rows and the inner side has an index. Performance is O(outer_rows x inner_cost). Catastrophic when the outer side is large and the inner side has no index.

**Hash Join** - builds a hash table from one input, then probes it with the other.

```
Hash Join  (cost=100.00..850.00 rows=5000 width=128)
  Hash Cond: (orders.customer_id = customers.id)
  ->  Seq Scan on orders  (cost=0.00..600.00 rows=50000 width=64)
  ->  Hash  (cost=50.00..50.00 rows=2000 width=64)
        Buckets: 4096  Batches: 1  Memory Usage: 160kB
```

Best for joining larger tables. If `Batches > 1`, the hash table didn't fit in work_mem and spilled to disk - increase work_mem.

**Merge Join** - sorts both inputs, then merges them in order. Efficient when both inputs are already sorted (from indexes or prior Sort nodes).

```
Merge Join  (cost=0.85..1200.00 rows=5000 width=128)
  Merge Cond: (orders.customer_id = customers.id)
  ->  Index Scan using orders_customer_id_idx on orders
  ->  Index Scan using customers_pkey on customers
```

### Other Important Nodes

| Node | What it does | Watch for |
|------|-------------|-----------|
| **Sort** | Sorts input rows | `Sort Method: external merge Disk` = work_mem too low |
| **HashAggregate** | GROUP BY using hash table | Disk usage = work_mem too low |
| **GroupAggregate** | GROUP BY on pre-sorted input | Needs Sort or index providing order |
| **Materialize** | Caches subplan results for reuse | High loops count = may need rethinking |
| **Memoize** (PG14+) | Caches parameterized inner-loop results | Cache Hit/Miss ratio in EXPLAIN ANALYZE |
| **Incremental Sort** (PG13+) | Sorts partially-sorted input | Cheaper than full Sort when leading keys match |
| **Limit** | Stops after N rows | Can make nested loops viable for "top N" |

### Estimated vs Actual Rows

When estimated and actual rows differ by more than 10x, the planner is working with bad information:

```
Seq Scan on orders  (cost=0.00..1.03 rows=1 width=64) (actual time=0.015..850.000 rows=450000 loops=1)
```

Estimated 1 row, got 450,000. This means:
1. Statistics are stale - run `ANALYZE`
2. Column correlation isn't captured - use `CREATE STATISTICS`
3. The planner can't estimate the function/expression - consider a functional index

### Buffers Output

```
Bitmap Heap Scan on orders  (actual time=...)
  Buffers: shared hit=520 read=980 dirtied=12 written=3
           temp read=450 written=450
```

| Field | Meaning |
|-------|---------|
| **shared hit** | Pages found in shared_buffers (fast) |
| **shared read** | Pages read from disk or OS cache |
| **shared dirtied** | Pages modified (will need writing at checkpoint) |
| **shared written** | Pages written to disk during query (rare, means bgwriter is behind) |
| **temp read/written** | Temp file I/O (work_mem too small) |

**Cache hit ratio** for a query: `hit / (hit + read)`. Target > 99% for OLTP.

---

## 8. Indexing Strategy

### B-tree (Default)

Supports equality and range queries. Handles 90% of indexing needs.

```sql
CREATE INDEX ON orders (customer_id);
CREATE INDEX ON orders (created_at DESC);
```

Supports: `=`, `<`, `>`, `<=`, `>=`, `BETWEEN`, `IN`, `IS NULL`, `ORDER BY`, `MIN/MAX`

**Multi-column index column order matters:**

```sql
-- For queries filtering on status AND sorting by created_at:
CREATE INDEX ON orders (status, created_at DESC);

-- Column order: most selective first (fewest matching rows), then sort column
-- This index helps: WHERE status = 'pending' ORDER BY created_at DESC
-- This index does NOT help: WHERE created_at > '2024-01-01' (can't skip first column)
```

### Hash

Only supports equality (`=`). Slightly faster than B-tree for pure equality lookups on large values. Not WAL-logged before PG10.

```sql
CREATE INDEX ON sessions USING hash (session_token);
```

Rarely used - B-tree handles equality well and is more versatile.

### GIN (Generalized Inverted Index)

For multi-valued columns: arrays, JSONB, full-text search.

```sql
CREATE INDEX ON products USING gin (tags);                          -- array
CREATE INDEX ON documents USING gin (metadata);                     -- JSONB
CREATE INDEX ON articles USING gin (to_tsvector('english', body));  -- full-text
```

Supports: `@>`, `<@`, `?`, `?|`, `?&`, `@@` (full-text match)

GIN indexes are slower to update (each INSERT may modify many index entries) but very fast for lookups. Use `fastupdate = on` (default) to batch updates.

### GiST (Generalized Search Tree)

For geometric data, ranges, and nearest-neighbor queries.

```sql
CREATE INDEX ON events USING gist (duration);           -- range type
CREATE INDEX ON locations USING gist (coordinates);     -- PostGIS geometry
```

Supports: `&&` (overlap), `@>` (containment), `<->` (nearest-neighbor)

### BRIN (Block Range Index)

Stores min/max values per block range. Tiny footprint (1000x smaller than B-tree) but only effective when data is physically ordered.

```sql
CREATE INDEX ON sensor_data USING brin (recorded_at);
```

Best for: append-only tables with timestamp columns where new rows always have higher timestamps. Useless if data is randomly ordered.

### Covering Indexes (INCLUDE)

Include non-searchable columns in the index to enable Index Only Scans:

```sql
-- Query needs customer_id for filtering, but also returns status and total:
SELECT customer_id, status, total FROM orders WHERE customer_id = 42;

-- Covering index:
CREATE INDEX ON orders (customer_id) INCLUDE (status, total);
```

INCLUDE columns are stored in leaf pages only (not in the tree structure), so they can't be used for filtering - only for avoiding heap fetches.

### Partial Indexes

Index only the rows you actually query:

```sql
-- Only 3% of orders are 'pending', but you query them constantly:
CREATE INDEX ON orders (created_at) WHERE status = 'pending';
```

The index is much smaller (3% of full size), faster to update, and faster to scan. Your query must include the WHERE clause for the planner to use it:

```sql
SELECT * FROM orders WHERE status = 'pending' AND created_at > now() - interval '1 hour';
-- Uses the partial index
```

### Expression Indexes

Index a computed expression:

```sql
CREATE INDEX ON users (lower(email));

-- Now this uses the index:
SELECT * FROM users WHERE lower(email) = 'alice@example.com';
```

The query must use the **exact same expression** as the index definition.

### Unused Index Detection

Indexes that are never scanned still cost write performance (updated on every INSERT/UPDATE/DELETE):

```sql
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND pg_relation_size(indexrelid) > 1024 * 1024  -- > 1MB
ORDER BY pg_relation_size(indexrelid) DESC;
```

If `idx_scan = 0` after weeks of production traffic, the index is likely dead weight. Verify it's not used for uniqueness constraints before dropping.

### Index Bloat

Indexes accumulate dead entries from UPDATE/DELETE operations. VACUUM removes dead heap tuples but index cleanup can lag behind.

Detect bloat:

```sql
-- Install pgstattuple extension:
CREATE EXTENSION IF NOT EXISTS pgstattuple;

SELECT * FROM pgstattuple('orders_pkey');
-- Look at dead_tuple_percent
```

**Remediation:**
- **REINDEX CONCURRENTLY** (PG12+) - rebuilds without locking reads/writes
- **pg_repack** - external tool, no locks, works on tables and indexes
- **VACUUM FULL** - rewrites the entire table, takes an ACCESS EXCLUSIVE lock (blocks everything) - last resort

```sql
REINDEX INDEX CONCURRENTLY orders_pkey;
```

### When NOT to Add an Index

Every index has costs:
- Disk space (can be substantial for large tables)
- Write overhead: every INSERT updates every index, every UPDATE on indexed columns updates those indexes
- VACUUM overhead: more indexes = more work per vacuum cycle
- Planner time: more indexes to evaluate

Don't add an index for:
- Small tables (< 1000 rows) - Seq Scan is faster
- Low-selectivity columns (e.g., boolean with 50/50 distribution) - index won't help
- Write-heavy tables where read performance isn't critical
- Columns never used in WHERE, JOIN, or ORDER BY

---

## 9. Autovacuum Tuning for Performance

### What Autovacuum Does

Autovacuum performs two critical functions:
1. **VACUUM** - reclaims space from dead tuples (rows deleted or replaced by UPDATE)
2. **ANALYZE** - refreshes planner statistics from sampled data

Both are essential for performance. Without VACUUM, tables bloat. Without ANALYZE, the planner picks wrong plans.

### When Autovacuum Triggers

**Vacuum triggers** when dead tuples exceed:
`autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * reltuples`

**Analyze triggers** when changed rows exceed:
`autovacuum_analyze_threshold + autovacuum_analyze_scale_factor * reltuples`

Defaults: threshold = 50, vacuum_scale_factor = 0.2, analyze_scale_factor = 0.1

For a 10,000,000-row table with defaults, vacuum triggers after 2,000,050 dead tuples (20% of the table). That is a lot of bloat before cleanup starts.

### Per-Table Tuning for High-Churn Tables

```sql
ALTER TABLE orders SET (
  autovacuum_vacuum_scale_factor = 0.01,       -- trigger at 1% dead tuples instead of 20%
  autovacuum_vacuum_threshold = 1000,           -- or 1000 dead tuples, whichever is more
  autovacuum_analyze_scale_factor = 0.005,      -- re-analyze at 0.5% changes
  autovacuum_analyze_threshold = 500
);
```

For the 10M-row table, vacuum now triggers at 101,000 dead tuples instead of 2,000,050.

### Cost-Based Vacuum Delay

Autovacuum throttles itself to avoid overwhelming disk I/O:

```sql
-- Global settings:
ALTER SYSTEM SET autovacuum_vacuum_cost_delay = '2ms';    -- pause between chunks (default 2ms, was 20ms pre-PG12)
ALTER SYSTEM SET autovacuum_vacuum_cost_limit = 800;       -- work units before pausing (default 200)
```

Higher `cost_limit` = vacuum runs faster but uses more I/O. On fast NVMe storage, you can safely raise this to 800-2000.

For a specific critical table that needs aggressive vacuuming:

```sql
ALTER TABLE hot_table SET (
  autovacuum_vacuum_cost_delay = '0ms',    -- no throttling
  autovacuum_vacuum_cost_limit = 2000
);
```

### autovacuum_max_workers

Default is 3 workers. On a server with many tables and high churn, increase:

```sql
ALTER SYSTEM SET autovacuum_max_workers = 6;  -- requires restart
```

Each worker can only vacuum one table at a time. If you have 50 high-churn tables and 3 workers, tables queue up. More workers = less queue, but each worker shares the global `autovacuum_vacuum_cost_limit`, so individual workers slow down.

### Monitoring Autovacuum

```sql
SELECT relname, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric / GREATEST(n_live_tup, 1) * 100, 1) AS dead_pct,
       last_autovacuum, last_autoanalyze,
       autovacuum_count, autoanalyze_count
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

**Red flags:**
- `dead_pct` > 20% - vacuum is not keeping up
- `last_autovacuum` is NULL or very old - vacuum never ran or hasn't run recently
- `n_dead_tup` growing over time - vacuum is slower than the rate of dead tuple creation

### Table Bloat

Even after VACUUM, space from dead tuples is not returned to the OS - it's reused by future inserts. If a table had a one-time bulk delete, the file stays large.

**Detect bloat with pgstattuple:**

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;

SELECT
  pg_size_pretty(table_len) AS total_size,
  pg_size_pretty(dead_tuple_len) AS dead_space,
  round(dead_tuple_percent::numeric, 1) AS dead_pct
FROM pgstattuple('orders');
```

**Remediation options:**

| Method | Locks | Downtime | Use when |
|--------|-------|----------|----------|
| **VACUUM** | No exclusive lock | None | Normal maintenance, dead space will be reused |
| **REINDEX CONCURRENTLY** | No exclusive lock | None | Index-only bloat |
| **pg_repack** | No exclusive lock | None | Table + index bloat, production-safe |
| **VACUUM FULL** | ACCESS EXCLUSIVE | Full table lock | Last resort, small tables, or maintenance windows |

```bash
# pg_repack - no locks, rewrites table in the background:
pg_repack -d mydb -t orders
```

---

## 10. pg_stat Views - Your Production Dashboard

### pg_stat_activity

The first thing to check when something is slow - what is running right now?

```sql
SELECT pid, state, wait_event_type, wait_event,
       now() - query_start AS duration,
       left(query, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY duration DESC;
```

Expected output (yours will differ):

```
  pid  |  state  | wait_event_type | wait_event |  duration   |                     query
-------+---------+-----------------+------------+-------------+----------------------------------------------
 14523 | active  | Lock            | relation   | 00:05:12.34 | UPDATE orders SET status = 'shipped' WHERE...
 14601 | active  | IO              | DataFileRead| 00:00:45.12 | SELECT * FROM large_report_view
 14589 | active  |                 |            | 00:00:02.34 | EXPLAIN ANALYZE SELECT...
```

**State values:** `active` (running), `idle` (waiting for command), `idle in transaction` (transaction open, doing nothing - dangerous), `fastpath function call`

### pg_stat_statements

**The single most important extension for performance tuning.** Tracks execution statistics for every normalized query.

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

**Top 10 queries by total execution time (where to focus tuning):**

```sql
SELECT left(query, 60) AS query,
       calls,
       round(total_exec_time::numeric, 1) AS total_ms,
       round(mean_exec_time::numeric, 1) AS mean_ms,
       round(stddev_exec_time::numeric, 1) AS stddev_ms,
       rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

**Top queries by mean time (slowest individual queries):**

```sql
SELECT left(query, 60) AS query,
       calls,
       round(mean_exec_time::numeric, 1) AS mean_ms,
       rows / GREATEST(calls, 1) AS rows_per_call
FROM pg_stat_statements
WHERE calls > 100
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Reset after tuning to measure improvement:

```sql
SELECT pg_stat_statements_reset();
```

### pg_stat_user_tables

Table-level activity and health:

```sql
SELECT relname,
       seq_scan, idx_scan,
       round(idx_scan::numeric / GREATEST(seq_scan + idx_scan, 1) * 100, 1) AS idx_pct,
       n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE n_live_tup > 1000
ORDER BY seq_scan DESC;
```

**Red flags:**
- `idx_pct` < 95% on a large table = missing indexes, too many seq scans
- `n_dead_tup` > 10% of `n_live_tup` = vacuum is not keeping up
- `last_autoanalyze` is NULL = statistics have never been collected

### pg_stat_user_indexes

Find unused indexes (costing write performance for no benefit):

```sql
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND pg_relation_size(indexrelid) > 1048576
ORDER BY pg_relation_size(indexrelid) DESC;
```

### pg_statio_user_tables

Cache hit ratio per table:

```sql
SELECT relname,
       heap_blks_hit, heap_blks_read,
       round(heap_blks_hit::numeric / GREATEST(heap_blks_hit + heap_blks_read, 1) * 100, 1) AS hit_pct
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 1000
ORDER BY hit_pct ASC;
```

Target: > 99% for OLTP tables. Tables with < 90% hit ratio are not fitting in cache - consider increasing shared_buffers or optimizing queries to touch fewer pages.

### pg_stat_bgwriter

Checkpoint and background writer health:

```sql
SELECT checkpoints_timed, checkpoints_req,
       round(checkpoints_req::numeric / GREATEST(checkpoints_timed + checkpoints_req, 1) * 100, 1) AS req_pct,
       buffers_checkpoint, buffers_clean, buffers_backend,
       pg_size_pretty(buffers_checkpoint * 8192::bigint) AS checkpoint_written
FROM pg_stat_bgwriter;
```

**Red flags:**
- `req_pct` > 10% - checkpoints are being triggered by WAL volume (max_wal_size too low), not by time
- `buffers_backend` is high relative to `buffers_checkpoint` + `buffers_clean` - backends are writing dirty pages themselves because bgwriter and checkpointer can't keep up

### pg_stat_wal (PG14+)

WAL generation rate:

```sql
SELECT wal_records, wal_fpi, wal_bytes,
       pg_size_pretty(wal_bytes) AS wal_generated,
       stats_reset
FROM pg_stat_wal;
```

High `wal_fpi` (full page images) relative to `wal_records` means full_page_writes is generating large WAL. Consider `wal_compression`.

---

## 11. Wait Events and Lock Contention

### Wait Event Categories

When a query is slow but CPU and disk look fine, check what it's waiting on:

```sql
SELECT pid, wait_event_type, wait_event, state,
       now() - query_start AS duration,
       left(query, 60) AS query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
  AND state = 'active';
```

| wait_event_type | Meaning | Common causes |
|-----------------|---------|---------------|
| **Lock** | Waiting for a heavyweight lock | Another transaction holds the lock |
| **LWLock** | Waiting for a lightweight (internal) lock | Shared buffer contention, WAL insert |
| **IO** | Waiting for disk I/O | Slow disk, missing from cache |
| **BufferPin** | Waiting for a buffer pin | Concurrent access to same page |
| **Client** | Waiting for client to send data | Slow application, network latency |
| **Activity** | Idle background process | Normal for bgwriter, autovacuum launcher |

### Common Wait Events

| Wait Event | Type | Meaning | Action |
|------------|------|---------|--------|
| **relation** | Lock | Waiting for table-level lock | Find the blocking query |
| **transactionid** | Lock | Waiting for another transaction to commit | Find the blocking transaction |
| **tuple** | Lock | Waiting for row-level lock | Row contention, consider advisory locks |
| **WALInsertLock** | LWLock | Contention writing WAL | Increase wal_buffers, reduce commit rate |
| **buffer_content** | LWLock | Contention on shared buffer page | Often hot-row contention |
| **DataFileRead** | IO | Reading data file from disk | Missing from cache, check shared_buffers |
| **WALSync** | IO | Flushing WAL to disk | Slow WAL disk, consider battery-backed write cache |

### pg_locks and Blocking Chains

Find who is blocking whom:

```sql
SELECT
  blocked.pid AS blocked_pid,
  blocked.query AS blocked_query,
  blocking.pid AS blocking_pid,
  blocking.query AS blocking_query,
  now() - blocked.query_start AS blocked_duration
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

Simpler version using pg_blocking_pids() (PG9.6+):

```sql
SELECT pid, pg_blocking_pids(pid) AS blocked_by,
       left(query, 60) AS query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

### Lock Types (Least to Most Restrictive)

| Lock Mode | Typical Operation | Conflicts with |
|-----------|-------------------|----------------|
| **AccessShareLock** | SELECT | AccessExclusive |
| **RowShareLock** | SELECT FOR UPDATE | Exclusive, AccessExclusive |
| **RowExclusiveLock** | INSERT, UPDATE, DELETE | Share, ShareRowExclusive, Exclusive, AccessExclusive |
| **ShareLock** | CREATE INDEX (non-CONCURRENTLY) | RowExclusive, ShareRowExclusive, Exclusive, AccessExclusive |
| **AccessExclusiveLock** | ALTER TABLE, DROP TABLE, VACUUM FULL | Everything |

### Deadlock Detection

```sql
ALTER SYSTEM SET log_lock_waits = on;        -- log when a query waits > deadlock_timeout
ALTER SYSTEM SET deadlock_timeout = '1s';     -- default, time before checking for deadlocks
```

PostgreSQL automatically detects and resolves deadlocks by aborting one of the transactions. Check the PostgreSQL log for `deadlock detected` messages.

### Advisory Locks

Application-level locks that don't lock any database object. Useful for coordinating application logic:

```sql
-- Acquire an advisory lock (blocks until available):
SELECT pg_advisory_lock(12345);

-- Try without blocking:
SELECT pg_try_advisory_lock(12345);

-- Release:
SELECT pg_advisory_unlock(12345);
```

Use case: ensuring only one instance of a batch job runs at a time.

---

## 12. Parallel Query

### How It Works

PostgreSQL splits large operations across multiple worker processes:

```
        Gather (or Gather Merge)
        /      |      \
   Worker  Worker  Worker    <-- each processes a portion of the table
        \      |      /
         Combined Results
```

### Key Parameters

```sql
max_parallel_workers_per_gather = 2     -- workers per query node (default 2)
max_parallel_workers = 8                -- total parallel workers across all queries
max_worker_processes = 8                -- total background workers (includes autovacuum)
min_parallel_table_scan_size = '8MB'    -- minimum table size for parallel scan
parallel_tuple_cost = 0.1               -- cost of passing tuple between processes
parallel_setup_cost = 1000              -- cost of launching workers
```

On a 16-core server with heavy analytical queries:

```sql
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET max_parallel_workers = 12;
ALTER SYSTEM SET max_worker_processes = 16;
```

### When Parallel Helps

- Large sequential scans (table > min_parallel_table_scan_size)
- Aggregates over big tables (COUNT, SUM, AVG)
- Hash joins with large inputs
- B-tree index creation (CREATE INDEX)
- VACUUM (PG13+)

### When Parallel Doesn't Help

- Small tables (below min_parallel_table_scan_size)
- Index lookups returning few rows
- Queries waiting on locks or slow I/O
- Functions marked `PARALLEL UNSAFE`
- Already at max_parallel_workers limit

### Checking Parallel Execution

```sql
EXPLAIN ANALYZE SELECT count(*) FROM big_table;
```

```
Finalize Aggregate  (actual time=150.00..150.01 rows=1)
  ->  Gather  (actual time=50.00..149.95 rows=3)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial Aggregate  (actual time=45.00..45.01 rows=1)
              ->  Parallel Seq Scan on big_table  (actual time=0.01..30.00 rows=333333)
```

If `Workers Launched < Workers Planned`, you've hit the global `max_parallel_workers` limit.

---

## 13. Query Optimization Patterns

### CTEs: Materialized vs Inlined

Before PG12, CTEs were optimization fences. Since PG12, CTEs are inlined by default:

```sql
-- PG12+: both are equivalent in performance
WITH pending AS (SELECT * FROM orders WHERE status = 'pending')
SELECT * FROM pending WHERE created_at > now() - interval '1 day';

SELECT * FROM orders WHERE status = 'pending' AND created_at > now() - interval '1 day';
```

Force materialization when you want the CTE executed exactly once:

```sql
WITH pending AS MATERIALIZED (SELECT * FROM orders WHERE status = 'pending')
SELECT * FROM pending WHERE created_at > '2024-01-01';
```

### EXISTS vs IN vs JOIN

For "find rows with matching rows in another table":

```sql
-- EXISTS (usually fastest - stops at first match):
SELECT * FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- IN (equivalent to EXISTS in modern PostgreSQL):
SELECT * FROM customers WHERE id IN (SELECT customer_id FROM orders);

-- JOIN (can return duplicates if orders has multiple rows per customer):
SELECT DISTINCT c.* FROM customers c JOIN orders o ON o.customer_id = c.id;
```

For "find rows WITHOUT matching rows", use `NOT EXISTS` (not `NOT IN` - which handles NULLs incorrectly and can't use anti-join optimization):

```sql
-- Good:
SELECT * FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- Bad (fails if orders.customer_id has any NULL):
SELECT * FROM customers WHERE id NOT IN (SELECT customer_id FROM orders);
```

### Pagination: Keyset vs OFFSET

**OFFSET is slow for deep pages** because PostgreSQL must scan and discard all skipped rows:

```sql
-- Page 1000 of 50 results: scans 50,000 rows, discards 49,950
SELECT * FROM orders ORDER BY created_at DESC OFFSET 49950 LIMIT 50;
```

**Keyset pagination** uses a WHERE clause with the last seen value:

```sql
-- First page:
SELECT * FROM orders ORDER BY created_at DESC, order_id DESC LIMIT 50;

-- Next page (using last row's values):
SELECT * FROM orders
WHERE (created_at, order_id) < ('2024-06-15 10:30:00', 485923)
ORDER BY created_at DESC, order_id DESC
LIMIT 50;
```

Keyset is O(1) regardless of page depth, but requires a unique sort key and can't jump to arbitrary pages.

### Batch Operations

Large DELETE/UPDATE operations hold locks for the entire duration and generate massive WAL. Break them into chunks:

```sql
-- Bad: locks table for minutes, generates huge WAL
DELETE FROM events WHERE created_at < now() - interval '90 days';

-- Good: chunked delete, commits between batches
DO $$
DECLARE
  rows_deleted INTEGER;
BEGIN
  LOOP
    DELETE FROM events
    WHERE ctid IN (
      SELECT ctid FROM events
      WHERE created_at < now() - interval '90 days'
      LIMIT 10000
    );
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;
    EXIT WHEN rows_deleted = 0;
    COMMIT;
    PERFORM pg_sleep(0.1);  -- brief pause to let other queries through
  END LOOP;
END $$;
```

---

## 14. Benchmarking with pgbench

### Initialize

```bash
pgbench -i -s 100 mydb
# -s 100 = scale factor 100 = 10,000,000 rows in pgbench_accounts
```

### Run a Benchmark

```bash
# 10 clients, 4 threads, 60 seconds:
pgbench -c 10 -j 4 -T 60 mydb
```

Expected output (yours will differ):

```
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 100
query mode: simple
number of clients: 10
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 48523
number of failed transactions: 0
latency average = 12.37 ms
latency stddev = 8.24 ms
initial connection time = 52.34 ms
tps = 808.71 (without initial connection time)
```

**Key metrics:**
- **tps** - transactions per second. Higher is better. Compare before/after tuning changes.
- **latency average** - mean time per transaction. Lower is better.
- **latency stddev** - consistency. High stddev = spiky performance.

### Read-Only Benchmark

```bash
pgbench -c 10 -j 4 -T 60 -S mydb
# -S = select-only (no writes)
```

### Custom Scripts

```bash
cat > /tmp/custom_bench.sql << 'EOF'
\set customer_id random(1, 100000)
SELECT * FROM orders WHERE customer_id = :customer_id;
EOF

pgbench -c 10 -j 4 -T 60 -f /tmp/custom_bench.sql mydb
```

---

## 15. Real-World Diagnostic Workflow

When someone says "the database is slow," follow this path:

```
Step 1: OS Check
  |
  +-- Load average > 2x CPU count? --> CPU bound
  |     +-- top: high %us? --> query optimization (Step 5)
  |     +-- top: high %wa? --> disk I/O (Step 3)
  |     +-- top: high %sy? --> too many connections (Step 2)
  |
  +-- Swap in use? --> Emergency: vm.swappiness, shared_buffers sizing
  |
  +-- iostat %util > 80%? --> Disk bottleneck
        +-- Which process? (iotop) --> vacuum? checkpoint? query?

Step 2: Connection Check
  |
  +-- How many connections? (pg_stat_activity)
  |     +-- > 200 active? --> Need PgBouncer
  |     +-- Many "idle in transaction"? --> idle_in_transaction_session_timeout
  |
  +-- Connection storms? --> PgBouncer, retry backoff

Step 3: Active Queries
  |
  +-- What's running? (pg_stat_activity WHERE state = 'active')
  |     +-- Long-running queries? --> Check EXPLAIN
  |     +-- Many identical queries? --> Missing index or bad plan
  |
  +-- What are they waiting on? (wait_event_type)
        +-- Lock? --> Find blocker (pg_blocking_pids)
        +-- IO? --> Disk or cache miss
        +-- LWLock? --> Internal contention

Step 4: Statistics Check
  |
  +-- pg_stat_user_tables: last_analyze NULL? --> ANALYZE
  +-- pg_class: reltuples wildly wrong? --> ANALYZE
  +-- High n_dead_tup? --> Vacuum falling behind

Step 5: EXPLAIN the Slow Query
  |
  +-- EXPLAIN (ANALYZE, BUFFERS)
  +-- Estimated vs actual rows off? --> Stale stats (ANALYZE)
  +-- Seq Scan on large table? --> Missing index
  +-- Sort: external merge Disk? --> Raise work_mem
  +-- Hash Batches > 1? --> Raise work_mem
  +-- Nested Loop on large outer? --> Wrong join, check statistics
  +-- Low buffer hit ratio? --> shared_buffers or query touching too many pages

Step 6: Fix and Verify
  |
  +-- ANALYZE, add index, tune parameter
  +-- Re-run EXPLAIN (ANALYZE, BUFFERS)
  +-- Compare before/after
  +-- Monitor pg_stat_statements for improvement
```

### SURVIVE Scenarios for Practice

Each of these Module 12 SURVIVE scenarios practices a specific diagnostic step:

| Scenario | What You Practice |
|----------|-------------------|
| 01 - shared_buffers too low | Memory tuning, buffer hit ratio |
| 02 - missing index | EXPLAIN analysis, index creation |
| 03 - work_mem too low | Detecting disk spills, per-session tuning |
| 04 - seq scan on large table | Index strategy, partial indexes |
| 05 - index corruption | REINDEX, data integrity checks |
| 06 - plan cache bloat | Prepared statement management |
| 07 - checkpoint too frequent | WAL tuning, pg_stat_bgwriter |
| 08 - effective_cache_size wrong | Planner hints, cost model |
| 09 - random_page_cost wrong | SSD tuning, scan type selection |
| 10 - parallel workers disabled | Parallel query configuration |
| 11 - stale stats after bulk delete | Statistics, ANALYZE, real-world incident |

---

## Key Takeaways

1. **Start at the OS** - check load average, swap, disk I/O before opening psql
2. **vm.swappiness = 1**, disable THP, enable huge pages, use XFS with noatime
3. **shared_buffers = 25% of RAM**, effective_cache_size = 75%, random_page_cost = 1.1 for SSD
4. **work_mem** is per-operation, not per-connection - set conservative global default, raise per-session
5. **ANALYZE is the fix** for sudden performance degradation after bulk operations
6. **pg_stat_statements** is your single best tool for finding which queries to optimize
7. **EXPLAIN (ANALYZE, BUFFERS)** shows what actually happened, not just what the planner guessed
8. **PgBouncer in transaction mode** is standard for web applications - keep max_connections low
9. **Autovacuum per-table tuning** is essential for high-churn tables - don't rely on global defaults
10. **Check wait events** before assuming CPU or disk - the query might just be waiting for a lock
