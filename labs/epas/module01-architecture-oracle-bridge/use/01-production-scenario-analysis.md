---
layout: default
title: "Use 01 - Production Scenario Analysis"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 6
locked: "no"
---

# Use 01: Production Scenario Analysis

## Goal

Apply everything you learned in the Concepts and Build labs to six realistic production scenarios. Each scenario drops you into a situation that a DBA managing EPAS in production will eventually face. Your job is to think through the architecture - identify which EPAS components are involved, explain why the problem is happening at the architectural level, determine the correct response, and compare how Oracle handles the same situation. These are not quiz questions with one-word answers. Each scenario requires 20-30 minutes of focused reasoning.

## Format

This is a theory-based exercise. You do not need a running server. Read each scenario, work through the "What You Need to Determine" questions on paper or in a text editor, then expand the answer section to check your reasoning. If your answer missed something, go back to the relevant Concepts doc and re-read that section before moving on.

**Time:** 2.5-3 hours total (six scenarios at 20-30 minutes each).

**Prerequisite:** Complete all three Concepts docs and both Build labs first.

---

## Scenario 1: The Idle Connection Flood

### Context

You are the new EPAS DBA at a fintech company. The payments database runs on EPAS 16 with `max_connections = 500`. The application layer is a Java monolith with a built-in connection pool configured for 50 connections per app server. There are 10 app servers.

### The Situation

At 09:15 on Monday, PagerDuty fires: "EPAS: connection count 450/500, new connections refused." You SSH into the database server and run:

```sql
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = 'payments'
GROUP BY state;
```

Result:

```
    state    | count
-------------+-------
 idle         |   400
 active       |    30
 idle in tran |    20
```

The application team says "we didn't deploy anything this weekend."

### What You Need to Determine

1. What EPAS architectural components are involved in connection handling? How does a new connection get established?
2. Why are 400 idle connections a serious problem in EPAS specifically? How does this differ from Oracle's shared server architecture?
3. What is the correct short-term fix to restore service right now?
4. What is the correct long-term architectural fix?
5. How does PgBouncer fit into the long-term solution, and what Oracle component is it roughly analogous to?

<details markdown="block">
<summary>Worked Answer</summary>

### 1. Architecture Involved

Every client connection in EPAS is handled by a **dedicated backend process**, forked from the postmaster. When a client connects, the postmaster creates a new OS-level process that gets its own memory allocation (`work_mem`, `temp_buffers`, `maintenance_work_mem` per-session).

This is the **process-per-connection model**. There is no equivalent of Oracle's shared server (MTS) mode where multiple sessions share a pool of server processes.

### 2. Why Idle Connections Are Dangerous

Each of those 400 idle backends is a full OS process consuming roughly **5-10 MB of resident memory** just by existing - even though it is doing zero work. That is 2-4 GB of RAM wasted.

Worse, each backend holds a slot in the **procArray**, which every active transaction must scan during visibility checks (MVCC snapshot creation). More backends = slower snapshot acquisition for every query.

> **Oracle comparison:** In shared server mode, an idle connection releases its server process back to the pool. In dedicated mode, Oracle has the same problem, but DBAs use Connection Manager (CMAN) or DRCP to mitigate it.

### 3. Short-Term Fix

Find stale sessions:

```sql
SELECT pid, state, state_change, client_addr
FROM pg_stat_activity
WHERE state = 'idle'
  AND state_change < now() - interval '30 minutes';
```

Terminate them:

```sql
SELECT pg_terminate_backend(pid);
```

Then set an automatic timeout to prevent recurrence:

```sql
ALTER SYSTEM SET idle_session_timeout = '300s';
SELECT pg_reload_conf();
```

### 4. Long-Term Fix

Deploy **PgBouncer** (or pgpool-II) as a connection pooler in **transaction pooling mode**. A backend process is only assigned to a client for the duration of a transaction.

- 10 app servers x 50 connections = 500 PgBouncer connections
- PgBouncer maps those to 50-80 actual EPAS backends

This is architecturally similar to Oracle's shared server or DRCP. The key insight: EPAS does not have built-in connection pooling, so you must add it externally.

