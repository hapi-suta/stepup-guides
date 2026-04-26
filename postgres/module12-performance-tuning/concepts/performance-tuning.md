# PostgreSQL Performance Tuning - Concepts Guide

This guide is for you - read it before starting the BUILD guides. It explains the WHY behind every tool, every setting, and every decision a production DBA makes when something is slow. Think of this as the conversation where I give you the mental model first, so that when you get hands-on in the labs, you already understand what you're doing and why.

---

## Table of Contents

1. [The Diagnostic Mindset - How DBAs Think](#1-the-diagnostic-mindset---how-dbas-think)
2. [OS-Level Diagnostics - Your First Line of Defense](#2-os-level-diagnostics---your-first-line-of-defense)
3. [OS Kernel Tuning - Making Linux Work With PostgreSQL](#3-os-kernel-tuning---making-linux-work-with-postgresql)
4. [PostgreSQL Memory Architecture - Where Your Data Lives](#4-postgresql-memory-architecture---where-your-data-lives)
5. [Storage and I/O - The Slowest Link in the Chain](#5-storage-and-io---the-slowest-link-in-the-chain)
6. [Connection Management - Less is More](#6-connection-management---less-is-more)
7. [The Query Planner and EXPLAIN - Reading PostgreSQL's Mind](#7-the-query-planner-and-explain---reading-postgresqls-mind)
8. [Indexing Strategy - The Right Tool for the Right Job](#8-indexing-strategy---the-right-tool-for-the-right-job)
9. [Autovacuum - The Cleanup Crew You Can't Ignore](#9-autovacuum---the-cleanup-crew-you-cant-ignore)
10. [Monitoring Views, Wait Events, and Parallel Query](#10-monitoring-views-wait-events-and-parallel-query)
11. [Real-World Diagnostic Workflow](#11-real-world-diagnostic-workflow)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. The Diagnostic Mindset - How DBAs Think

When someone runs up to you and says "the database is slow," your instinct might be to open `psql` and start looking at queries. That instinct is wrong.

A production DBA triages from the **outside in**: operating system first, then database configuration, then the specific query. Why? Because the database runs on a machine, and if the machine is sick, no amount of query tuning will help. A perfectly indexed query still runs slowly if the disk is saturated or the server is swapping.

Think of it like a doctor. You don't start with surgery - you start with vital signs. Is the patient breathing? What's the heart rate? Same thing here:

```
Server vitals (OS)  →  Database config  →  Specific query
    top, vmstat          shared_buffers       EXPLAIN ANALYZE
    iostat, sar          work_mem             indexes
    swap, disk           connections          statistics
```

This is the order this concepts guide follows, and it maps directly to the BUILD guides you're about to do. Section 2 maps to Build Guide 06 (OS Diagnostics). Section 3 maps to Build Guide 07 (OS Kernel Tuning). And so on. By the time you start the labs, you'll already know what each tool does and why you're using it.

> **Concept:** Performance tuning is not about memorizing settings. It is about learning a diagnostic method - a repeatable process you follow every time. The settings change between servers, but the process stays the same. Master the process and you can tune any PostgreSQL server you encounter.

---

## 2. OS-Level Diagnostics - Your First Line of Defense

Before you open `psql`, you need to check the machine. You'll get hands-on with all these tools in Build Guide 06 (OS Diagnostics). Here's what each one does and what the numbers mean.

### top - Your Server's Dashboard

**What is it?** `top` is a built-in Linux utility that gives you a live, real-time dashboard of your server. Think of it like the instrument panel in a car - at a glance, you can see CPU usage, memory usage, swap usage, and which processes are consuming the most resources.

When you run `top -bn1 | head -15` (which you'll do in Build Guide 06), here's what you're looking at:

```
top - 14:32:01 up 45 days,  3:12,  2 users,  load average: 12.50, 8.30, 4.10
Tasks: 312 total,   5 running, 307 sleeping,   0 stopped,   0 zombie
%Cpu(s): 45.2 us, 12.1 sy,  0.0 ni, 28.4 id,  13.8 wa,  0.0 hi,  0.5 si,  0.0 st
MiB Mem :  64000.0 total,   2100.0 free,  48000.0 used,  13900.0 buff/cache
MiB Swap:   8192.0 total,   6500.0 free,   1692.0 used.  14800.0 avail Mem
```

**Load Average** - those three numbers (`12.50, 8.30, 4.10`) are the average number of processes waiting for CPU over the last 1, 5, and 15 minutes. Here's how to read them:

Compare the numbers to your CPU count. If you have 16 cores:
- Load 16.0 = every core is busy, 100% utilized
- Load 12.5 = 78% utilized, getting warm
- Load 32.0 = 200% - processes are queuing up, waiting for a turn on the CPU
- If the numbers are trending up (4 -> 8 -> 12), the problem is getting worse right now

On your lab server, you have 2 vCPUs, so a load average of 2.0 means you're maxed out.

**CPU Breakdown** - this is the `%Cpu(s)` line:

| Field | What it means | What to worry about |
|-------|---------------|---------------------|
| **us** (user) | Time running your code and queries | High us = CPU-bound queries, probably missing indexes |
| **sy** (system) | Time the kernel spends doing OS work | High sy = too many connections, excessive context switching |
| **wa** (iowait) | Time the CPU sits idle waiting for the disk | High wa = your disk is the bottleneck, go check iostat |
| **id** (idle) | CPU is doing nothing | Low id = server is fully loaded |
| **st** (steal) | Time stolen by the hypervisor on a VM | High st = "noisy neighbor" problem, need a bigger instance |

When you see high `wa`, that's your signal to look at disk I/O next with `iostat`. When you see high `us`, that's your signal to look at queries with `pg_stat_statements`. Every number points you to the next diagnostic step.

**Memory** - the fields that matter:

| Field | What it means |
|-------|---------------|
| **total** | Physical RAM installed |
| **free** | Completely unused memory (don't panic if this is low - Linux caches aggressively, that's normal) |
| **used** | Actively used by processes |
| **buff/cache** | Used by the OS for disk caching (Linux will give this back if a process needs it) |
| **avail Mem** | Memory available without swapping = free + reclaimable cache. **THIS is the number that matters** |

> **Concept:** On Linux, low "free" memory is normal and healthy. The OS uses unused RAM as disk cache (buff/cache), which makes everything faster. The number you should watch is "avail Mem" - that tells you how much memory is actually available. If avail Mem is low, you have a real problem. If free is low but buff/cache is high, you're fine.

**Swap** - if you see ANY swap usage on a PostgreSQL server, investigate immediately. PostgreSQL keeps frequently accessed data pages in shared_buffers (in RAM). If those pages get swapped to disk, a query that normally takes 5ms from RAM suddenly takes 5 seconds from the swap partition. Performance doesn't degrade gradually - it collapses.

### vmstat - Watching the Pattern Over Time

**What is it?** `vmstat` (Virtual Memory Statistics) is another built-in Linux tool, but instead of showing you a snapshot like `top`, it shows you a **stream of updates** at intervals you choose. When you run `vmstat 2 5`, you're saying "show me the stats every 2 seconds, 5 times."

This is powerful because it lets you watch the pattern. A single snapshot might catch the server during a quiet moment. Five snapshots over 10 seconds show you the trend.

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 3  0      0 2100000 120000 13800000  0    0   450  1200 8500 12000 45 12 28 14  0
 5  2      0 2050000 120000 13750000  0    0  2800  5600 9200 15000 52 15 18 14  0
12  8   1024 1900000 120000 13600000  4   12  8500 12000 11000 22000 65 20  2 12  0
```

The columns that matter most:

- **r** (run queue) - processes waiting for CPU. If this is consistently more than 2x your CPU count, your CPUs are saturated
- **b** (blocked) - processes stuck waiting for I/O. Any value above 0 means your disk can't keep up
- **si/so** (swap in/out) - these should ALWAYS be 0 on a PostgreSQL server. Any swap activity means something is wrong
- **bi/bo** (blocks in/out) - disk read/write throughput in blocks per second
- **cs** (context switches) - how often the CPU switches between processes. Values above 50,000 often mean too many connections or lock contention

Look at the third row in that example. The `r` jumped to 12, `b` jumped to 8, swap started (si=4, so=12), and disk I/O exploded (bi=8500). That's a server in trouble - CPU saturated, processes blocked on disk, and it's starting to swap. You'd see this pattern during a checkpoint storm or a massive sequential scan.

### iostat - Is Your Disk the Problem?

**What is it?** `iostat` is part of the `sysstat` package (which you'll install in Build Guide 06 with `dnf install sysstat`). While `top` tells you the CPU is waiting on I/O, `iostat` tells you exactly what the disk is doing - how many reads, how many writes, how long each operation takes, and whether the disk is overwhelmed.

When you run `iostat -xz 2 5`, the `-x` flag gives you extended statistics (the important ones), `-z` hides idle devices, and `2 5` means "every 2 seconds, 5 times."

```
Device   r/s     w/s   rkB/s    wkB/s  await  avgqu-sz  %util
nvme0n1  850.00  1200.00  54400  76800   1.20    2.45    72.00
```

Here's what each column tells you:

| Column | What it means | When to worry |
|--------|---------------|---------------|
| **r/s, w/s** | Read/write operations per second (IOPS) | Compare to your disk's rated IOPS |
| **await** | Average time each I/O operation takes (in milliseconds) | > 10ms on SSD means it's saturated |
| **avgqu-sz** | Average number of requests queued up | > 4 means requests are piling up |
| **%util** | Percentage of time the disk is busy | > 80% means you're approaching the limit |

What counts as "bad" depends on your disk type:
- **NVMe SSD**: await should be under 1ms, %util above 90% is concerning
- **Regular SSD**: await under 5ms, %util above 80% is concerning
- **Spinning disk (HDD)**: await under 10ms is acceptable, %util above 70% is concerning

> **Concept:** When you see high iowait in `top`, your next step is always `iostat`. Together they answer two questions: (1) Is the CPU waiting on the disk? (top tells you) and (2) Why is the disk slow? (iostat tells you). If await is high and %util is near 100%, your disk is the bottleneck. Either your queries are doing too much I/O (fix with indexes or more RAM for caching) or you need faster storage.

### sar - The Time Machine

**What is it?** `sar` (System Activity Reporter) is also part of the `sysstat` package. Unlike `top` and `vmstat` which show you what's happening NOW, `sar` records data continuously in the background and lets you look at the past. It's your time machine.

When the problem happened at 3 AM and you're investigating at 9 AM, `sar` is how you go back and see what the server was doing at 3 AM. It automatically saves data files in `/var/log/sa/` - one file per day.

```bash
# CPU history for today between 8 AM and noon:
sar -u -f /var/log/sa/sa25 -s 08:00:00 -e 12:00:00

# Memory history:
sar -r -f /var/log/sa/sa25 -s 08:00:00 -e 12:00:00

# Disk I/O history:
sar -d -f /var/log/sa/sa25 -s 08:00:00 -e 12:00:00
```

The flags are intuitive once you know them: `-u` for CPU (utilization), `-r` for RAM, `-d` for disk, `-b` for block I/O.

### iotop - Which Process is Killing the Disk?

**What is it?** `iotop` shows you disk I/O broken down by process - like `top` but for disk activity instead of CPU. When `iostat` tells you the disk is busy, `iotop` tells you WHO is making it busy.

When you run `sudo iotop -oP`, the `-o` flag means "only show processes doing I/O right now" and `-P` means "show processes, not threads."

If you see a PostgreSQL backend doing tons of I/O, that usually means one of two things:
- A query is doing full table scans because it's missing an index
- work_mem is too small and a sort operation is spilling to temp files on disk

### How These Tools Connect

Here's the diagnostic flow - each tool points you to the next one:

```
+-------------------+     high %wa      +-------------------+
|                   | ----------------> |                   |
|   top / vmstat    |                   |   iostat          |
|   "Is something   |     high %us      |   "Which disk     |
|    wrong?"        | --------+         |    is busy?"      |
+-------------------+         |         +--------+----------+
                              |                  |
                              v                  v
                    +-------------------+   +-------------------+
                    | pg_stat_statements|   |      iotop        |
                    | "Which query is   |   | "Which process is |
                    |  burning CPU?"    |   |  doing the I/O?"  |
                    +-------------------+   +-------------------+
```

You always start with `top` or `vmstat`. The CPU breakdown tells you where to look next. This is the method - learn the method and you can diagnose any performance problem.

---

## 3. OS Kernel Tuning - Making Linux Work With PostgreSQL

Linux ships with defaults designed for general-purpose workloads - web servers, desktops, containers, everything. PostgreSQL is not a general-purpose workload. It's a database that manages its own memory cache, writes massive amounts of data to disk, and absolutely cannot tolerate being swapped out.

In Build Guide 07, you'll change several kernel parameters on your lab server. Here's WHY each one matters.

### vm.swappiness - Keeping PostgreSQL in RAM

**What is it?** `vm.swappiness` is a kernel parameter that controls how aggressively Linux moves data from RAM to the swap partition on disk. The default value is 60, on a scale of 0-100. A value of 60 means the kernel is fairly willing to swap.

For PostgreSQL, you set this to 1.

**Why 1 and not 0?** You might think "if swapping is bad, just set it to 0 and never swap." But 0 doesn't mean "never swap." It means "only swap when you absolutely have to." The problem is that when the kernel finally HAS to swap with a value of 0, it's because memory is critically low - and at that point, it might trigger the OOM (Out Of Memory) killer, which randomly kills processes to free memory. If it kills the PostgreSQL postmaster process, your entire database crashes instantly.

A value of 1 means "avoid swapping as much as possible, but if memory gets tight, swap a little bit rather than killing processes." It's the safe minimum.

> **Concept:** The OOM killer is a Linux last resort - when memory runs out completely, the kernel picks a process and kills it dead. No graceful shutdown, no CHECKPOINT, just gone. On a database server, the OOM killer is your worst nightmare. Setting swappiness=1 (not 0) and overcommit_memory=2 are both strategies to prevent the OOM killer from ever being invoked.

### vm.dirty_ratio and vm.dirty_background_ratio - Controlling Write Bursts

**What are these?** When your application writes data, Linux doesn't immediately write it to disk. Instead, it marks those pages as "dirty" (modified but not yet on disk) and keeps them in RAM. Eventually, the kernel flushes dirty pages to disk. These two parameters control WHEN that flushing happens.

- **dirty_background_ratio = 3** means "start flushing in the background when 3% of RAM is dirty pages." The background flusher works quietly without blocking your application.
- **dirty_ratio = 10** means "if dirty pages reach 10% of RAM, BLOCK new writes until some pages are flushed." This is the emergency brake.

The defaults are higher (dirty_background_ratio=10, dirty_ratio=20), which lets dirty pages pile up and then causes a burst of writes all at once. For PostgreSQL, that burst competes with checkpoints (which are also flushing data to disk), creating I/O spikes.

Lower values = more frequent, smaller flushes = smoother I/O. Think of it like doing dishes - washing a few after every meal (low values) versus letting them pile up for a week and then spending three hours (high values).

### vm.overcommit_memory - Protecting Against the OOM Killer

**What is it?** By default, Linux lies to applications about memory. When a program asks for 2 GB of RAM, Linux says "sure, here you go" - even if only 500 MB is actually free. Linux bets that the program won't actually use all 2 GB. This is called "overcommit."

Usually this works fine. But on a database server, PostgreSQL DOES use the memory it requests (for shared_buffers and backend processes). If Linux overcommits too aggressively and runs out of physical RAM, the OOM killer comes out.

Setting `overcommit_memory = 2` tells the kernel: "Don't overcommit. Only promise memory you actually have." Combined with `overcommit_ratio = 80`, the kernel allows allocations up to 80% of RAM + 100% of swap. If an allocation would exceed that, it gets refused with an error instead of being allowed and then killed later.

This means PostgreSQL might fail to fork a new backend (you'll see a "could not fork new process" error), which is annoying but recoverable. Much better than the OOM killer destroying everything.

### Huge Pages - Reducing Memory Management Overhead

**What are they?** Your server's RAM is divided into pages. By default, Linux uses 4 KB pages. PostgreSQL's shared_buffers is a big block of shared memory - if you set it to 16 GB, that's 4,194,304 individual 4 KB pages. The CPU has a cache called the TLB (Translation Lookaside Buffer) that maps virtual addresses to physical addresses. With 4 million pages, the TLB can't hold all the mappings, so the CPU constantly has to look them up. This slows things down.

Huge pages are 2 MB each instead of 4 KB. That same 16 GB of shared_buffers becomes only 8,192 pages - the TLB can handle that easily. The result is measurably faster shared_buffers access.

In Build Guide 07, you'll calculate the number of huge pages from VmPeak and configure the kernel. Here's the math:
- Find VmPeak from `/proc/<PID>/status` (the peak virtual memory of the PostgreSQL postmaster)
- Divide by 2048 KB (the size of one huge page) and add 1
- Set `vm.nr_hugepages` to that value

Then in `postgresql.conf`, set `huge_pages = try` (use huge pages if available, fall back to regular pages if not) or `huge_pages = on` (fail to start if huge pages aren't available).

### Transparent Huge Pages (THP) - The One You Must Disable

**What is it?** THP is Linux's attempt to automatically use huge pages without you configuring anything. Sounds great, right? The problem is HOW it works. The kernel runs a background process called `khugepaged` that constantly tries to merge 4 KB pages into 2 MB huge pages. This causes:

- Random latency spikes when the kernel pauses your process to defragment memory
- Memory fragmentation as the kernel moves pages around
- Unpredictable performance that looks like your database randomly stutters

Every PostgreSQL tuning guide, the official PostgreSQL documentation, and every experienced DBA will tell you: **disable THP**. Use explicit huge pages (the previous section) instead, where YOU control the allocation.

You'll do this in Build Guide 07:
```bash
echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag
```

When you run `cat /sys/kernel/mm/transparent_hugepage/enabled`, the `[never]` in brackets shows the active setting:
```
always madvise [never]
```

### ulimits - Don't Let the OS Throttle PostgreSQL

**What are ulimits?** The Linux kernel sets limits on resources each user can consume - how many files they can open, how many processes they can create, etc. These are called "ulimits" (user limits). The defaults (1024 open files) are fine for regular users, but PostgreSQL opens a LOT of files:

- Every table has at least one file
- Every index has at least one file
- Each backend process has file descriptors for its connection
- WAL segments are open files

On a database with thousands of tables and hundreds of connections, you'll hit the 1024 limit fast. When PostgreSQL can't open a file, queries fail with "too many open files" errors.

In Build Guide 07, you'll set `nofile` (max open files) and `nproc` (max processes) to 65536 for the postgres user. That's enough headroom for even large production databases.

### File System and Mount Options

**XFS vs ext4** - both work, but XFS is preferred for PostgreSQL because:
- Better performance with large files (and PostgreSQL data files can be gigabytes)
- Better parallel I/O (important when multiple backends read different tables)
- Better WAL write performance

The mount options `noatime` and `nodiratime` (which you'll configure in Build Guide 07) disable access timestamp updates. By default, every time Linux READS a file, it WRITES the access time to the filesystem metadata. PostgreSQL reads data pages constantly. Writing a timestamp for every read is pure overhead with zero benefit. Disabling it removes thousands of unnecessary writes.

> **Concept:** Linux's default configuration assumes you're running a general-purpose workload. Almost every default is wrong for a database server. Kernel tuning isn't optional "nice to have" optimization - it's essential configuration. A production DBA who skips kernel tuning and jumps straight to query optimization is like a mechanic who tunes the engine but never checks the oil. You'll do all of this hands-on in Build Guide 07.

### NUMA - For Multi-Socket Servers

**What is it?** If your server has multiple CPU sockets (physical processor chips), each socket has its own directly-attached RAM. Accessing RAM attached to your own socket is fast ("local" memory). Accessing RAM attached to the other socket is slower ("remote" memory). This architecture is called NUMA (Non-Uniform Memory Access).

PostgreSQL's shared_buffers is a large block of shared memory accessed by ALL backends. If it ends up allocated on just one NUMA node, backends running on the other socket always access remote memory - slower.

The fix is to start PostgreSQL with `numactl --interleave=all`, which spreads the memory allocation evenly across all NUMA nodes. This way every backend gets roughly equal performance.

You probably won't encounter NUMA on your 2-vCPU lab server or small cloud instances. But on a production server with 2 or 4 sockets (common for large on-prem databases), NUMA awareness matters.

### Network Tuning for Replication

The TCP keepalive settings (covered in Build Guide 07) solve a specific problem: detecting dead connections.

By default, Linux waits over 2 hours before deciding a TCP connection is dead. On a replication link, that means if the network between primary and standby fails, it takes 2+ hours for the primary to notice the standby is gone. That's 2 hours of WAL piling up.

The tuned settings (keepalive_time=60, interval=10, probes=6) detect a dead connection in about 2 minutes: send a keepalive at 60 seconds, retry every 10 seconds, give up after 6 retries.

---

## 4. PostgreSQL Memory Architecture - Where Your Data Lives

Understanding how PostgreSQL uses memory is the foundation of performance tuning. Every setting you adjust in this section changes how much data PostgreSQL keeps in RAM versus going to disk. And the difference between RAM and disk is enormous - a random read from RAM takes about 0.1 microseconds, while a random read from an SSD takes about 100 microseconds. That's a 1000x difference.

Here's the big picture of how PostgreSQL divides your server's RAM:

```
+-------------------------------------------------------------------+
|                       Total Server RAM (64 GB)                     |
|                                                                    |
|  +--------------------------+  +-------------------------------+   |
|  |   shared_buffers (16 GB) |  |     OS Page Cache (~32 GB)    |   |
|  |   PostgreSQL's own cache |  |     Linux's automatic cache   |   |
|  |   Shared by ALL backends |  |     Managed by the kernel     |   |
|  +--------------------------+  +-------------------------------+   |
|                                                                    |
|  +--------------------------+  +-------------------------------+   |
|  |  Per-backend memory      |  |  Background workers           |   |
|  |  - work_mem (per sort/   |  |  - autovacuum workers         |   |
|  |    hash, NOT per conn)   |  |    (maintenance_work_mem)     |   |
|  |  - temp_buffers          |  |  - WAL writer                 |   |
|  |  - ~5-10 MB overhead     |  |  - checkpointer, bgwriter    |   |
|  +--------------------------+  +-------------------------------+   |
+-------------------------------------------------------------------+
```

### shared_buffers - PostgreSQL's Own Page Cache

**What is it?** shared_buffers is PostgreSQL's private cache for data pages. When a query needs to read a row, PostgreSQL first checks shared_buffers. If the page containing that row is already there (called a "cache hit"), the data comes straight from RAM - extremely fast. If the page isn't there (a "cache miss"), PostgreSQL reads it from disk and puts a copy in shared_buffers for next time.

You'll configure this in Build Guide 03 (Memory Tuning).

**The 25% rule:** Set shared_buffers to 25% of total RAM.

Why not more? Because PostgreSQL isn't the only thing caching data. Linux ALSO caches disk reads in the OS page cache. If you give 50% of RAM to shared_buffers, the OS cache shrinks. When a page gets evicted from shared_buffers, it can't be found in the OS cache either - so it has to come from disk. The 25% rule balances both caches:

- shared_buffers (25%) = PostgreSQL's controlled, purpose-built cache
- OS page cache (~50%) = Linux's automatic, general-purpose cache
- Everything else (~25%) = backend memory, OS processes, headroom

Sizing examples:
- 4 GB server (like your lab): `shared_buffers = 1GB`
- 16 GB server: `shared_buffers = 4GB`
- 64 GB server: `shared_buffers = 16GB`
- 256 GB server: `shared_buffers = 64GB`

> **Concept:** PostgreSQL has a two-layer caching architecture. Layer 1 is shared_buffers (PostgreSQL controls this). Layer 2 is the OS page cache (Linux controls this). A page evicted from shared_buffers might still be in the OS cache, which is much faster than disk. This is why giving shared_buffers MORE than 25% can actually make things slower - you're shrinking Layer 2, and pages that miss Layer 1 have to go all the way to disk.

### work_mem - The Sneaky Memory Setting

**What is it?** work_mem is the amount of memory PostgreSQL allocates for sort operations, hash tables, and similar in-memory operations within a query. When a query has an ORDER BY, GROUP BY, DISTINCT, or hash join, PostgreSQL uses work_mem for that operation.

Here's the critical thing that trips people up: **work_mem is per-operation, not per-connection, not per-query.** A single complex query might have 3 sort operations and 2 hash joins - that's 5 x work_mem for ONE query. If 200 connections are each running queries like that:

```
200 connections x 5 operations x 64 MB = 64 GB
```

That can blow out all your RAM from a single setting.

**Best practice:** Set a conservative global default (4-16 MB depending on your server), then raise it per-session when you need to run analytical queries:

```sql
-- Global default (conservative):
ALTER SYSTEM SET work_mem = '16MB';

-- For a specific reporting session that needs big sorts:
SET work_mem = '256MB';
-- This resets when the session ends
```

**How to know if work_mem is too low:** In EXPLAIN output (which you'll learn in Build Guide 01), look for this:

```
Sort Method: external merge  Disk: 45600kB    <-- BAD: spilled to disk
```

vs this:

```
Sort Method: quicksort  Memory: 2048kB        <-- GOOD: fits in memory
```

When you see "external merge Disk", it means the sort didn't fit in work_mem and had to write temporary files to disk. That is dramatically slower. Either raise work_mem globally or for that session.

### maintenance_work_mem - Fuel for Maintenance Operations

**What is it?** This is like work_mem but specifically for maintenance operations: VACUUM, CREATE INDEX, ALTER TABLE ADD FOREIGN KEY. These operations run less frequently but benefit greatly from more memory.

You can set this much higher than work_mem because only a few maintenance operations run at once, while hundreds of queries might run simultaneously:

```sql
ALTER SYSTEM SET maintenance_work_mem = '2GB';  -- on a 64 GB server
```

Larger values make VACUUM run faster (it can hold more dead tuple pointers in memory) and CREATE INDEX faster (it can sort more data in memory). There's limited benefit above 2 GB for most workloads.

### effective_cache_size - A Hint, Not a Setting

**What is it?** This is the most misunderstood PostgreSQL setting. effective_cache_size does NOT allocate any memory. It doesn't reserve anything. It doesn't change how PostgreSQL uses RAM.

It's a **hint to the query planner**: "Hey planner, when you're deciding whether to use an index scan or a sequential scan, assume this much total cache is available (shared_buffers + OS page cache combined)."

If you set this too low, the planner thinks most data won't be in cache and favors sequential scans (reading everything in order from disk is faster than random reads from disk). If you set it correctly (~75% of RAM), the planner knows most data is probably cached and willingly chooses index scans.

```sql
ALTER SYSTEM SET effective_cache_size = '48GB';  -- 75% of 64 GB RAM
```

On your lab server with 1.6 GB RAM, you'd set this to about 1.2 GB.

### wal_buffers and temp_buffers

These rarely need tuning:

- **wal_buffers** - shared memory for WAL records before they're flushed to disk. Default is 1/32 of shared_buffers (capped at 64 MB). Leave it alone unless you have extreme write throughput.
- **temp_buffers** - per-session memory for temporary tables. Default 8 MB. Only raise if your application uses large temp tables in stored procedures.

---

## 5. Storage and I/O - The Slowest Link in the Chain

No matter how much RAM you have, data eventually lives on disk. How PostgreSQL writes to disk, when it flushes, and how WAL (Write-Ahead Logging) works all affect performance. You'll work with checkpoints and WAL hands-on in Build Guide 05.

### WAL on a Separate Disk

WAL writes are sequential (one record after another, in order) and constant (every INSERT, UPDATE, DELETE generates WAL). Data writes are random (updating pages scattered across different tables). When WAL and data share the same disk, they compete.

On a dedicated database server, putting WAL on a separate physical volume prevents this competition. In practice, you symlink `pg_wal` to the separate mount:

```
# Data on one volume:
/opt/pgsql/data  ->  /dev/nvme0n1

# WAL on another volume:
/opt/pgsql/data/pg_wal  ->  /dev/nvme1n1
```

On cloud instances with high-performance NVMe or provisioned IOPS EBS, this matters less because the storage can handle both workloads. On spinning disks, it's critical.

### Checkpoint Tuning - Smoothing Out the Write Storm

**What is a checkpoint?** A checkpoint is when PostgreSQL flushes ALL dirty pages from shared_buffers to disk. It's the database saying "let me make sure everything in memory is safely on disk, so if I crash, I know where to start recovery from."

Checkpoints are triggered by two things:
1. **Time** - checkpoint_timeout (default: 5 minutes) fires a checkpoint on a timer
2. **WAL volume** - when the amount of WAL generated since the last checkpoint reaches max_wal_size (default: 1 GB), a checkpoint fires

The problem with frequent checkpoints is that they create bursts of disk I/O. All those dirty pages flushed at once can saturate your disk. The solution is to make checkpoints less frequent and spread the writes out:

```sql
ALTER SYSTEM SET max_wal_size = '4GB';              -- more WAL between checkpoints
ALTER SYSTEM SET min_wal_size = '1GB';              -- keep at least this much WAL on disk
ALTER SYSTEM SET checkpoint_timeout = '15min';       -- longer interval between checkpoints
ALTER SYSTEM SET checkpoint_completion_target = 0.9;  -- spread writes over 90% of the interval
```

That last one, `checkpoint_completion_target`, is subtle but important. Imagine your checkpoint_timeout is 10 minutes:

```
completion_target = 0.5:  |||||||...........  (burst write in first 5 min, idle for 5 min)
completion_target = 0.9:  |..|..|..|..|..|.  (writes spread over 9 min, much smoother)
```

A target of 0.9 means "try to finish the checkpoint over 90% of the interval." This spreads the I/O out so it doesn't spike.

> **Concept:** There's a trade-off with checkpoint frequency. Less frequent checkpoints (larger max_wal_size, longer timeout) mean less I/O overhead during normal operation. But they also mean longer crash recovery, because more WAL needs to be replayed. On a 64 GB server with NVMe, max_wal_size of 4-8 GB is a good balance. The extra 30 seconds of crash recovery is worth the smoother performance during normal operations.

### wal_compression - Smaller WAL, Less I/O

Every time PostgreSQL modifies a page for the first time after a checkpoint, it writes the ENTIRE 8 KB page to WAL (called a "full page image" or FPI). This is a safety measure against partial page writes during a crash.

These full page images make WAL significantly larger. `wal_compression` compresses them:

```sql
ALTER SYSTEM SET wal_compression = 'lz4';  -- PG15+, or 'pglz' for older versions
```

This typically reduces WAL volume by 30-60%, which means:
- Less disk I/O for WAL writes
- Less data shipped to standby servers during replication
- The trade-off is a small CPU cost for compression, which is almost always worth it

### Temp Files - When work_mem Isn't Enough

When a sort or hash operation exceeds work_mem, PostgreSQL writes temporary files to disk. These temp files go in the `pgsql_tmp` directory inside the data directory.

You can log when this happens:

```sql
ALTER SYSTEM SET log_temp_files = '10MB';  -- log any temp file larger than 10 MB
```

And you can monitor total temp file usage across all databases:

```sql
SELECT datname, temp_files, temp_bytes,
       pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_database
WHERE temp_bytes > 0;
```

If temp_bytes is consistently high, your work_mem is too low for the workload. Either raise it globally or identify the specific queries that need more memory.

---

## 6. Connection Management - Less is More

This might be the most counterintuitive section: PostgreSQL performs WORSE with more connections. You'll see this firsthand in Build Guide 08.

### Why More Connections = Worse Performance

PostgreSQL creates a new operating system process for every connection. This is different from many databases that use threads. Each backend process uses:

- **5-10 MB of private memory** just for existing (before running any queries)
- **File descriptors** (limited by ulimits)
- **Lock table entries** (more connections = more lock checking)
- **Proc array slots** (PostgreSQL scans this array on every snapshot for MVCC visibility)

That last point is the killer. Every time a query starts, PostgreSQL scans the entire proc array to figure out which transactions are visible. With 500 connections, that's 500 entries to scan on every single query, even if most connections are idle.

Real-world benchmarks consistently show: on a 16-core server, performance peaks at about 50-60 active connections and degrades beyond that. At 500 connections, you're getting lower throughput than at 50.

**Rule of thumb:** `max_connections` should be 2-4x your CPU core count for OLTP workloads. On a 16-core server, that's 32-64 connections.

"But my application needs 2000 connections!" That's what PgBouncer is for.

### PgBouncer - The Connection Multiplexer

**What is it?** PgBouncer is a lightweight connection pooler that sits between your application and PostgreSQL. Your application connects to PgBouncer (thinking it's PostgreSQL), and PgBouncer maintains a small pool of real PostgreSQL connections that it shares among all clients.

```
Your application (2000 connections)
       |
   PgBouncer (pool_size = 30)
       |
   PostgreSQL (30 backend processes)
```

2000 application connections share 30 real PostgreSQL connections. Each app connection "borrows" a real connection, uses it, and returns it to the pool.

PgBouncer has three pool modes:

| Mode | When the connection is returned | Best for | Restrictions |
|------|-------------------------------|----------|--------------|
| **session** | When the client disconnects | Legacy apps needing LISTEN/NOTIFY or session variables | Least efficient pooling |
| **transaction** | When COMMIT or ROLLBACK completes | Web apps (most common choice) | Can't use SET, prepared statements, or LISTEN |
| **statement** | After each individual statement | Simple read-heavy apps | Can't use multi-statement transactions at all |

**Transaction mode** is the standard for web applications. When a client finishes a transaction (COMMIT), the real PostgreSQL connection goes back into the pool immediately. Another client can grab it for their next transaction. This gives you the best connection reuse.

### idle_in_transaction_session_timeout

Here's a scenario that happens all the time: an application starts a transaction (BEGIN), runs a query, and then... does nothing. Maybe it's waiting for user input. Maybe it crashed. But the transaction is still open, and as long as it's open:

- The connection is held (can't be reused by PgBouncer)
- Any locks it holds are kept
- VACUUM can't clean up dead tuples from rows modified after this transaction started

This one stuck transaction can prevent VACUUM from running effectively on the entire database.

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
```

This kills any session that sits idle inside an open transaction for more than 30 seconds. It's a safety net against one stuck application degrading everything.

> **Concept:** Connection management is where most teams get the biggest "free" performance win. If your application opens 500 connections directly to PostgreSQL, putting PgBouncer in front and reducing real connections to 50 will likely improve throughput significantly - even without changing a single query. The reason is that PostgreSQL's architecture (process-per-connection, proc array scanning, lock contention) simply works better with fewer connections doing more work than many connections doing less.

---

## 7. The Query Planner and EXPLAIN - Reading PostgreSQL's Mind

This is the heart of performance tuning. Build Guide 01 covers EXPLAIN/ANALYZE hands-on and Build Guide 04 covers query optimization patterns. Here's the deeper understanding of what's happening inside PostgreSQL's head when it plans your query.

### How the Planner Thinks

PostgreSQL uses a **cost-based optimizer**. When you run a query, the planner:

1. Generates all possible ways to execute it (different scan types, different join orders, different join methods)
2. Estimates the "cost" of each plan using a mathematical model
3. Picks the cheapest plan

The cost isn't measured in seconds - it's an abstract unit based on how much disk I/O and CPU work the plan requires. The planner uses several cost parameters to calculate this:

| Parameter | Default | What it represents | SSD setting |
|-----------|---------|---------------------|-------------|
| seq_page_cost | 1.0 | Reading one page sequentially from disk | 1.0 |
| random_page_cost | 4.0 | Reading one page randomly from disk | 1.1 |
| cpu_tuple_cost | 0.01 | Processing one row | 0.01 |
| cpu_index_tuple_cost | 0.005 | Processing one index entry | 0.005 |

The crucial ratio is `random_page_cost` to `seq_page_cost`. At the default ratio of 4:1, the planner thinks random reads (index scans) are 4x more expensive than sequential reads (table scans). That was true for spinning disks where the read head had to physically seek. On SSDs, random reads are nearly as fast as sequential reads.

```sql
ALTER SYSTEM SET random_page_cost = 1.1;  -- tell the planner your SSD is fast
```

After this change, the planner is much more willing to choose index scans because it knows random reads aren't that expensive anymore.

### What Statistics the Planner Reads

The planner's estimates are only as good as the statistics it has. PostgreSQL maintains two sources of statistics:

**pg_class** - basic table info (how many rows, how many disk pages):

```sql
SELECT relname, reltuples::bigint AS estimated_rows, relpages
FROM pg_class WHERE relname = 'orders';
```

If `reltuples` says your table has 100 rows but it actually has 1 million, every plan the planner generates will be wrong.

**pg_statistic** (queried through the friendlier `pg_stats` view) - per-column distribution data:
- Most common values and their frequencies
- Histogram of value distribution
- Number of distinct values
- Fraction of NULL values

```sql
SELECT attname, n_distinct, most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'orders' AND attname = 'status';
```

These statistics tell the planner things like "the status column has 5 distinct values, 'shipped' appears 60% of the time, 'pending' appears 5% of the time." With this, it knows that `WHERE status = 'pending'` returns ~5% of rows (use an index) while `WHERE status = 'shipped'` returns 60% (sequential scan is probably faster).

### ANALYZE - Refreshing Statistics

**What is it?** ANALYZE reads a sample of rows from a table and updates `pg_statistic`. It's the ONLY way to refresh these column statistics. Regular VACUUM does NOT update statistics - only ANALYZE does.

Autovacuum runs auto-analyze when changed rows exceed:
```
autovacuum_analyze_threshold + autovacuum_analyze_scale_factor x reltuples
```

With defaults (threshold=50, scale_factor=0.1), a 100,000-row table gets re-analyzed after 10,050 row changes. That's usually fine, but after a bulk operation (loading millions of rows, or deleting 90% of a table), you should run ANALYZE manually.

**Real-world war story:** A bulk data deletion job removed 90% of rows from a table but didn't run ANALYZE afterward. The planner thought a 60 MB table had 2 rows. Every query that touched that table got catastrophically wrong execution plans - sequential scans everywhere, wrong join strategies, no parallel execution. The fix took 3 seconds: `ANALYZE VERBOSE table_name;`. The diagnosis took an hour because nobody thought to check statistics first.

> **Concept:** Stale statistics are the #1 cause of sudden performance degradation in PostgreSQL. When a query that was fast yesterday is suddenly slow today, and nothing else changed, the first thing to check is: did a bulk data operation run without ANALYZE? Did autovacuum's auto-analyze fire? Check `last_autoanalyze` in `pg_stat_user_tables`. Nine times out of ten, an ANALYZE fixes it.

### Reading EXPLAIN Output

When you run `EXPLAIN (ANALYZE, BUFFERS)` on a query (you'll practice this extensively in Build Guide 01), the output tells you exactly what happened:

```
Index Scan using orders_pkey on orders  (cost=0.42..8.44 rows=1 width=64) (actual time=0.015..0.016 rows=1 loops=1)
```

Breaking this down:
- **cost=0.42..8.44** - the planner's estimated cost (startup..total). These are abstract units, not milliseconds.
- **rows=1** - the planner's estimate of how many rows this step returns
- **actual time=0.015..0.016** - real wall-clock time in milliseconds
- **rows=1** (in the actual section) - how many rows it ACTUALLY returned
- **loops=1** - how many times this step executed (important for nested loops)

**The most important comparison** is estimated rows vs actual rows. When they differ by more than 10x, the planner is working with bad information:

```
Seq Scan on orders  (cost=0.00..1.03 rows=1 width=64) (actual time=0.015..850.000 rows=450000 loops=1)
```

Estimated 1 row, got 450,000. The planner thought it was looking for a needle in a haystack (1 row = use whatever scan is cheapest) but actually it needed to return half the table. Run ANALYZE.

### Scan Types - What They Mean

You'll see all of these in Build Guide 01. Here's the mental model for when the planner chooses each one:

**Sequential Scan** - reads every page in the table, in order. Not always bad! For queries returning more than 5-10% of rows, sequential I/O (reading pages in order) is faster than random I/O (jumping around to specific pages via an index). Also optimal for tiny tables where the whole table fits in a few pages.

**Index Scan** - walks the B-tree index to find matching rows, then fetches each row from the table (random I/O). Best when you're selecting a small fraction of rows. Each row fetch is a random read from the table heap.

**Index Only Scan** - reads everything it needs from the index itself, never touches the table. This is the fastest possible scan, but it requires:
1. A covering index that includes all columns the query needs
2. The visibility map to confirm all matching rows are visible (recently VACUUMed)

If you see `Heap Fetches: 0`, the visibility map was up to date and no table access was needed. If Heap Fetches is high, VACUUM hasn't run recently.

**Bitmap Index Scan + Bitmap Heap Scan** - a two-step process. First, scan the index and build a bitmap of which pages contain matching rows. Then read those pages in physical order (sequential I/O). This is the planner's compromise when too many rows for an Index Scan (too much random I/O) but too few for a Seq Scan.

### Join Types

**Nested Loop** - for each row in the outer table, look up matching rows in the inner table. Works great when the outer side has few rows and the inner side has an index. Performance is O(outer_rows x inner_lookup_cost). Catastrophic when the outer side is large and the inner side lacks an index.

**Hash Join** - builds a hash table from one input, then probes it with the other. Best for joining larger tables. If you see `Batches > 1` in the EXPLAIN output, the hash table didn't fit in work_mem and spilled to disk. Increase work_mem.

**Merge Join** - sorts both inputs, then merges them in order (like merging two sorted decks of cards). Efficient when both inputs are already sorted, either from indexes or from prior Sort operations.

### Buffers Output - Where Did the Data Come From?

When you include BUFFERS in your EXPLAIN, you see where each page came from:

```
Buffers: shared hit=520 read=980 dirtied=12 written=3
         temp read=450 written=450
```

| Field | What it means |
|-------|---------------|
| **shared hit** | Pages found in shared_buffers (fast, from RAM) |
| **shared read** | Pages read from disk or OS cache (slower) |
| **shared dirtied** | Pages this query modified |
| **shared written** | Pages written to disk during the query (rare - means bgwriter is behind) |
| **temp read/written** | Temp file I/O because work_mem was too small |

The cache hit ratio for a query is `hit / (hit + read)`. For OLTP queries, you want this above 99%. If you're seeing low hit ratios, either shared_buffers is too small or the query is touching too many pages (probably needs an index).

---

## 8. Indexing Strategy - The Right Tool for the Right Job

Indexes are how you make queries fast. But they're not free - every index costs disk space and slows down writes. You'll create and test indexes hands-on in Build Guide 02. Here's the strategic thinking behind choosing the right index for the right situation.

### B-tree - The Default Workhorse

**What is it?** A B-tree (Balanced tree) is a sorted tree structure that lets PostgreSQL find any value in O(log n) time. It's the default index type and handles about 90% of indexing needs.

Supports: `=`, `<`, `>`, `<=`, `>=`, `BETWEEN`, `IN`, `IS NULL`, `ORDER BY`, `MIN/MAX`

**Multi-column index column order matters.** This is a common gotcha. The index `(status, created_at)` can be used for:
- `WHERE status = 'pending'` (uses first column)
- `WHERE status = 'pending' ORDER BY created_at` (uses both columns)
- `WHERE status = 'pending' AND created_at > '2024-01-01'` (uses both)

But it CANNOT be used for:
- `WHERE created_at > '2024-01-01'` alone (can't skip the first column)

Think of it like a phone book sorted by last name, then first name. You can look up all Smiths, or all Smith-Johns, but you can't efficiently find all Johns across all last names.

**Rule:** Put the most selective column first (the one that filters out the most rows), then add sort columns.

### Other Index Types

PostgreSQL has several specialized index types for specific use cases:

**Hash** - only supports equality (`=`). Slightly faster than B-tree for pure equality lookups on large values like UUIDs or long strings. Rarely used because B-tree handles equality well AND supports range queries.

**GIN (Generalized Inverted Index)** - designed for columns that contain multiple values. If you have a JSONB column, an array column, or a full-text search column, GIN is what you want. It indexes every individual value inside the column. Slower to update (each INSERT might add many index entries) but very fast for lookups.

**GiST (Generalized Search Tree)** - designed for geometric data, ranges, and nearest-neighbor queries. If you're using PostGIS for geographic data or range types (e.g., date ranges), GiST is your tool.

**BRIN (Block Range Index)** - stores just the min/max values for ranges of physical table blocks. Tiny footprint (1000x smaller than a B-tree) but only works when data is physically ordered. Perfect for append-only tables with timestamp columns where new rows always have later timestamps. Useless if data is randomly ordered.

### Covering Indexes (INCLUDE)

A covering index includes extra columns that aren't used for filtering but ARE needed by the query. This enables Index Only Scans - the query never touches the table at all. You'll create one of these in Build Guide 02.

```sql
-- Query: SELECT customer_id, status, total FROM orders WHERE customer_id = 42;

-- Covering index:
CREATE INDEX ON orders (customer_id) INCLUDE (status, total);
```

The INCLUDE columns are stored in the index leaf pages but not in the tree structure itself. They can't be used for filtering - only for avoiding heap fetches.

### Partial Indexes

Why index every row when you only query some of them?

```sql
-- Only 3% of orders are 'pending', but you query them constantly:
CREATE INDEX ON orders (created_at) WHERE status = 'pending';
```

This index is tiny (3% of a full index), faster to update, and faster to scan. Your query must include the same WHERE clause for the planner to use it:

```sql
-- Uses the partial index:
SELECT * FROM orders WHERE status = 'pending' AND created_at > now() - interval '1 hour';
```

### Expression Indexes

When you filter on a function or expression:

```sql
-- This query can't use a regular index on email:
SELECT * FROM users WHERE lower(email) = 'alice@example.com';

-- Create an index on the expression:
CREATE INDEX ON users (lower(email));
```

The query must use the EXACT same expression as the index definition.

### Finding and Removing Unused Indexes

Every index costs write performance - every INSERT, UPDATE, or DELETE on the table must also update every index. If an index is never used for reads, it's pure overhead.

```sql
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND pg_relation_size(indexrelid) > 1024 * 1024  -- bigger than 1 MB
ORDER BY pg_relation_size(indexrelid) DESC;
```

If `idx_scan = 0` after weeks of production traffic, the index is dead weight. Before dropping it, verify it's not there for a uniqueness constraint.

> **Concept:** Indexes are a trade-off between read speed and write cost. Every index you add makes reads faster (for queries that use it) but writes slower (for ALL writes to that table). A table with 10 indexes means every INSERT updates 10 indexes. The goal isn't "index everything" - it's "index the columns that are actually filtered, joined, or sorted in your real queries." Use pg_stat_user_indexes to find unused indexes and drop them. In production, I've seen tables with 15 indexes where only 3 were actually used - dropping the other 12 improved write throughput by 40%.

### Index Bloat

When you DELETE or UPDATE rows, the dead entries in indexes aren't immediately removed. VACUUM cleans them up, but if VACUUM falls behind, indexes accumulate bloat - dead entries that take up space and slow down scans.

To detect bloat:

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
SELECT * FROM pgstattuple('orders_pkey');
-- Look at dead_tuple_percent
```

To fix bloated indexes:
- **REINDEX CONCURRENTLY** (PG12+) - rebuilds the index without blocking reads or writes. This is the preferred method.
- **pg_repack** - an external tool that does the same thing for both tables and indexes, also without locking
- **VACUUM FULL** - rewrites the entire table AND its indexes, but takes an ACCESS EXCLUSIVE lock (blocks everything). Last resort for maintenance windows only.

### When NOT to Add an Index

Don't add an index for:
- **Small tables** (< 1000 rows) - sequential scan is faster because the whole table fits in a few pages
- **Low-selectivity columns** (e.g., a boolean with 50/50 distribution) - the index would return half the table, which is worse than a sequential scan
- **Write-heavy tables** where read performance isn't the bottleneck
- **Columns never used** in WHERE, JOIN, or ORDER BY

---

## 9. Autovacuum - The Cleanup Crew You Can't Ignore

Build Guide 09 walks you through autovacuum tuning step by step. Here's why it matters so much and how to think about tuning it for different workloads.

### What Autovacuum Actually Does

When you UPDATE a row in PostgreSQL, the old version of that row doesn't disappear. PostgreSQL keeps it around in case another transaction still needs to see it (this is how MVCC - Multi-Version Concurrency Control - works). When you DELETE a row, same thing - the row is marked as dead but not removed.

Over time, these dead rows pile up. They waste disk space, make table scans slower (PostgreSQL has to read past dead rows), and can cause transaction ID wraparound issues.

Autovacuum is a set of background worker processes that automatically clean up these dead rows. It does two things:

1. **VACUUM** - marks dead tuples as reusable space (doesn't shrink the file, just makes space available for new rows)
2. **ANALYZE** - samples the table and updates planner statistics

Both are essential. Without VACUUM, tables bloat forever. Without ANALYZE, the planner picks wrong execution plans.

### When Autovacuum Triggers

Autovacuum fires VACUUM when dead tuples exceed:
```
autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor x reltuples)
```

With defaults (threshold=50, scale_factor=0.2):
- 1,000-row table: vacuum after 250 dead rows (50 + 0.2 x 1000)
- 10,000,000-row table: vacuum after 2,000,050 dead rows (50 + 0.2 x 10M)

That 10-million-row table has to accumulate 2 million dead rows (20% of the table!) before autovacuum kicks in. By that point, the table is significantly bloated. This is why the default scale_factor of 0.2 is too aggressive for large tables.

### Per-Table Tuning for High-Churn Tables

For tables with heavy INSERT/UPDATE/DELETE activity, lower the thresholds:

```sql
ALTER TABLE orders SET (
  autovacuum_vacuum_scale_factor = 0.01,      -- trigger at 1% dead tuples (not 20%)
  autovacuum_vacuum_threshold = 1000,          -- or 1000 dead tuples minimum
  autovacuum_analyze_scale_factor = 0.005,     -- re-analyze at 0.5% changes
  autovacuum_analyze_threshold = 500
);
```

For that 10M-row table, vacuum now triggers at 101,000 dead rows instead of 2,000,050. Much better.

### Cost-Based Vacuum Throttling

Autovacuum throttles itself to avoid overwhelming disk I/O. It works in chunks - vacuum some pages, pause, vacuum some more, pause:

```sql
ALTER SYSTEM SET autovacuum_vacuum_cost_delay = '2ms';    -- how long to pause
ALTER SYSTEM SET autovacuum_vacuum_cost_limit = 800;      -- how much work before pausing
```

Higher `cost_limit` = vacuum runs faster but uses more I/O. On fast NVMe storage, you can safely raise this to 800-2000. The default of 200 was designed for spinning disks and is too conservative for SSDs.

For a specific critical table that needs aggressive vacuuming:

```sql
ALTER TABLE hot_table SET (
  autovacuum_vacuum_cost_delay = '0ms',    -- no throttling at all
  autovacuum_vacuum_cost_limit = 2000
);
```

### autovacuum_max_workers

Default is 3 workers. Each worker can only vacuum one table at a time. If you have 50 high-churn tables and 3 workers, tables queue up waiting for a turn.

```sql
ALTER SYSTEM SET autovacuum_max_workers = 6;  -- requires restart
```

One catch: all workers share the global `autovacuum_vacuum_cost_limit`. If you have 6 workers sharing a cost_limit of 800, each worker effectively gets 800/6 = 133. You might need to increase cost_limit proportionally.

### Monitoring Autovacuum Health

```sql
SELECT relname, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric / GREATEST(n_live_tup, 1) * 100, 1) AS dead_pct,
       last_autovacuum, last_autoanalyze,
       autovacuum_count, autoanalyze_count
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

**Red flags to watch for:**
- `dead_pct` above 20% - vacuum is falling behind
- `last_autovacuum` is NULL - vacuum has never run on this table (brand new table or autovacuum is disabled/broken)
- `n_dead_tup` keeps growing over time - dead tuples are created faster than vacuum cleans them up

> **Concept:** Table bloat in PostgreSQL is NOT returned to the operating system by regular VACUUM. VACUUM marks space as reusable for future inserts within PostgreSQL, but the file on disk stays the same size. If a table temporarily grew to 10 GB due to a bulk load and then you deleted 90% of the data, the file stays at 10 GB - but now 9 GB of it is reusable space. Only VACUUM FULL (blocks everything) or pg_repack (no locks) can actually shrink the file. For most tables, just let the reusable space get filled by future inserts.

---

## 10. Monitoring Views, Wait Events, and Parallel Query

These three topics are how you monitor a running production database. You'll get hands-on with pg_stat views in Build Guide 10, wait events in Build Guide 11, and parallel query in Build Guide 12.

### pg_stat_activity - What's Running Right Now?

**What is it?** `pg_stat_activity` is a system view that shows you every connection to your database and what it's doing right now. It's the first thing you check when someone reports slowness.

```sql
SELECT pid, state, wait_event_type, wait_event,
       now() - query_start AS duration,
       left(query, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY duration DESC;
```

The `state` column tells you what each connection is doing:
- **active** - currently running a query
- **idle** - waiting for the next command from the application
- **idle in transaction** - inside a BEGIN but not doing anything - this is dangerous (holds locks, blocks vacuum)
- **idle in transaction (aborted)** - a transaction that errored but wasn't rolled back

If you see many connections in `idle in transaction`, that's often the cause of your performance problems.

### pg_stat_statements - The Single Most Important Extension

**What is it?** `pg_stat_statements` is a PostgreSQL extension that tracks execution statistics for every normalized query. "Normalized" means it replaces literal values with parameters, so `SELECT * FROM orders WHERE id = 42` and `SELECT * FROM orders WHERE id = 99` are tracked as the same query pattern.

This is how you answer the question: "Which queries should I optimize first?"

```sql
-- Top queries by total time (where to focus tuning):
SELECT left(query, 60) AS query,
       calls,
       round(total_exec_time::numeric, 1) AS total_ms,
       round(mean_exec_time::numeric, 1) AS mean_ms,
       rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

A query that takes 5ms but runs 1 million times per day uses more resources than a query that takes 10 seconds but runs once. `total_exec_time` captures this - sort by it to find where to focus.

After tuning, reset the statistics to measure improvement:

```sql
SELECT pg_stat_statements_reset();
```

### pg_stat_user_tables - Table Health Dashboard

This view shows per-table activity:

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

What to look for:
- **idx_pct below 95%** on a large table means too many sequential scans - probably missing an index
- **n_dead_tup above 10% of n_live_tup** means vacuum is falling behind
- **last_autoanalyze is NULL** means statistics have never been collected - the planner is guessing

### pg_statio_user_tables - Cache Hit Ratios

How often does each table's data come from cache (fast) vs disk (slow)?

```sql
SELECT relname,
       heap_blks_hit, heap_blks_read,
       round(heap_blks_hit::numeric / GREATEST(heap_blks_hit + heap_blks_read, 1) * 100, 1) AS hit_pct
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 1000
ORDER BY hit_pct ASC;
```

For OLTP tables, target above 99%. Tables with hit ratios below 90% aren't fitting in cache - either increase shared_buffers, optimize queries to touch fewer pages, or add more RAM.

### pg_stat_bgwriter - Checkpoint Health

```sql
SELECT checkpoints_timed, checkpoints_req,
       round(checkpoints_req::numeric / GREATEST(checkpoints_timed + checkpoints_req, 1) * 100, 1) AS req_pct,
       buffers_checkpoint, buffers_clean, buffers_backend
FROM pg_stat_bgwriter;
```

- **req_pct above 10%** means checkpoints are being triggered by WAL volume (max_wal_size is too low), not by the timer. Increase max_wal_size.
- **buffers_backend is high** relative to checkpoint + clean buffers means backends are writing dirty pages themselves because the background writer can't keep up. The bgwriter should be doing this work, not your query processes.

### Wait Events - What's Your Query Waiting For?

When a query is slow but CPU and disk look fine, the query might be waiting on something. You'll dig into this in Build Guide 11.

```sql
SELECT pid, wait_event_type, wait_event, state,
       now() - query_start AS duration,
       left(query, 60) AS query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
  AND state = 'active';
```

The main wait event categories:

| Category | What it means | Common causes |
|----------|---------------|---------------|
| **Lock** | Waiting for a heavyweight lock | Another transaction holds a conflicting lock |
| **LWLock** | Waiting for a lightweight internal lock | Shared buffer contention, WAL insert contention |
| **IO** | Waiting for disk I/O to complete | Slow disk, data not in cache |
| **BufferPin** | Waiting for access to a buffer page | Concurrent access to the same hot page |
| **Client** | Waiting for the client application | Slow app, network latency |
| **Activity** | Idle background process | Normal for bgwriter and autovacuum launcher |

The most common wait events you'll encounter:

| Wait Event | Type | What it means | What to do |
|------------|------|---------------|------------|
| **relation** | Lock | Waiting for a table-level lock | Find and fix the blocking query |
| **transactionid** | Lock | Waiting for another transaction to commit | Find the blocking transaction |
| **tuple** | Lock | Waiting for a row-level lock | Row contention, might need application redesign |
| **WALInsertLock** | LWLock | Contention writing WAL | Increase wal_buffers or reduce commit rate |
| **DataFileRead** | IO | Reading data file from disk | Data not in cache, check shared_buffers |

### Finding Lock Blockers

When you see Lock waits, use `pg_blocking_pids()` to find who's blocking whom:

```sql
SELECT pid, pg_blocking_pids(pid) AS blocked_by,
       left(query, 60) AS query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Or for more detail, join `pg_locks` with `pg_stat_activity` to see the full blocking chain (you'll walk through this query in Build Guide 11).

### Lock Types - From Gentle to Nuclear

| Lock Mode | Typical Operation | How disruptive |
|-----------|-------------------|----------------|
| **AccessShareLock** | SELECT | Barely - only conflicts with AccessExclusive |
| **RowShareLock** | SELECT FOR UPDATE | Mild |
| **RowExclusiveLock** | INSERT, UPDATE, DELETE | Moderate - conflicts with Share locks |
| **ShareLock** | CREATE INDEX (non-CONCURRENTLY) | Blocks writes |
| **AccessExclusiveLock** | ALTER TABLE, DROP TABLE, VACUUM FULL | Blocks EVERYTHING |

This is why `CREATE INDEX CONCURRENTLY` exists - regular CREATE INDEX takes a ShareLock that blocks all writes. CONCURRENTLY takes weaker locks and allows writes to continue (at the cost of taking longer and doing more work).

> **Concept:** Deadlocks happen when two transactions each hold a lock the other needs. Transaction A locks row 1 and wants row 2. Transaction B locks row 2 and wants row 1. Neither can proceed. PostgreSQL automatically detects this (after deadlock_timeout, default 1 second) and kills one transaction to break the cycle. Enable `log_lock_waits = on` so you see these in your logs. Frequent deadlocks usually mean your application needs to access rows in a consistent order.

### Parallel Query - Dividing the Work

PostgreSQL can split large operations across multiple worker processes. In Build Guide 12, you'll run parallel queries and see EXPLAIN output like:

```
Finalize Aggregate  (actual time=150.00..150.01 rows=1)
  ->  Gather  (actual time=50.00..149.95 rows=3)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial Aggregate  (actual time=45.00..45.01 rows=1)
              ->  Parallel Seq Scan on big_table  (rows=333333)
```

The key parameters:

```sql
max_parallel_workers_per_gather = 2    -- max workers for one query node
max_parallel_workers = 8               -- total workers across all queries
max_worker_processes = 8               -- total background workers (includes autovacuum)
min_parallel_table_scan_size = '8MB'   -- table must be at least this big for parallel
```

**When parallel helps:** Large sequential scans, aggregates over big tables (COUNT, SUM, AVG), hash joins with large inputs, CREATE INDEX, VACUUM (PG13+).

**When parallel doesn't help:** Small tables, index lookups returning few rows, queries waiting on locks, functions marked PARALLEL UNSAFE.

If you see `Workers Launched < Workers Planned`, you've hit the global `max_parallel_workers` limit. Other queries are already using the available workers.

---

## 11. Real-World Diagnostic Workflow

When someone says "the database is slow," here is the exact decision tree to follow. This ties together everything from the previous sections:

```
Step 1: CHECK THE OS (Section 2 / Build Guide 06)
  |
  +-- top: Load average > 2x CPU count?
  |     +-- High %us? --> CPU-bound queries, jump to Step 5
  |     +-- High %wa? --> Disk I/O bottleneck, run iostat
  |     +-- High %sy? --> Too many connections, jump to Step 2
  |
  +-- Swap in use? --> EMERGENCY: check swappiness, shared_buffers sizing
  |
  +-- iostat: %util > 80%?
        +-- iotop: who's doing the I/O? vacuum? checkpoint? query?

Step 2: CHECK CONNECTIONS (Section 6 / Build Guide 08)
  |
  +-- How many connections? (SELECT count(*) FROM pg_stat_activity)
  |     +-- > 200 active? --> Deploy PgBouncer
  |     +-- Many "idle in transaction"? --> Set idle_in_transaction_session_timeout
  |
  +-- Connection storms? --> PgBouncer + exponential backoff in app

Step 3: WHAT'S RUNNING? (Section 10 / Build Guide 10)
  |
  +-- pg_stat_activity WHERE state = 'active'
  |     +-- Long-running queries? --> EXPLAIN them (Step 5)
  |     +-- Many identical queries? --> Missing index or bad plan
  |
  +-- What are they waiting on? (wait_event_type)
        +-- Lock? --> pg_blocking_pids() to find the blocker
        +-- IO? --> Disk bottleneck or cache miss
        +-- LWLock? --> Internal contention (hot row, WAL insert)

Step 4: CHECK STATISTICS (Section 9 / Build Guide 09)
  |
  +-- pg_stat_user_tables: last_autoanalyze NULL? --> ANALYZE
  +-- pg_class: reltuples wildly wrong? --> ANALYZE
  +-- High n_dead_tup? --> Autovacuum is falling behind

Step 5: EXPLAIN THE SLOW QUERY (Section 7 / Build Guide 01)
  |
  +-- EXPLAIN (ANALYZE, BUFFERS) the query
  +-- Estimated vs actual rows off by 10x+? --> Stale stats, run ANALYZE
  +-- Seq Scan on large table? --> Missing index
  +-- Sort: external merge Disk? --> Raise work_mem
  +-- Hash Batches > 1? --> Raise work_mem
  +-- Nested Loop with large outer side? --> Wrong join, check statistics
  +-- Low buffer hit ratio? --> shared_buffers too small or query touching too many pages

Step 6: FIX AND VERIFY
  |
  +-- Make the change (ANALYZE, add index, tune parameter)
  +-- Re-run EXPLAIN (ANALYZE, BUFFERS)
  +-- Compare before and after
  +-- Monitor pg_stat_statements for sustained improvement
```

Every step in this workflow maps to a BUILD guide and a section in this concepts doc. When you work through the BUILD guides, you'll practice each of these steps hands-on.

### Quick Commands Reference

| Situation | Command | What you learn |
|-----------|---------|----------------|
| Server health | `top -bn1 \| head -15` | CPU, memory, swap, load |
| Disk bottleneck? | `iostat -xz 2 5` | IOPS, latency, utilization |
| Who's doing I/O? | `sudo iotop -oP` | Process-level disk activity |
| Historical data | `sar -u -f /var/log/sa/saDD` | Past CPU/memory/disk |
| Active queries | `SELECT * FROM pg_stat_activity WHERE state='active'` | Running queries, wait events |
| Slow queries | `SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10` | Top resource consumers |
| Table health | `SELECT relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables` | Vacuum status, dead tuples |
| Cache hit ratio | `SELECT sum(heap_blks_hit)::float / sum(heap_blks_hit + heap_blks_read) FROM pg_statio_user_tables` | Overall cache effectiveness |
| Blocking locks | `SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid))>0` | Who blocks whom |
| Query plan | `EXPLAIN (ANALYZE, BUFFERS) <query>` | Actual execution details |

---

## 12. Troubleshooting

### Common Problems and Fixes

| Problem | Symptoms | Diagnosis | Fix |
|---------|----------|-----------|-----|
| **Swap usage on PG server** | Everything slow, iowait high | `free -m` shows swap used | Set vm.swappiness=1, check shared_buffers isn't too large for available RAM |
| **Sudden slow queries after bulk operation** | Queries that were fast are now slow | `SELECT reltuples FROM pg_class` shows wrong row count | `ANALYZE <table>` to refresh statistics |
| **Table bloat** | Table size much larger than data | `SELECT * FROM pgstattuple('tablename')` shows high dead_tuple_percent | Regular VACUUM, or pg_repack for severe cases |
| **"Too many connections" error** | Application can't connect | `SELECT count(*) FROM pg_stat_activity` shows max | Deploy PgBouncer, lower max_connections, kill idle-in-transaction |
| **Temp files on disk** | Slow sorts, iowait spikes | `log_temp_files = 0` shows temp file creation in logs | Raise work_mem for the session or globally |
| **Checkpoints too frequent** | Spiky I/O, `checkpoints_req` growing fast | `pg_stat_bgwriter` shows high req_pct | Increase max_wal_size |
| **Index not being used** | Seq Scan on large table despite index | `EXPLAIN` shows Seq Scan | Check random_page_cost (1.1 for SSD), run ANALYZE, check if query returns >5% of rows |
| **OOM killer terminated PostgreSQL** | Database crashed, dmesg shows "Out of memory" | `dmesg \| grep -i oom` | Set overcommit_memory=2, reduce shared_buffers, add RAM |
| **Autovacuum not keeping up** | n_dead_tup growing, table bloat | `pg_stat_user_tables` shows growing dead tuples | Lower scale_factor per-table, increase cost_limit, add workers |
| **Lock contention** | Queries waiting, pg_stat_activity shows Lock waits | `pg_blocking_pids()` finds the blocker | Fix the blocking query, consider shorter transactions, advisory locks |

### When You See These in EXPLAIN

| EXPLAIN symptom | What it means | What to do |
|-----------------|---------------|------------|
| `Sort Method: external merge Disk` | Sort spilled to temp files | Raise work_mem |
| `Heap Fetches: 12000` on Index Only Scan | Visibility map outdated | Run VACUUM |
| `Batches: 4` in Hash Join | Hash table spilled to disk | Raise work_mem |
| `Workers Launched: 0` when Workers Planned: 2 | No parallel workers available | Check max_parallel_workers |
| Estimated rows=1, actual rows=500000 | Statistics wildly wrong | Run ANALYZE |
| Seq Scan on million-row table with WHERE | Missing index | Create an appropriate index |
| Nested Loop with Seq Scan on inner side | Catastrophic join plan | Add index on join column, or run ANALYZE |

### Production Best Practices vs Lab Setup

| Setting | Your lab | Production (64 GB server) | Why different |
|---------|----------|--------------------------|---------------|
| shared_buffers | 400MB | 16GB | 25% of RAM |
| work_mem | 4MB | 16-64MB (raise per-session) | More RAM allows bigger sorts |
| maintenance_work_mem | 64MB | 2GB | Faster VACUUM and index creation |
| effective_cache_size | 1.2GB | 48GB | 75% of RAM |
| max_connections | 100 | 50 (with PgBouncer) | PgBouncer handles connection pooling |
| max_wal_size | 1GB | 4-8GB | Fewer checkpoints, smoother I/O |
| random_page_cost | 4.0 | 1.1 | SSD/NVMe has fast random reads |
| autovacuum_vacuum_scale_factor | 0.2 | 0.01 (per-table) | Large tables need more frequent vacuum |
| vm.swappiness | 60 (default) | 1 | Never swap shared_buffers to disk |
| huge_pages | off | on | Reduce TLB misses for large shared_buffers |

Your lab server is intentionally small so you can see the effects of tuning more dramatically. On a 64 GB production server, the principles are identical - the numbers just scale up.

---

## Key Takeaways

1. **Start at the OS.** Check load average, swap, disk I/O with top/vmstat/iostat before opening psql.
2. **Tune the kernel.** vm.swappiness=1, disable THP, enable huge pages, use XFS with noatime. These aren't optional.
3. **25% rule.** shared_buffers = 25% of RAM, effective_cache_size = 75%, random_page_cost = 1.1 for SSD.
4. **work_mem is per-operation**, not per-connection. Set a conservative global default, raise per-session for analytics.
5. **ANALYZE is the fix** for sudden performance degradation after bulk operations. Always your first check.
6. **pg_stat_statements** is your single best tool for finding which queries to optimize. Sort by total_exec_time.
7. **EXPLAIN (ANALYZE, BUFFERS)** shows what actually happened. Compare estimated vs actual rows. Check buffer hit ratios.
8. **Less connections = more performance.** PgBouncer in transaction mode. Keep max_connections low.
9. **Tune autovacuum per-table.** Don't rely on global defaults for high-churn tables.
10. **Check wait events** before assuming CPU or disk. Your query might just be waiting for a lock.
