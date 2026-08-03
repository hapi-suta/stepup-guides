---
layout: default
title: "Interview 01 - Architecture Discussion Points"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 8
locked: "no"
---

# Interview 01 - Architecture Discussion Points

## Purpose

These 15 questions represent what you will face in Senior/Lead DBA interviews at companies running EDB Postgres Advanced Server (EPAS). Every question is designed to test whether you truly understand EPAS internals or are just reciting documentation. The answers reference Oracle parallels because most EPAS shops are Oracle migration environments - interviewers expect you to speak both languages fluently. Study the strong answers, but internalize the reasoning rather than memorizing words. A good interviewer will ask follow-ups that only someone with real understanding can handle.

---

## Architecture Fundamentals

### Question 1: Walk me through what happens when a client sends a SELECT to EPAS

**What they are really asking:** Can you trace a query through all the architectural layers - from network to disk - and name the specific EPAS components involved at each stage?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

The client connects to the postmaster process on port 5444 (EPAS default). The postmaster forks a new backend process dedicated to this client. Authentication happens first - the backend checks pg_hba.conf to determine the auth method (md5, scram-sha-256, ldap, etc.), then validates credentials against pg_authid.

Once authenticated, the client sends the SELECT as a simple query protocol message. The backend's parser converts the SQL text into a parse tree. The analyzer/rewriter resolves table and column names against the system catalogs (pg_class, pg_attribute), applies any view definitions or rules, and produces a query tree. The planner/optimizer then generates candidate execution plans - sequential scan, index scan, bitmap scan, nested loop join, hash join, merge join - and costs each one using statistics from pg_statistic. It picks the lowest-cost plan.

The executor runs the plan. For data access, it first checks shared_buffers (EPAS's buffer cache, analogous to Oracle's buffer cache in the SGA). If the page is not in shared_buffers, it reads the 8 KB page from disk (or OS page cache) into a shared buffer. EPAS uses a clock-sweep eviction algorithm, not LRU like Oracle. The executor applies visibility checks using MVCC - it reads the tuple's xmin/xmax transaction IDs and checks them against the current snapshot (pg_xact / CLOG) to determine if the tuple is visible to this transaction.

Results are sent back through the backend to the client over the libpq protocol. No WAL is written for a pure SELECT (unlike Oracle, which writes redo even for consistent reads when generating undo). The backend process remains alive, waiting for the next command from this client.

In EPAS specifically, if the query uses Oracle-compatible syntax (CONNECT BY, packages, etc.), the parser handles these through EDB's extended parser before the standard planning stage.
</details>

**Red flags:** Saying "it goes to the optimizer and returns results" without mentioning shared_buffers, MVCC visibility, or the postmaster fork. Confusing EPAS's process-per-connection model with Oracle's shared server architecture.

---

### Question 2: Explain the VACUUM architecture and why Oracle doesn't need it

**What they are really asking:** Do you understand MVCC tuple versioning deeply enough to explain why VACUUM exists as a fundamental architectural consequence, not just a maintenance task?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

EPAS (and PostgreSQL) uses multi-version concurrency control where UPDATE creates a new tuple version in the same table and marks the old version's xmax with the updating transaction ID. DELETE marks the tuple's xmax but does not remove it. These dead tuples accumulate in the table's data pages, consuming disk space and making sequential scans slower because the executor must read and skip them.

VACUUM's job is to reclaim this space. Standard VACUUM marks dead tuples as free space in the Free Space Map (FSM) so future INSERTs can reuse those slots, but it does not shrink the physical file. VACUUM FULL rewrites the entire table, removing all dead space, but takes an ACCESS EXCLUSIVE lock - you cannot use it in production without downtime.

VACUUM also freezes old transaction IDs to prevent wraparound. EPAS uses 32-bit transaction IDs (about 4.2 billion). When the counter approaches wraparound, transactions that have not been frozen become invisible. Autovacuum's anti-wraparound mode forces aggressive vacuuming when a table approaches `autovacuum_freeze_max_age` (default 200 million transactions). If this fails - for example, because a long-running transaction holds back the oldest visible transaction ID - the database eventually enters "wraparound protection" mode and refuses all new transactions. This is a critical production failure unique to PostgreSQL/EPAS.

Oracle does not need VACUUM because it uses a fundamentally different MVCC implementation. Oracle stores only the current version of a row in the data block. When a row is modified, Oracle writes the old version to an undo segment (rollback segment). Readers needing the old version reconstruct it from undo on the fly. The undo is circular and automatically overwritten after the undo_retention period. There is no accumulation of dead tuples in the data blocks. The tradeoff is "ORA-01555: snapshot too old" - if undo is overwritten before a long-running query finishes reading it, the query fails. EPAS never has this problem because old tuple versions persist until VACUUM removes them.

Operationally, this means EPAS DBAs must monitor autovacuum closely - check `pg_stat_user_tables.n_dead_tup`, watch for autovacuum workers being saturated, tune `autovacuum_vacuum_cost_delay` and `autovacuum_vacuum_scale_factor` per table for high-churn tables.
</details>

**Red flags:** Saying "VACUUM is like Oracle's DBMS_STATS" (it is not - that is ANALYZE). Saying VACUUM FULL is safe to run in production without mentioning the exclusive lock.