Also reduce `max_connections` to a sane value (200-300) to create back-pressure rather than letting the server silently degrade.

</details>

---

## Scenario 2: The Disappearing Disk Space

### Context

You manage an EPAS 16 instance for a healthcare platform. PGDATA is `/var/lib/edb/as16/data` on a 500 GB EBS volume. The database is 120 GB. You have streaming replication to a standby server with a replication slot named `standby_slot`.

### The Situation

At 02:00, PagerDuty fires: "Filesystem /var/lib/edb at 94% utilization." You SSH in and confirm the volume is nearly full. The database has not grown significantly - `pg_database_size('healthcare')` still returns approximately 120 GB. Something else is consuming the disk.

### What You Need to Determine

1. What directories under PGDATA could be consuming unexpected space? List at least four.
2. How do you diagnose which directory is the culprit?
3. What is the single most dangerous cause of unexpected disk growth in an EPAS instance with replication, and why?
4. If the standby server has been down for 3 days and you have a replication slot, what happens to disk usage on the primary?
5. What is the Oracle equivalent of this problem, and why does Oracle handle it differently?

<details markdown="block">
<summary>Worked Answer</summary>

### 1. Directories That Consume Space Under PGDATA

| Directory | What It Holds |
|:----------|:-------------|
| `pg_wal/` | WAL segment files (16 MB each). **Most common culprit.** |
| `base/` | Table and index data files. Growth = bloat or data growth. |
| `pg_log/` | Server log files. Grows unbounded if rotation is misconfigured. |
| `pg_stat_tmp/` | Temporary statistics files (usually small). |
| `pg_replslot/` | Replication slot metadata (tiny, but the slot causes WAL retention). |
| temp files | Sorts and hash joins, if `temp_tablespaces` not configured elsewhere. |

### 2. Diagnosis

From the shell:

```bash
du -sh /var/lib/edb/as16/data/*/
```

From SQL:

```sql
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

In this scenario, `pg_wal/` will likely show **300+ GB**.

### 3. Most Dangerous Cause: Replication Slots

A replication slot tells the primary: "do not delete any WAL segment that the subscriber has not yet consumed."

If the standby goes down and stays down, the primary retains **every WAL file** generated since the standby stopped consuming. There is no automatic limit. WAL grows until the disk fills, writes stop, and the database goes down.

> **This is the single most common cause of unplanned EPAS outages in production.**

Check with:

```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;
```

If the slot shows `active = false` and retained is hundreds of GB - that is your problem.

### 4. Short-Term Fix

Drop the inactive replication slot:

```sql
SELECT pg_drop_replication_slot('standby_slot');
```

WAL files will be cleaned up by the next checkpoint. You will need to rebuild the standby from a fresh base backup later.

### 5. Long-Term Fix

Cap WAL retention per slot (EPAS 13+):

```sql
ALTER SYSTEM SET max_slot_wal_keep_size = '50GB';
SELECT pg_reload_conf();
```

Monitor slot lag with alerting. Never let an inactive slot go unnoticed.

### Oracle Comparison

Oracle uses **online redo logs in a fixed circular buffer**. When a redo log fills, the archiver copies it to the archive log destination, and the redo log is reused. Archive logs can fill a destination, but they never block the redo log circular buffer.

The key difference: EPAS WAL is a **linear sequence** of files retained until no longer needed. Oracle redo is **circular** with archiving as a separate concern.

</details>

---

## Scenario 3: The Crash Recovery

### Context

You manage a busy OLTP EPAS 16 instance processing 5,000 transactions per second. The server's `checkpoint_timeout` is set to `30min` and `checkpoint_completion_target` is `0.9`. The DBA before you set these values to "reduce checkpoint I/O impact."

### The Situation

At 04:30, the data center has a power event. The server loses power ungracefully - no clean shutdown. When power returns 10 minutes later, the server boots and EPAS starts automatically via systemd. You check the logs and see:

```
LOG:  database system was not shut down cleanly; automatic recovery in progress
LOG:  redo starts at 4A/8B000028
LOG:  ...replaying WAL...
```

Recovery takes 45 minutes. During this time, the database does not accept connections. The application is completely down.

### What You Need to Determine

1. What is happening during crash recovery? What data structures are being rebuilt?
2. Why did recovery take 45 minutes? What is the relationship between `checkpoint_timeout` and recovery time?
3. What determines the exact amount of WAL that must be replayed?
4. How would you tune EPAS to guarantee recovery completes in under 5 minutes?
5. What is the Oracle equivalent mechanism, and how does Oracle let you control recovery time?

<details markdown="block">
<summary>Worked Answer</summary>

### 1. What Happens During Crash Recovery

When EPAS starts after an unclean shutdown, it replays WAL from the **last completed checkpoint** forward.

A checkpoint is a point-in-time guarantee that all dirty buffers in `shared_buffers` have been flushed to the data files on disk. Any changes after the last checkpoint exist only in WAL files (and in `shared_buffers`, which were lost when RAM lost power).

The postmaster reads WAL sequentially from the checkpoint's redo point and re-applies every change. During replay, **no client connections are accepted**.

### 2. Why 45 Minutes

With `checkpoint_timeout = 30min`, EPAS checkpoints at most every 30 minutes. Worst case: up to 30 minutes of WAL must be replayed.

At 5,000 TPS, 30 minutes generates a massive volume of WAL - potentially tens of GB. Replaying WAL is I/O-intensive because each record must be applied to the correct page, often requiring random reads.

`checkpoint_completion_target = 0.9` spreads checkpoint writes over 27 minutes (reduces I/O spikes during normal operation) but does nothing to reduce WAL accumulation between checkpoints.

### 3. What Determines Replay Volume

The WAL between the **last completed checkpoint's redo pointer** and the crash point.

> **Critical detail:** If a checkpoint was in progress when power was lost (likely with a 30-minute interval), that incomplete checkpoint does not count. EPAS replays from the *previous* completed checkpoint. Worst-case replay could cover **nearly two full checkpoint intervals**.

### 4. Tuning for Faster Recovery

Reduce `checkpoint_timeout` to cap the replay window:

```sql
ALTER SYSTEM SET checkpoint_timeout = '5min';
ALTER SYSTEM SET max_wal_size = '2GB';
SELECT pg_reload_conf();
```

This caps WAL replay to approximately 5 minutes of transaction volume. More checkpoint I/O, but with `checkpoint_completion_target = 0.9`, it spreads across 4.5 minutes.

Monitor checkpoint frequency:

```sql
SELECT checkpoints_timed, checkpoints_req
FROM pg_stat_bgwriter;
```

### 5. Oracle Comparison

Oracle's equivalent is **instance recovery** (SMON replays online redo logs from the last checkpoint). Oracle provides two features EPAS lacks:

- **MTTR Advisor** - analyzes workload and recommends settings
- **`FAST_START_MTTR_TARGET`** - specify a target recovery time in seconds; Oracle automatically adjusts dirty block write frequency

Oracle's buffer cache tracks dirty buffers in a **checkpoint queue** ordered by first-dirty time, enabling granular control. EPAS has no equivalent - the DBA must manually calculate the checkpoint frequency vs. recovery time trade-off.

</details>

---

## Scenario 4: The Bloated Table

### Context

You are managing an EPAS 16 instance for an e-commerce platform. The `orders` table handles heavy UPDATE traffic - each order goes through states: `pending` -> `processing` -> `shipped` -> `delivered`. The table is updated 50,000 times per hour.

### The Situation

Last month, `pg_total_relation_size('orders')` returned 2 GB. Today it returns 15 GB. But `SELECT count(*) FROM orders` has stayed constant at 4 million rows. Queries that used to run in 200ms are now taking 4 seconds. The Oracle DBA on the team says "just rebuild the table like we do with ALTER TABLE MOVE in Oracle."

### What You Need to Determine

1. What EPAS architectural feature causes tables to grow even when the row count stays the same?
2. Why does this NOT happen in Oracle? What architectural difference prevents it?
3. What is the difference between VACUUM and VACUUM FULL?
4. What specific metrics would you check to confirm this diagnosis?
5. Why is VACUUM FULL dangerous in production, and what alternative exists?

<details markdown="block">
<summary>Worked Answer</summary>

### 1. MVCC and Dead Tuples

EPAS uses **Multi-Version Concurrency Control (MVCC)** where an UPDATE does not modify a row in place. Instead, it:

1. Marks the old row version (tuple) as **dead**
2. Inserts a **new tuple** with the updated values

The dead tuple remains physically in the data file until VACUUM removes it. With 50,000 updates/hour, the table accumulates **1.2 million dead tuples per day**. If autovacuum cannot keep up (table locked by long queries, or settings too conservative), dead tuples pile up and the file grows. This is **table bloat**.

### 2. Why Oracle Is Different

Oracle uses **undo segments** for MVCC:

- UPDATE modifies the row **in place** in the data block
- Before-image is written to an undo segment
- Readers needing the old version reconstruct it from undo
- When undo retention expires, undo space is reused

The table itself **never accumulates dead row versions**. Oracle tables do not experience bloat from UPDATE-heavy workloads the way EPAS tables do.

### 3. VACUUM vs VACUUM FULL

| | VACUUM | VACUUM FULL |
|:--|:-------|:------------|
| **What it does** | Marks dead tuples as reusable free space | Rewrites entire table into a new file |
| **File size after** | Stays 15 GB (space reusable internally) | Shrinks back to ~2 GB |
| **Lock required** | None (runs concurrently) | ACCESS EXCLUSIVE (blocks everything) |
| **Downtime** | Zero | 10-30 min on a 15 GB table |

### 4. Metrics to Check

Check dead tuple count and vacuum history:

```sql
SELECT n_live_tup, n_dead_tup, last_autovacuum, last_vacuum
FROM pg_stat_user_tables
WHERE relname = 'orders';
```

Check for long-running transactions blocking cleanup:

```sql
SELECT pid, xact_start, state
FROM pg_stat_activity
WHERE xact_start < now() - interval '1 hour';
```

If `n_dead_tup` is in the millions and `last_autovacuum` is days ago (or NULL) - autovacuum is not keeping up.

### 5. Why VACUUM FULL Is Dangerous (and What to Use Instead)

VACUUM FULL locks the table exclusively for the entire rewrite. All queries and DML against `orders` are **blocked** - the application hangs.

**Safer alternatives:**

1. **pg_repack** - rebuilds the table online (creates a copy, replays changes via triggers, swaps files). Analogous to Oracle's `DBMS_REDEFINITION`.

2. **Tune autovacuum** to be more aggressive on this specific table:

```sql
ALTER TABLE orders SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_cost_delay = 2
);
```

</details>

---

## Scenario 5: The Split Brain

### Context

You have an EPAS 16 high-availability cluster managed by EDB Failover Manager (EFM):
- **Node A** - primary (10.0.1.10)
- **Node B** - streaming standby (10.0.1.11)
- **Node C** - EFM witness (10.0.1.12)

A virtual IP (VIP) 10.0.1.100 floats to whichever node is the primary.

### The Situation

At 03:00, a network switch failure partitions the network. Node A can still reach clients but cannot reach Node B or Node C. Node B and Node C can reach each other but not Node A. EFM on Node B and Node C form a majority (2 of 3 nodes), determine that Node A is unreachable, and promote Node B to primary. The VIP moves to Node B.

When the network recovers at 03:45, both Node A and Node B believe they are the primary. Node A has been accepting writes from clients that could still reach it directly (bypassing the VIP). Node B has been accepting writes via the VIP. You now have two diverged timelines with 45 minutes of conflicting data.

### What You Need to Determine

1. What architectural mechanism should have prevented Node A from accepting writes after the promotion?
2. What is the role of the witness node in the failover decision?
3. How does Oracle Data Guard handle the equivalent situation (max protection, max availability, max performance)?
4. Why can you NOT simply "merge" the two diverged primaries back together?
5. What is pg_rewind, when would you use it, and what are its limitations?

<details markdown="block">
<summary>Worked Answer</summary>

### 1. Preventing Writes on the Old Primary

EFM is supposed to **fence** the old primary before promoting the standby. Fencing means shutting down PostgreSQL on Node A (or isolating it via STONITH - "shoot the other node in the head") so it cannot accept writes.

In this scenario, fencing **failed** because Node B/C cannot reach Node A over the network. This is the fundamental challenge of split-brain prevention.

**The fix:** Configure EFM with a fencing script that uses an **out-of-band mechanism**:
- IPMI or iLO (hardware-level power control)
- Cloud API (e.g., `aws ec2 stop-instances`)

These work even when the network is partitioned. Without reliable fencing, split brain is always possible.

### 2. Witness Node Role

The witness does not hold data. Its sole purpose is to provide a **quorum vote**.

- 3-node cluster needs 2 votes for majority
- Node B + Node C (2 nodes) = quorum, can safely promote
- Node A alone (1 node) = no quorum, should NOT promote

> **Critical distinction:** Quorum determines WHO gets promoted. It does NOT stop the existing primary from continuing to accept writes. That requires fencing.

### 3. Oracle Data Guard Comparison

Oracle Data Guard offers three protection modes with explicit trade-offs:

| Mode | Behavior | Trade-off |
|:-----|:---------|:----------|
| **Maximum Protection** | Primary crashes rather than commit without standby acknowledgment | Prevents split brain, but risks primary availability |
| **Maximum Availability** | Like max protection, falls back to async if standby unreachable | Balance of safety and availability |
| **Maximum Performance** | Async transport, tolerates data loss | Most common, highest availability |

Oracle also has **Fast-Start Failover (FSFO)** with an Observer process (analogous to EFM's witness). The key advantage: redo transport modes give the DBA explicit control over data protection vs. availability, **integrated into the database engine** rather than as an external tool.

### 4. Why You Cannot Merge Diverged Primaries

Once both nodes accepted independent writes, their **WAL timelines diverged**:

- Node A: writing WAL on **timeline 1**
- Node B: started **timeline 2** at the promotion point

The same data page may have been modified differently on each node. There is no automated way to merge these changes - the database engine does not understand application-level conflict resolution.

### 5. pg_rewind

If you choose Node B as the correct primary, `pg_rewind` resynchronizes Node A as a standby:

1. Reads WAL on both nodes from the divergence point
2. Identifies which pages were modified on Node A after the split
3. Copies the correct page versions from Node B
4. Avoids a full `pg_basebackup` (which could take hours)

**Requirements:**
- `wal_log_hints = on` OR data checksums enabled
- WAL from the divergence point still available on both nodes

**Limitation:** All data written to Node A during the split-brain period is **permanently lost**. If WAL has been recycled, `pg_rewind` cannot work and you must rebuild from scratch.

</details>

---

## Scenario 6: The Memory OOM Kill

### Context

Your EPAS 16 production instance runs on a server with 32 GB RAM. Configuration:
- `shared_buffers = 8GB`
- `work_mem = 256MB`
- `max_connections = 300`
- `maintenance_work_mem = 2GB`

The server runs only EPAS - no other applications.

### The Situation

During peak load at 14:00, the application experiences a total outage lasting 3 minutes. You check the Linux system logs and find:

```
kernel: Out of memory: Killed process 28451 (edb-postgres)
kernel: Out of memory: Killed process 28452 (edb-postgres)
kernel: Out of memory: Killed process 28453 (edb-postgres)
```

The EPAS logs show:

```
LOG:  server process (PID 28451) was terminated by signal 9: Killed
LOG:  terminating any other active server processes
LOG:  all server processes terminated; reinitializing
LOG:  database system was interrupted; last known up at 2026-06-07 13:58:22 UTC
LOG:  database system was not shut down cleanly; automatic recovery in progress
```

Three backend processes were killed, but the entire database went down and performed crash recovery.

### What You Need to Determine

1. Why does one or two dead backend processes cause ALL backends to restart and trigger crash recovery?
2. What shared memory corruption risk exists when a process is killed unexpectedly?
3. Show the math: why does this configuration guarantee OOM on a 32 GB server during peak load?
4. How does Oracle handle the equivalent situation differently (ASMM, PGA_AGGREGATE_TARGET)?
5. What specific tuning changes would you make to prevent this from ever happening again?

<details markdown="block">
<summary>Worked Answer</summary>

### 1. Why All Backends Restart

All backend processes access the same **shared_buffers** segment. When a backend is killed by the OOM killer (signal 9), it may have been in the middle of:

- Modifying a shared buffer page
- Updating a lock table entry
- Writing to the WAL buffer

The postmaster **cannot know** whether shared memory is now corrupted. Rather than risk serving corrupt data, it follows a fail-safe protocol:

1. Terminate ALL remaining backends
2. Perform crash recovery (replay WAL)
3. Only then accept new connections

> **Design principle:** Data integrity is more important than availability. A single corrupted page served to a client causes silent data corruption that propagates through the application.

### 2. Shared Memory Corruption Risk

`shared_buffers` is a pool of 8 KB pages mapped into every backend's address space. If a backend was mid-write when killed:

- **Buffer page**: Partially written content = torn data for other readers
- **WAL buffer**: Partially written WAL record = corrupted recovery chain
- **Lock manager**: Half-updated hash entry = deadlocks or lock leaks

The postmaster cannot inspect every shared memory structure to determine if corruption occurred, so it **assumes the worst**.

### 3. The Math

```
shared_buffers (allocated once):              8 GB
work_mem (per sort, per backend):
  100 backends x 256 MB =                   25 GB