---

### Question 3: Describe EPAS's WAL architecture and compare it to Oracle redo

**What they are really asking:** Can you explain WAL's role in crash recovery, replication, and PITR, and articulate the specific differences from Oracle's redo/undo architecture?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

WAL (Write-Ahead Logging) is EPAS's durability guarantee. Before any data page modification is flushed to disk, the corresponding WAL record must be flushed first. WAL records are written sequentially to 16 MB segment files in `pg_wal/`. The WAL writer process flushes WAL buffers (in shared memory, sized by `wal_buffers`) to disk periodically, and backends force-flush when they commit (unless `synchronous_commit = off`).

WAL serves three purposes: crash recovery (replay from last checkpoint), streaming replication (ship WAL to standbys via walsender/walreceiver), and point-in-time recovery (archive WAL segments to restore to any arbitrary point).

Checkpoints are triggered by `checkpoint_timeout` (default 5 minutes) or `max_wal_size` (default 1 GB). During a checkpoint, the checkpointer process flushes all dirty buffers to disk and writes the checkpoint location to pg_control. After a crash, recovery starts from the last checkpoint's REDO location and replays all WAL forward.

Compared to Oracle: Oracle separates redo logs (online redo logs, archived redo logs) from undo (undo tablespace). WAL combines both functions - it logs both the new and old page images (when full_page_writes is on after a checkpoint). Oracle uses a circular set of online redo log groups that are overwritten after archiving. EPAS uses a flat directory of WAL segments that are recycled after archiving and checkpointing.

Oracle's LGWR writes redo continuously; EPAS's WAL writer does the same. But Oracle's redo contains only the change vectors (before and after images of specific bytes), while EPAS WAL records include full 8 KB page images after each checkpoint (full_page_writes). This makes EPAS WAL volumes larger than Oracle redo for the same workload, but eliminates the risk of partial page writes (torn pages).

One operational difference: Oracle redo log switches trigger alerts and can stall the database if archiving cannot keep up. EPAS has the same behavior - if archive_command fails, pg_wal fills up and the database eventually stops. But EPAS does not have the concept of redo log groups or multiplexed redo members. If you want WAL redundancy, you use a mirrored filesystem.
</details>

**Red flags:** Not knowing that WAL serves replication and PITR in addition to crash recovery. Confusing WAL with logical decoding or saying WAL is "like Oracle Data Guard" (Data Guard is the replication system; redo is the log format).

---

### Question 4: What happens if the postmaster process is killed?

**What they are really asking:** Do you understand the EPAS process hierarchy and the cascading consequences of losing the parent process?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

The postmaster is the root of the EPAS process tree. Every backend, autovacuum worker, WAL writer, checkpointer, bgwriter, archiver, stats collector, and logical replication worker is a child of the postmaster. If the postmaster is killed, all child processes are orphaned and will terminate.

The specific behavior depends on how the postmaster is killed. With `pg_ctl stop -m fast` (SIGTERM), the postmaster sends SIGTERM to all backends, waits for them to finish current queries and disconnect, writes a clean checkpoint, updates pg_control to "shut down" state, and exits cleanly. With `pg_ctl stop -m immediate` (SIGQUIT), the postmaster sends SIGQUIT to all children, which abort immediately. No checkpoint is performed. On next startup, crash recovery replays WAL from the last checkpoint - this is safe but takes time proportional to the amount of WAL since the last checkpoint.

With `kill -9` (SIGKILL), the worst case: the postmaster has no chance to signal children or perform cleanup. Children are orphaned (re-parented to PID 1 by the OS and eventually killed). Shared memory may be left in an inconsistent state. The `postmaster.pid` file is not removed. If a checkpoint was in progress when the SIGKILL landed, pg_control could be partially written, corrupting it. On next startup, you may see `PANIC: could not locate a valid checkpoint record`, requiring pg_resetwal as a last resort.

This is fundamentally different from Oracle. In Oracle, killing the PMON or SMON background process triggers instance recovery, but the Oracle kernel (the single multi-threaded process, or on Linux the set of threads) is more resilient to individual process loss. Oracle can restart background processes independently. In EPAS, the postmaster is a single point of failure for the entire instance - losing it means losing everything.

Operationally, you should never allow anyone to run `kill -9` on the postmaster. If systemd manages the service, configure `Restart=on-failure` with `RestartSec=5s` to auto-restart after crashes.
</details>

**Red flags:** Saying "just restart it, no big deal" without mentioning crash recovery, pg_control corruption risk, or shared memory cleanup. Not knowing the difference between SIGTERM, SIGQUIT, and SIGKILL.

---

### Question 5: How would you size shared_buffers and work_mem for a 128 GB RAM server with 500 concurrent connections?

**What they are really asking:** Can you reason about memory allocation in EPAS without blindly applying the "25% of RAM" rule, and do you understand the relationship between shared and per-backend memory?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

Start with the memory budget. Of 128 GB, the OS needs about 2-4 GB, leaving ~124 GB for EPAS and OS page cache.

For shared_buffers, the common starting point is 25% of RAM - so 32 GB. But this is a starting point, not a rule. shared_buffers is a fixed allocation of shared memory used as EPAS's buffer cache. Unlike Oracle's SGA, EPAS relies heavily on the OS page cache as a second-level cache. Setting shared_buffers too high (say 96 GB) actually hurts performance because you get double-caching - the same page sits in both shared_buffers and the OS page cache - and the clock-sweep replacement algorithm in shared_buffers is less sophisticated than the OS's LRU. For a 128 GB server, I would start at 32 GB and benchmark up to 40 GB, watching `pg_stat_bgwriter` for `buffers_alloc` growth rate and cache hit ratios.

For work_mem, this is where people get into trouble. work_mem is allocated per-sort-operation, not per-connection. A single complex query with 5 sort/hash operations could allocate 5 times work_mem. With 500 connections, worst case memory from sorts alone: 500 connections x 3 sorts average x work_mem. If work_mem = 64 MB, that is 500 x 3 x 64 MB = 96 GB - far more than available. This would cause massive swapping.

For 500 connections, I would set work_mem = 8-16 MB at the global level, then use `SET LOCAL work_mem = '256MB'` for specific reporting queries or ETL sessions that need large sorts. Or better yet, reduce the actual backend count to 50-100 using PgBouncer and set work_mem = 64 MB with the lower connection count.

Other per-backend parameters: temp_buffers (default 8 MB, used for temporary tables), maintenance_work_mem (for VACUUM, CREATE INDEX - set to 1-2 GB, shared across autovacuum workers via autovacuum_work_mem).

The practical answer: 500 direct connections to EPAS is a red flag. Deploy PgBouncer in transaction mode with default_pool_size = 50-100, then you are sizing for 100 backends, not 500. With 100 backends: shared_buffers = 32 GB, work_mem = 64 MB, effective_cache_size = 96 GB (tells the planner how much total cache to expect), maintenance_work_mem = 2 GB.
</details>

**Red flags:** Saying "shared_buffers should be 25% of RAM" without explaining why or acknowledging that it depends on workload and connection count. Setting work_mem = 1 GB "because we have lots of RAM" without calculating the per-connection multiplier.

---

## Oracle to EPAS Migration

### Question 6: Why would you choose EPAS over vanilla PostgreSQL for an Oracle migration?

**What they are really asking:** Do you know the specific Oracle-compatible features EPAS provides and can you articulate the business case beyond "it is compatible"?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

EPAS provides Oracle compatibility features that dramatically reduce migration effort and risk. The concrete features that matter most:

**PL/SQL compatibility.** EPAS runs Oracle PL/SQL packages, stored procedures, and functions with minimal changes. This includes `%TYPE` and `%ROWTYPE` declarations, `FORALL` bulk operations, exception handling with named exceptions (NO_DATA_FOUND, TOO_MANY_ROWS), autonomous transactions (`PRAGMA AUTONOMOUS_TRANSACTION`), and the `DBMS_OUTPUT`, `DBMS_SQL`, `DBMS_LOB`, `UTL_FILE`, `UTL_MAIL`, `UTL_HTTP` packages. Vanilla PostgreSQL has PL/pgSQL, which is syntactically different - every PL/SQL procedure would need rewriting.

**SQL syntax compatibility.** EPAS supports Oracle SQL syntax: `CONNECT BY` for hierarchical queries (vanilla PostgreSQL uses `WITH RECURSIVE`), `DECODE()`, `NVL()`, `NVL2()`, `MINUS` (instead of `EXCEPT`), outer join syntax with `(+)`, `ROWNUM`, dual table, `SYSDATE`, and `MERGE` (DML). These are high-frequency constructs in Oracle codebases.

**Data dictionary compatibility.** EPAS provides `ALL_TABLES`, `ALL_TAB_COLUMNS`, `ALL_INDEXES`, `ALL_CONSTRAINTS`, `USER_*`, `DBA_*` views that Oracle DBAs and monitoring tools expect. This means existing monitoring scripts and ORM configurations often work without changes.

**Tooling.** EDB provides the Migration Toolkit (MTK) for schema and data migration, EDB Failover Manager (EFM) for HA, PEM (Postgres Enterprise Manager) for monitoring with an Oracle Enterprise Manager-like interface, and Backup and Recovery Tool (BART) for enterprise backups.

The business case: a typical Oracle-to-vanilla-PostgreSQL migration requires 6-18 months of PL/SQL rewriting. With EPAS, you can often migrate stored procedures with less than 10% code changes, reducing the project to 2-6 months. For a company with 500,000 lines of PL/SQL, that difference is millions of dollars in developer time and months of risk.

Where EPAS is not the right choice: if the application has no stored procedures, uses only standard SQL, and the team prefers community PostgreSQL, then vanilla PostgreSQL is fine. EPAS adds licensing cost ($5,000-$15,000 per core per year depending on the plan), so the Oracle compatibility features need to justify that cost.
</details>

**Red flags:** Saying "EPAS is just PostgreSQL with a different name." Not knowing specific compatibility features (packages, CONNECT BY, DBMS_* packages). Not mentioning the cost tradeoff.

---

### Question 7: What is the biggest operational gotcha when moving from Oracle to EPAS?

**What they are really asking:** Have you actually done this migration, or are you just reading the marketing materials?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