OS needs:                                     3 GB
maintenance_work_mem (autovacuum):
  3 workers x 2 GB =                         6 GB
                                          --------
TOTAL:                                       42 GB  ← on a 32 GB server
```

`work_mem = 256 MB` is per-sort-operation per-backend. A single complex query with 4 sort/hash nodes uses **1 GB**. The Linux OOM killer selects the largest processes - EPAS backends with big sort allocations.

### 4. Oracle Comparison

Oracle has **built-in memory governors** that EPAS lacks:

- **ASMM** (Automatic Shared Memory Management) - manages the SGA as a single controlled allocation
- **`PGA_AGGREGATE_TARGET`** - sets a global cap on total process memory across all sessions

If a session needs sort memory beyond its allocation, Oracle **spills to a temp tablespace** on disk rather than consuming more RAM. Total memory stays within planned limits.

EPAS has no equivalent global cap. Each backend independently allocates `work_mem` without coordination, making the total **unpredictable**.

### 5. Tuning Changes

| Change | Why |
|:-------|:----|
| `work_mem = '16MB'` (global), `SET work_mem = '256MB'` per-session when needed | Prevents uncontrolled memory growth |
| `max_connections = 150` + PgBouncer | Fewer backends = less total memory |
| `maintenance_work_mem = '512MB'` | Reduces autovacuum memory footprint |
| `vm.overcommit_memory = 2`, `vm.overcommit_ratio = 80` | Kernel refuses allocations exceeding physical RAM instead of killing later |
| `huge_pages = on` | Makes shared_buffers non-swappable and exempt from OOM scoring |

</details>

---

## Key Takeaways

1. **Process-per-connection** is the single biggest architectural difference between EPAS and Oracle that impacts day-to-day operations. Connection pooling is not optional in production - it is a requirement.

2. **WAL is linear, not circular.** Unlike Oracle's fixed-size redo log groups, WAL files accumulate. Replication slots, archive failures, and long-running transactions can cause unbounded WAL growth. Monitor WAL directory size and replication slot lag aggressively.

3. **Checkpoints control recovery time.** There is no MTTR advisor - you must understand the relationship between `checkpoint_timeout`, WAL volume, and crash recovery duration and tune it manually.

4. **MVCC bloat is a feature, not a bug.** Oracle hides old row versions in undo segments. EPAS keeps them in the table itself. This means VACUUM is not optional - it is as critical as RMAN backups in Oracle. A failed autovacuum leads to bloat, which leads to performance degradation, which leads to outages.

5. **Shared memory makes failure contagious.** One crashed backend takes down all backends. Oracle has the same shared memory model (SGA), but Oracle's memory management (ASMM, PGA_AGGREGATE_TARGET) provides built-in governors that EPAS lacks. You must calculate and cap memory usage manually.

6. **Split brain prevention requires fencing.** Quorum voting (via a witness node) determines WHO gets promoted, but it does not stop the old primary from accepting writes. Reliable fencing - preferably via out-of-band mechanisms like IPMI or cloud APIs - is mandatory for production HA.