The biggest operational gotcha is VACUUM and autovacuum management. Oracle DBAs coming to EPAS have never had to think about dead tuple cleanup because Oracle's undo architecture handles this transparently. In EPAS, if autovacuum falls behind on a high-transaction table - and it will, because the defaults are too conservative for most production workloads - you get table bloat, index bloat, degraded query performance, and eventually transaction ID wraparound risk.

I have seen this pattern repeatedly: the migration goes smoothly, the application works, performance testing passes, and then 3-6 months into production, a critical table has grown from 10 GB to 80 GB because autovacuum could not keep up with the UPDATE rate. The Oracle DBA did not know to monitor `n_dead_tup` in `pg_stat_user_tables` or to tune `autovacuum_vacuum_scale_factor` down from the default 0.2 (20% of the table must be dead before autovacuum triggers) to 0.01 or even set a fixed `autovacuum_vacuum_threshold` for high-churn tables.

Second gotcha: connection management. Oracle handles 2,000 connections natively with shared server mode. EPAS with 2,000 direct connections will consume 20+ GB of RAM just for backend processes and degrade under ProcArrayLock contention. You must deploy PgBouncer, and you must redesign connection strings, which means application changes the migration plan did not account for.

Third gotcha: sequence behavior. Oracle sequences have a cache (default 20) and do not guarantee gap-free numbering. EPAS sequences also cache, but the `nextval()` function behaves differently in error scenarios - a rolled-back transaction in EPAS still consumes the sequence value. Oracle DBAs who rely on sequence values for audit continuity get surprised.

Fourth: the lack of `ALTER SESSION SET NLS_DATE_FORMAT`. Oracle date formatting is session-level. In EPAS, you use `datestyle`, `SET search_path`, and type casting differently. Implicit date-to-string conversions that worked in Oracle may produce different formats in EPAS.
</details>

**Red flags:** Saying "there are no gotchas, EPAS is compatible." Focusing only on syntax differences rather than operational differences. Not mentioning VACUUM at all.

---

### Question 8: How does EPAS authentication (pg_hba.conf) compare to Oracle TNS?

**What they are really asking:** Do you understand the fundamental difference in how EPAS and Oracle handle client-to-server connectivity and can you configure both?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

Oracle and EPAS take completely different approaches. Oracle uses a client-side configuration model: the client has a `tnsnames.ora` file that maps service names to host:port/service_name, and the server has a `listener.ora` that configures the TNS Listener (comparable to the EPAS postmaster's listening function). Authentication itself is handled by the database - the listener just brokers the connection.

EPAS uses a server-side access control model through `pg_hba.conf` (Host-Based Authentication). This file is evaluated top-to-bottom for every connection attempt, and the first matching rule wins. Each rule specifies: connection type (local/host/hostssl/hostnossl), database name, username, client IP range (CIDR), and authentication method (trust, reject, md5, scram-sha-256, cert, ldap, gss, pam, radius).

The key architectural difference: Oracle has no equivalent to pg_hba.conf. In Oracle, if you can reach the listener and have valid credentials, you can connect to any database the listener serves. In EPAS, even with valid credentials, if pg_hba.conf does not have a matching rule for your IP + database + username combination, you are rejected. This is actually a stronger security model because it provides network-layer access control at the database level.

Practical example of a common pg_hba.conf:

```
# Local connections via Unix socket
local   all   enterprisedb   peer
local   all   all            scram-sha-256

# Application servers via SSL only
hostssl production  app_service  10.0.1.0/24  scram-sha-256

# Replication connections
hostssl replication  replicator   10.0.2.0/24  scram-sha-256

# Reject everything else
host    all   all   0.0.0.0/0   reject
```

One gotcha Oracle DBAs hit: editing pg_hba.conf but forgetting to reload (`SELECT pg_reload_conf()` or `pg_ctl reload`). The file is only read at startup or reload, not on every connection. And the most common debugging frustration: a broad rule earlier in the file matching before a specific rule later - since it is first-match-wins, order matters critically.

EPAS also supports `pg_ident.conf` for mapping OS usernames to database usernames, which has no direct Oracle equivalent. And EPAS can integrate with the same LDAP/Kerberos infrastructure Oracle uses, but the configuration syntax is completely different.
</details>

**Red flags:** Saying pg_hba.conf and tnsnames.ora serve the same purpose (they do not - one is server-side access control, the other is client-side connection configuration). Not knowing that pg_hba.conf is first-match-wins.

---

### Question 9: How does EPAS handle crash recovery differently from Oracle?

**What they are really asking:** Do you understand the checkpoint/WAL replay mechanism and how EPAS's single-pass recovery differs from Oracle's two-phase (redo then undo) approach?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

EPAS crash recovery is a single forward pass: replay WAL from the last completed checkpoint to the end of WAL. There is no separate "undo" phase like Oracle.

When EPAS starts after a crash, the startup process reads pg_control to find the last checkpoint's REDO location. It then sequentially reads and replays every WAL record from that point forward. Each WAL record describes a physical change to a data page - it is applied idempotently (safe to apply multiple times). If `full_page_writes = on` (the default), the first WAL record for each page after a checkpoint contains the full 8 KB page image, so even a torn page write is recoverable. After all WAL is replayed, the database is consistent and opens for connections.

What about uncommitted transactions? EPAS does not need to roll them back explicitly. Because EPAS uses MVCC with transaction status stored in pg_xact (CLOG), an uncommitted transaction's ID is simply marked as "in progress" or "aborted" in the CLOG. When subsequent queries check tuple visibility, they see these transaction IDs and treat the tuples as invisible. The dead tuples from aborted transactions are cleaned up later by VACUUM. This is fundamentally different from Oracle's approach.

Oracle crash recovery (SMON instance recovery) has two phases. Phase 1 (rolling forward): SMON replays online redo logs from the last checkpoint, restoring all committed and uncommitted changes to the data files. Phase 2 (rolling back): SMON uses undo segments to roll back any uncommitted transactions, physically removing their changes from the data blocks. This second phase can take significant time on a busy system - I have seen Oracle undo recovery take 30+ minutes after a crash during heavy batch processing. EPAS does not have this phase at all.

The practical impact: EPAS crash recovery time is proportional to the amount of WAL since the last checkpoint. If `checkpoint_timeout = 5min` and `max_wal_size = 2GB`, recovery typically takes seconds to a few minutes. You can tune this tradeoff - shorter checkpoint intervals mean faster recovery but more I/O during normal operations.

One important EPAS-specific detail: unlogged tables (`CREATE UNLOGGED TABLE`) skip WAL entirely. After a crash, they are truncated to zero rows. Oracle has no direct equivalent - the closest is `NOLOGGING` mode, but Oracle NOLOGGING tables still retain their data after a local crash (they only lose data if you restore from backup without applying redo).
</details>

**Red flags:** Saying EPAS has a rollback phase during crash recovery (it does not). Not mentioning pg_control or checkpoints. Confusing crash recovery with PITR.

---

### Question 10: Walk me through how you would migrate a 500 GB Oracle 19c database with 200 PL/SQL packages to EPAS 16

**What they are really asking:** Can you plan an end-to-end migration with realistic timelines and risk mitigation, not just run a tool?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

I would structure this as a 4-phase project spanning 12-16 weeks.

**Phase 1 - Assessment (weeks 1-3).** Run EDB's Migration Assessment Tool and Oracle's AWR/ADDM reports to inventory: schema objects (tables, indexes, views, materialized views, sequences, synonyms, types), PL/SQL code volume (200 packages = likely 50,000-200,000 lines), Oracle-specific features used (partitioning, advanced queuing, spatial, XMLType, RAC-specific code, database links, scheduler jobs, flashback), and workload profile (OLTP vs batch, peak TPS, data growth rate). I would flag any showstoppers early - things like Oracle Advanced Queuing that have no EPAS equivalent and need application redesign.

**Phase 2 - Schema and Code Migration (weeks 4-8).** Use EDB Migration Toolkit (MTK) to migrate the schema. MTK handles table DDL, indexes, constraints, sequences, and most PL/SQL automatically. For the 200 packages, I expect about 80% to migrate with minor changes (replacing Oracle-specific syntax like `DBMS_APPLICATION_INFO`, `UTL_FILE` path differences, bulk collect nuances). The remaining 20% will need manual rewriting - typically packages using advanced Oracle features like pipelined functions, object types with member methods, or edition-based redefinition. Each package gets a unit test before and after migration.

**Phase 3 - Data Migration and Performance Validation (weeks 9-12).** For 500 GB, I would use MTK for the initial data load (parallel threads, batch commits). Expected load time: 4-8 hours depending on network and disk. Then run `ANALYZE` on all tables to generate optimizer statistics. Performance validation: replay the production workload using a captured trace or synthetic load. Compare query plans with Oracle's. The most common performance issues: missing Oracle-specific hints (EPAS uses `pg_hint_plan` extension), hash join vs nested loop differences, and composite index column order assumptions. Tune `random_page_cost`, `effective_cache_size`, `work_mem`, and create any missing indexes.

**Phase 4 - Cutover (weeks 13-16).** Set up ongoing replication from Oracle to EPAS using EDB's Replication Server or a CDC tool (Debezium, GoldenGate) for the cutover window. Run parallel operations for 2-4 weeks: application writes to Oracle, data replicates to EPAS, read traffic gradually shifted to EPAS. On cutover night: stop application writes to Oracle, verify replication lag is zero, switch application connection strings to EPAS, validate with smoke tests, monitor for 4 hours, then decommission Oracle read traffic.

Key risk mitigations: always have a rollback plan (keep Oracle running for 2 weeks post-cutover), test VACUUM performance on the highest-churn tables during parallel run, and deploy PgBouncer from day one.
</details>

**Red flags:** Saying "just run MTK and it handles everything." Estimating less than 8 weeks for a 500 GB / 200 package migration. Not mentioning performance validation or rollback planning.

---

## Production Operations

### Question 11: How would you diagnose a sudden 10x increase in query latency on an EPAS primary?

**What they are really asking:** Do you have a systematic troubleshooting methodology, or do you just restart the database and hope?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

I follow a top-down diagnostic approach, starting with the broadest indicators and narrowing down.

**Step 1 - Check system resources (30 seconds).** Run `top`, `vmstat 1 5`, `iostat -x 1 5`. Look for: CPU saturation (>90% user+system), I/O wait (>20%), swap usage (any swap activity is a red flag in EPAS), disk latency (await > 10ms on SSD). If the server is swapping, that is your answer - find what is consuming memory.

**Step 2 - Check EPAS wait events (1 minute).** Query `pg_stat_activity`:

```sql
SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity WHERE state = 'active'
GROUP BY 1, 2 ORDER BY 3 DESC;
```

Common findings: `Lock/transactionid` means lock contention (someone is blocking). `LWLock/WALWriteLock` means WAL is bottlenecked (check disk speed for pg_wal). `IO/DataFileRead` means too many cache misses (shared_buffers may be too small, or a query is doing sequential scans on large tables). `Client/ClientRead` means backends are waiting for the application to send data - not a database problem.

**Step 3 - Find the problem queries (2 minutes).** Check `pg_stat_statements` (must be enabled):

```sql
SELECT query, calls, mean_exec_time, stddev_exec_time,
       rows, shared_blks_hit, shared_blks_read
FROM pg_stat_statements
ORDER BY mean_exec_time DESC LIMIT 10;
```

If mean_exec_time recently spiked for a specific query, check its plan with `EXPLAIN (ANALYZE, BUFFERS)`. Common causes: stale statistics (run `ANALYZE`), index was dropped or corrupted, table bloat causing sequential scan to take longer, new data distribution making the planner choose a different join strategy.

**Step 4 - Check for bloat and autovacuum issues.**

```sql
SELECT relname, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 100000 ORDER BY n_dead_tup DESC;
```

If a table has millions of dead tuples and autovacuum has not run recently, that table is bloated and scans are slow. Check if autovacuum is blocked by a long-running transaction:

```sql
SELECT pid, xact_start, state, query
FROM pg_stat_activity
WHERE xact_start < now() - interval '1 hour';
```

**Step 5 - Check for checkpoint storms.** If `checkpoint_timeout` is too short or `max_wal_size` too small, frequent checkpoints cause I/O spikes. Check the PostgreSQL log for `LOG: checkpoint starting: time` vs `LOG: checkpoint starting: wal` - the latter means WAL volume is forcing checkpoints faster than the timeout.

This entire diagnostic takes under 5 minutes and covers 95% of performance issues.
</details>

**Red flags:** Starting with "restart the service" as the first step. Not mentioning pg_stat_activity or pg_stat_statements. Blaming the network without checking database internals first.

---

### Question 12: Walk me through a failover scenario with EFM

**What they are really asking:** Have you actually configured and tested EFM, and do you understand the split-brain risks and fencing requirements?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

EDB Failover Manager (EFM) runs as an agent on each node in the cluster - primary, standby(s), and an optional witness node. Each agent monitors the local EPAS instance and communicates with peer agents over a dedicated network (typically a separate interface or VLAN).

**Normal state:** The primary agent checks local EPAS health every `node.timeout` seconds (default 10). It monitors: can it connect to the local database, is the database accepting writes, is replication to standbys healthy. Standby agents verify they are in recovery mode and streaming from the primary.

**Failure detection:** When the primary agent cannot reach the local EPAS instance (or the primary agent itself stops responding), the standby agents begin a consensus process. The `standby.timeout` parameter controls how long they wait before declaring the primary dead (default 30 seconds). The witness node breaks ties - if only one standby can reach the witness, it has quorum and can proceed with failover.

**Failover execution:** EFM selects the best standby (based on `recovery_target_timeline`, LSN position, and priority settings). The selected standby runs `pg_ctl promote` (or touches the trigger file). EFM then executes three critical actions: (1) moves the virtual IP to the new primary using the `virtual.ip.interface` and `virtual.ip.prefix` settings, (2) runs the `script.fence` command on the old primary to prevent split-brain - this script should stop EPAS, remove the VIP, and ideally power-fence the old primary via IPMI/iLO/cloud API, (3) runs `script.post.promotion` for any custom actions (update DNS, notify monitoring, reconfigure PgBouncer).

**Split-brain prevention is critical.** If the old primary is not properly fenced - for example, it was just network-partitioned, not actually down - you end up with two writable databases. EFM's fencing script must be aggressive: stop EPAS on the old primary, remove the VIP, and ideally shut down the node entirely. In cloud environments, I use the cloud API to stop the instance.

**Post-failover recovery.** The old primary cannot rejoin as a standby directly (its timeline has diverged). You either rebuild it with `pg_basebackup` or use `pg_rewind` (if `wal_log_hints = on` or data checksums are enabled) to rewind it to the point of divergence and attach it as a standby.

Compared to Oracle Data Guard: EFM is simpler (no broker configuration repository, no DGMGRL). Oracle Data Guard has built-in fast-start failover (FSFO) with an observer process - similar to EFM's witness. But Oracle Data Guard also provides switchover (graceful role change) natively, while EFM switchover requires more manual steps.
</details>

**Red flags:** Not mentioning fencing or split-brain risk. Saying "EFM handles everything automatically" without describing the consensus mechanism. Not knowing that the old primary needs pg_rewind or rebuild to rejoin.

---

### Question 13: You need to add a column to a 2 TB table in EPAS with zero downtime. How?

**What they are really asking:** Do you understand which DDL operations take heavy locks in EPAS and how to work around them?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

The answer depends entirely on what kind of column you are adding.

**Best case: nullable column with no default (or a non-volatile default in PG 11+/EPAS 11+).** Since PostgreSQL 11, `ALTER TABLE ADD COLUMN` with a constant default value is a metadata-only operation - it does not rewrite the table. It takes an `ACCESS EXCLUSIVE` lock, but only for milliseconds (to update the catalog). For a 2 TB table:

```sql
ALTER TABLE big_table ADD COLUMN new_col integer DEFAULT 0;
```

This is instant regardless of table size. The default value is stored in `pg_attrdef` and returned dynamically for existing rows. New inserts physically write the value.

**However,** the ACCESS EXCLUSIVE lock can still block if there are long-running queries or transactions holding conflicting locks on the table. Before running the ALTER, check for blockers:

```sql
SELECT pid, query, state, xact_start
FROM pg_stat_activity
WHERE pid IN (
  SELECT pid FROM pg_locks WHERE relation = 'big_table'::regclass
);
```

Use `lock_timeout` to avoid queuing indefinitely:

```sql
SET lock_timeout = '5s';
ALTER TABLE big_table ADD COLUMN new_col integer DEFAULT 0;
```

If it times out, retry during lower traffic.

**Bad case: column with a volatile default or a NOT NULL constraint on existing data.** Adding a column with `DEFAULT now()` (volatile) in older EPAS versions, or adding a NOT NULL constraint that must validate all existing rows, requires a full table scan or rewrite. For 2 TB, that means hours of ACCESS EXCLUSIVE lock.

Workaround for NOT NULL: add the column as nullable, backfill in batches, then add the constraint:

```sql
-- Step 1: instant metadata-only operation
ALTER TABLE big_table ADD COLUMN new_col integer;

-- Step 2: backfill in batches of 10,000 to avoid long locks
DO $$
DECLARE batch_start bigint := 0; batch_size bigint := 10000;
BEGIN
  LOOP
    UPDATE big_table SET new_col = 0
    WHERE id BETWEEN batch_start AND batch_start + batch_size - 1
      AND new_col IS NULL;
    IF NOT FOUND THEN EXIT; END IF;
    batch_start := batch_start + batch_size;
    COMMIT;
  END LOOP;
END $$;

-- Step 3: add NOT NULL with validation (scans table but no rewrite)
ALTER TABLE big_table ALTER COLUMN new_col SET NOT NULL;
```

For even less impact, use `ALTER TABLE ... ADD CONSTRAINT ... NOT VALID` followed by `ALTER TABLE ... VALIDATE CONSTRAINT` in a separate transaction - the validation takes only a SHARE UPDATE EXCLUSIVE lock, which does not block reads or writes.

**Oracle comparison:** Oracle's online DDL (`ALTER TABLE ADD COLUMN ONLINE`) has been available since 12c for most operations. Oracle handles this more gracefully because it can use supplemental logging to track changes during the DDL. EPAS does not have online DDL for table rewrites - you need workarounds like the batch approach or extensions like pg_repack for index rebuilds.
</details>

**Red flags:** Saying `ALTER TABLE ADD COLUMN` always rewrites the table (it has not since PG 11). Not knowing about lock_timeout. Proposing `VACUUM FULL` or `pg_repack` for a simple ADD COLUMN.

---

### Question 14: Describe how you would set up monitoring for a production EPAS cluster

**What they are really asking:** Do you know what metrics actually matter for EPAS, beyond just "CPU and disk"?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

I structure EPAS monitoring in four tiers: system, instance, query, and replication.

**Tier 1 - System metrics (OS level).** CPU utilization, I/O wait, disk throughput and latency (separately for data, WAL, and temp tablespace volumes), memory usage (specifically RSS of all EPAS backends), swap activity (any swap = investigate immediately), network throughput between primary and standbys. Tools: node_exporter + Prometheus, or CloudWatch on AWS.

**Tier 2 - Instance metrics (database level).** These are the EPAS-specific metrics that matter most:

- **Cache hit ratio:** `SELECT sum(blks_hit) / sum(blks_hit + blks_read) FROM pg_stat_database` - should be >99% for OLTP. Below 95% means shared_buffers is undersized or queries are scanning too much data.
- **Transaction rate and rollback ratio:** `xact_commit` and `xact_rollback` from `pg_stat_database`. A spike in rollbacks indicates application errors.
- **Autovacuum health:** Monitor `n_dead_tup` per table, `last_autovacuum` timestamp, number of active autovacuum workers vs `autovacuum_max_workers`. Alert if any table has >10 million dead tuples or has not been vacuumed in 24 hours.
- **Transaction ID age:** `SELECT max(age(datfrozenxid)) FROM pg_database`. Alert at 500 million, critical at 1 billion. Wraparound at 2 billion = database shuts down.
- **WAL generation rate:** Track `pg_current_wal_lsn()` over time. A sudden increase means something is generating excessive WAL (bulk loads, large UPDATEs without batching).
- **Connection count and state distribution:** Group `pg_stat_activity` by state. Alert on >80% max_connections used, and on any `idle in transaction` sessions older than 5 minutes.
- **Lock waits:** Count of sessions with `wait_event_type = 'Lock'` and duration of the longest wait.
- **Checkpoint duration and frequency:** From the PostgreSQL log or `pg_stat_bgwriter`. `checkpoint_write_time` and `checkpoint_sync_time` should be under your checkpoint_timeout.

**Tier 3 - Query metrics.** Enable `pg_stat_statements` and track: top queries by total_exec_time (not mean - total shows overall impact), queries with high `blks_read` (cache misses), queries with high `temp_blks_written` (need more work_mem or query optimization). Set up weekly reports comparing query performance to baseline.

**Tier 4 - Replication metrics.** On the primary: `SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, (sent_lsn - replay_lsn) AS replay_lag FROM pg_stat_replication`. Alert if replay_lag exceeds 100 MB or if replication state is anything other than 'streaming'. On standbys: `SELECT now() - pg_last_xact_replay_timestamp() AS replication_delay`. Alert if >30 seconds.

For tooling: EDB's PEM (Postgres Enterprise Manager) covers all of this with built-in dashboards and alerting. For open-source stacks: pgwatch2 or postgres_exporter + Prometheus + Grafana. I also always set `log_min_duration_statement = 1000` (log queries over 1 second) and `log_checkpoints = on` in postgresql.conf.
</details>

**Red flags:** Only monitoring CPU, memory, and disk without any EPAS-specific metrics. Not mentioning transaction ID wraparound monitoring. Not knowing about pg_stat_statements.

---

### Question 15: A developer asks you to run a DELETE that removes 800 million rows from a 1 billion row table. How do you handle this?

**What they are really asking:** Do you understand the implications of large-scale DML in EPAS and can you propose alternatives that do not bring down the production system?

<details markdown="block">
<summary><strong>Strong answer</strong></summary>

Running `DELETE FROM big_table WHERE condition` on 800 million rows in a single transaction would be catastrophic for several reasons: it generates massive WAL (easily 500+ GB for that many rows), holds row-level locks on 800 million tuples (enormous memory pressure from lock table overflow), takes hours and prevents autovacuum on that table for the entire duration, and if it fails or you need to cancel it, the rollback takes just as long. On EPAS with MVCC, the dead tuples from the DELETE still occupy disk space until VACUUM cleans them up - so you need 800 million rows worth of dead space temporarily.

**Approach 1 - Batch deletes (if keeping 200M rows is the minority case).** Delete in batches of 10,000-50,000 rows with a brief pause between batches to let autovacuum work:

```sql
DO $$
DECLARE
  deleted integer;
BEGIN
  LOOP
    DELETE FROM big_table
    WHERE ctid IN (
      SELECT ctid FROM big_table
      WHERE <condition>
      LIMIT 50000
    );
    GET DIAGNOSTICS deleted = ROW_COUNT;
    IF deleted = 0 THEN EXIT; END IF;
    RAISE NOTICE 'Deleted % rows', deleted;
    PERFORM pg_sleep(0.5);  -- Let autovacuum breathe
  END LOOP;
END $$;
```

This takes longer overall but is production-safe. Each batch generates manageable WAL and releases locks between iterations.

**Approach 2 - CREATE TABLE AS (if keeping 200M rows).** Since you are keeping only 20% of the data, it is faster to copy the keepers than to delete the leavers:

```sql
-- Create new table with surviving rows
CREATE TABLE big_table_new AS
  SELECT * FROM big_table WHERE <keep_condition>;

-- Recreate indexes, constraints, defaults, permissions
CREATE INDEX ... ON big_table_new ...;
ALTER TABLE big_table_new ADD CONSTRAINT ...;

-- Swap tables (brief lock)
BEGIN;
ALTER TABLE big_table RENAME TO big_table_old;
ALTER TABLE big_table_new RENAME TO big_table;
COMMIT;

-- After verification
DROP TABLE big_table_old;
```

This is much faster and avoids the dead tuple problem entirely. The new table has no bloat. The downside: the table is briefly renamed, so application queries may fail during the swap. Use a maintenance window or implement the swap behind PgBouncer (pause pool, swap, resume pool).

**Approach 3 - Partitioning (if this is a recurring need).** If you regularly purge old data, the table should be partitioned by date. Then purging is just `DROP TABLE big_table_y2025_q1` - instant, no dead tuples, no VACUUM, no WAL for the deleted rows.

In Oracle, a similar DELETE would generate undo (potentially filling the undo tablespace) and redo, but Oracle's MVCC cleanup is automatic. The Oracle DBA might use `ALTER TABLE ... ENABLE ROW MOVEMENT` and then `ALTER TABLE ... SHRINK SPACE` to reclaim space afterward, or use partition truncation. The EPAS equivalent of "shrink space" is `VACUUM FULL` (exclusive lock) or `pg_repack` (online).

My recommendation for this specific case: Approach 2 during a maintenance window. For a 1 billion row table, the CTAS takes maybe 30-60 minutes depending on hardware, versus 8-12 hours for batch deletes plus additional hours for VACUUM to reclaim the dead space.
</details>

**Red flags:** Running the DELETE in a single transaction without hesitation. Not mentioning WAL generation, dead tuples, or VACUUM. Saying "just add more disk" instead of addressing the architectural issue. Not considering the CTAS approach for majority-delete scenarios.
