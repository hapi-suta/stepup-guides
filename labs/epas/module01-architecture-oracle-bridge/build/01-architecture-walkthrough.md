---
layout: default
title: "Build 01 - Architecture Deep Dive Walkthrough"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 4
locked: "no"
---

# Build 01: EPAS Architecture Deep Dive Walkthrough

## What You Are Doing

You are working through five production analysis exercises that force you to think like an EPAS DBA, not an Oracle DBA. Each step gives you real output from a production EPAS server and asks you to diagnose, calculate, or explain what you see.

This is not a fill-in-the-blank worksheet. These are the exact situations you will face on-call at Mastercard.

**Mode:** Theory only - no server needed.

**Time:** 90 minutes.

**Prerequisite:** Read Concepts 02 (EPAS Architecture Deep Dive) first.

---

## Step 1: Process Model Analysis

Below is the `ps` output from a production EPAS 16 server running the CardAuth transaction processing application. This server handles 1,200 transactions per second during peak hours.

Study the output carefully. Something is wrong.

![EPAS Process Model]({{ '/assets/images/epas-process-model.svg' | relative_url }})

```
$ ps auxf | grep edb

enterprisedb  1201  0.0  0.1  postmaster -D /var/lib/edb/as16/data
enterprisedb  1205  0.0  0.0   \_ checkpointer
enterprisedb  1206  0.0  0.0   \_ bgwriter
enterprisedb  1207  0.0  0.0   \_ walwriter
enterprisedb  1208  0.0  0.0   \_ autovacuum launcher
enterprisedb  1209  0.0  0.0   \_ stats collector
enterprisedb  1210  0.0  0.0   \_ archiver   last was 00000001000000A40000003F
enterprisedb  1211  0.0  0.0   \_ logical replication launcher
enterprisedb  3401  2.1  1.2   \_ autovacuum worker   db=cardauth  tbl=txn_log
enterprisedb  3402  1.8  1.1   \_ autovacuum worker   db=cardauth  tbl=txn_log_archive
enterprisedb  3403  1.5  0.9   \_ autovacuum worker   db=cardauth  tbl=auth_decisions
enterprisedb  3404  1.2  0.8   \_ autovacuum worker   db=cardauth  tbl=merchant_cache
enterprisedb  3405  0.9  0.7   \_ autovacuum worker   db=cardauth  tbl=card_tokens
enterprisedb  3406  0.7  0.5   \_ autovacuum worker   db=cardauth  tbl=fraud_scores
enterprisedb  5001  0.3  0.2   \_ edb-as backend  cardauth_app  cardauth  10.0.4.21:43210  active
enterprisedb  5002  0.2  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.22:43211  active
enterprisedb  5003  0.1  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.23:43212  idle
enterprisedb  5004  0.1  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.21:43215  idle
enterprisedb  5005  0.0  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.22:43218  idle
enterprisedb  5006  0.0  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.23:43220  idle
enterprisedb  5007  0.0  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.21:43225  idle
enterprisedb  5008  0.0  0.1   \_ edb-as backend  cardauth_app  cardauth  10.0.4.22:43228  idle
enterprisedb  5009  0.0  0.1   \_ edb-as backend  batch_etl     cardauth  10.0.5.10:55001  idle in transaction
enterprisedb  5010  0.0  0.1   \_ edb-as backend  batch_etl     cardauth  10.0.5.10:55002  idle in transaction
enterprisedb  5011  0.0  0.1   \_ edb-as backend  batch_etl     cardauth  10.0.5.10:55003  idle in transaction
enterprisedb  5012  0.0  0.1   \_ edb-as backend  reporting_ro  cardauth  10.0.6.50:60001  active
enterprisedb  5013  0.0  0.1   \_ edb-as backend  reporting_ro  cardauth  10.0.6.50:60002  idle
enterprisedb  5014  0.0  0.1   \_ edb-as backend  monitoring    cardauth  10.0.7.1:22001   idle
```

### 1A: Process Identification

For each process category below, identify the processes from the output and explain their role.

| Category | Process(es) | Role in production |
|:---------|:------------|:-------------------|
| Master process | ___ | ___ |
| Maintenance background processes (list all 7) | ___ | ___ |
| Client backends (how many total?) | ___ | ___ |
| Autovacuum workers (how many active?) | ___ | ___ |

<details markdown="block">
<summary>Answer Key 1A</summary>

| Category | Process(es) | Role |
|:---------|:------------|:-----|
| Master process | **postmaster (PID 1201)** | Listens on port 5444, forks a new backend process for every client connection. Also manages shared memory and coordinates all child processes. If postmaster dies, everything dies. |
| Maintenance background processes | **checkpointer** (periodic dirty page flush), **bgwriter** (continuous small dirty page flush), **walwriter** (WAL buffer flush), **autovacuum launcher** (spawns vacuum workers), **stats collector** (feeds pg_stat_* views), **archiver** (copies WAL segments to backup), **logical replication launcher** (manages logical rep workers) | These seven are always present in a healthy EPAS instance. If any are missing from `ps` output, something is seriously wrong. |
| Client backends | **14 total** (PIDs 5001-5014) | Each backend handles exactly one client connection. 8 from cardauth_app (the main application), 3 from batch_etl, 2 from reporting_ro, 1 from monitoring. |
| Autovacuum workers | **6 active** (PIDs 3401-3406) | All 6 are vacuuming tables in the cardauth database. This is unusually high and is one of the anomalies you need to catch. |

</details>

### 1B: Anomaly Detection

Look at this output the way a senior DBA would at 3am. Identify at least three problems or concerns.

> **Concept:** In production PostgreSQL/EPAS, `ps` output tells a story. The number of autovacuum workers, the states of backends, the connections from unexpected sources - all of these are diagnostic signals. Learning to read `ps` output is like learning to read an EKG in medicine.

Write down what concerns you:

1. _______________________________________________
2. _______________________________________________
3. _______________________________________________

<details markdown="block">
<summary>Answer Key 1B</summary>

**Anomaly 1: Six autovacuum workers running simultaneously.**

The default `autovacuum_max_workers` is 3. Having 6 means someone raised it - which is not inherently bad - but all 6 are working on the same database at the same time. This tells you the `cardauth` database has a serious dead tuple problem. The tables are generating dead rows faster than autovacuum can clean them. In Oracle terms, this is like seeing every DBWR process at 100% CPU - something upstream is causing excessive churn.

The root cause is almost certainly the `batch_etl` sessions (see Anomaly 2). Long-running transactions prevent VACUUM from removing dead tuples, which causes autovacuum to work harder and harder without making progress.

**Anomaly 2: Three `batch_etl` backends stuck in "idle in transaction" state.**

This is the most dangerous thing in this output. "Idle in transaction" means these sessions opened a transaction (`BEGIN`) and then stopped doing anything - but never committed or rolled back. While these transactions stay open:

- VACUUM cannot remove any dead tuples created after these transactions started
- Table bloat grows without bound
- Eventually autovacuum gives up, dead tuples accumulate, and queries slow down
- In the worst case, you hit XID wraparound (the 2-billion transaction ID limit) and the database shuts itself down to prevent data corruption

In Oracle, you might let a session sit in an open transaction for hours without much harm (UNDO handles it). In PostgreSQL/EPAS, idle-in-transaction is a ticking bomb.

**Anomaly 3: The archiver process shows "last was ...3F".**

This by itself is not an anomaly - it just shows the last archived WAL segment. But combined with the other issues, you should ask: how long ago was that? If the archiver has not moved to a new segment in a while, your WAL archiving might be falling behind, which means your Point-In-Time Recovery window is stale. On a 1,200 TPS system, WAL segments should be cycling every few minutes.

**Anomaly 4 (bonus): Only 14 client connections on a 1,200 TPS system.**

This is actually healthy - it means they are likely using PgBouncer or another connection pooler in front of EPAS. A common Oracle mistake is setting `max_connections` to 2000 "just in case." In EPAS, fewer backends with connection pooling always outperforms many backends.

**Anomaly 5 (bonus): All cardauth_app connections come from three IPs (10.0.4.21-23).**

This is likely a 3-node application tier or a PgBouncer pool. Good architecture. But the batch_etl connections all come from a single IP (10.0.5.10) - this is the ETL server, and it is the source of your problems.

</details>

---

## Step 2: Memory Budget Calculation

You are sizing an EPAS 16 instance for a new Mastercard payment processing application. The server spec:

- **RAM:** 64 GB
- **max_connections:** 200 (includes pooler overhead)
- **Workload:** OLTP - short queries, high concurrency
- **Average concurrent active queries:** 40 at peak
- **Average sort/hash operations per query:** 2

> **Concept:** Memory sizing in EPAS is fundamentally different from Oracle. In Oracle, the SGA is a single large allocation that the instance manages. In EPAS, shared_buffers is allocated once at startup, but work_mem is allocated per-backend per-operation. This means a single bad setting can cause the Linux OOM killer to terminate your database process - something that never happens in Oracle because Oracle manages its own memory internally.

### The Memory Budget Formula

```
Total peak memory demand =
    shared_buffers
  + (active_backends * work_mem * avg_ops_per_query)
  + maintenance_work_mem * autovacuum_max_workers
  + OS overhead (kernel + page cache + other processes)
```

### Your Task

Fill in each row. Show your math. Then determine if the configuration is safe.

**Proposed Configuration:**
- `shared_buffers` = 16 GB (25% of RAM)
- `work_mem` = 256 MB
- `maintenance_work_mem` = 1 GB
- `autovacuum_max_workers` = 3
- `effective_cache_size` = 48 GB

| Component | Calculation | Result |
|:----------|:-----------|:-------|
| shared_buffers | Given | ___ GB |
| Peak work_mem demand | ___ active backends * ___ MB * ___ ops | ___ GB |
| Autovacuum memory | ___ workers * ___ GB | ___ GB |
| Total EPAS memory demand | Sum of above | ___ GB |
| OS overhead (reserve 10-15%) | ___ GB | ___ GB |
| Remaining for page cache | 64 GB - total demand - OS overhead | ___ GB |
| **Is this safe?** | Total demand + OS overhead < 64 GB? | YES / NO |

Then answer:

- What happens if ALL 200 connections become active simultaneously (not just 40)?
- What is the single most impactful change you would make to this configuration?
- Does `effective_cache_size` consume any RAM? What does it actually do?

<details markdown="block">
<summary>Answer Key Step 2</summary>

| Component | Calculation | Result |
|:----------|:-----------|:-------|
| shared_buffers | Given | **16 GB** |
| Peak work_mem demand | 40 backends * 256 MB * 2 ops | **20 GB** |
| Autovacuum memory | 3 workers * 1 GB | **3 GB** |
| Total EPAS memory demand | 16 + 20 + 3 | **39 GB** |
| OS overhead (reserve 10%) | 6.4 GB | **~7 GB** |
| Remaining for page cache | 64 - 39 - 7 | **18 GB** |
| **Is this safe?** | 46 GB < 64 GB | **YES - but barely** |

**Why "barely":** Under normal conditions (40 concurrent queries), this works. But the danger is hiding in `work_mem = 256 MB`.

**What happens if all 200 connections become active?**

200 backends * 256 MB * 2 ops = **100 GB** of work_mem demand alone. Add 16 GB shared_buffers + 3 GB autovac + 7 GB OS = **126 GB total demand on a 64 GB machine**. The Linux OOM killer will terminate the postmaster process, and every connection drops.

This is not hypothetical. At Mastercard scale, a connection pool stampede (e.g., after a network blip causes all connections to reconnect simultaneously) can push every backend into active status for a few seconds. 256 MB work_mem turns that into a server crash.

**The single most impactful change:**

Lower `work_mem` to **32-64 MB**. Here is the recalculation at 64 MB:
- Worst case: 200 * 64 MB * 2 = 25.6 GB
- Total: 16 + 25.6 + 3 + 7 = 51.6 GB - survivable on 64 GB

The queries that need large sorts will spill to disk (using temp files). This is slower for those individual queries, but the server stays alive. You can always set `work_mem` higher at the session level for specific batch jobs:
```sql
SET work_mem = '512MB';  -- just for this session
```

**Does effective_cache_size consume RAM?**

No. `effective_cache_size` allocates zero bytes. It is a hint to the query planner about how much total cache (shared_buffers + OS page cache) is available. It helps the planner decide whether an index scan (which relies on cached pages) is cheaper than a sequential scan. Setting it to 48 GB on a 64 GB machine tells the planner: "you can probably find frequently-accessed pages in cache, so favor index scans." This is one of the most misunderstood parameters - Oracle DBAs often worry it will eat memory, but it is purely advisory.

</details>

---

## Step 3: Storage Forensics

You get paged at 2:47 AM. The alert says: `/var/lib/edb/as16/data` is at **94% disk usage** on the CardAuth primary server. You SSH in and run `du -sh` on the PGDATA subdirectories:

```
$ du -sh /var/lib/edb/as16/data/*/

48G     /var/lib/edb/as16/data/base/
256K    /var/lib/edb/as16/data/global/
127G    /var/lib/edb/as16/data/pg_wal/
4.0K    /var/lib/edb/as16/data/pg_commit_ts/
4.0K    /var/lib/edb/as16/data/pg_dynshmem/
12K     /var/lib/edb/as16/data/pg_logical/
4.0K    /var/lib/edb/as16/data/pg_multixact/
4.0K    /var/lib/edb/as16/data/pg_notify/
4.0K    /var/lib/edb/as16/data/pg_replslot/
4.0K    /var/lib/edb/as16/data/pg_serial/
4.0K    /var/lib/edb/as16/data/pg_snapshots/
4.0K    /var/lib/edb/as16/data/pg_stat/
4.0K    /var/lib/edb/as16/data/pg_stat_tmp/
4.0K    /var/lib/edb/as16/data/pg_subtrans/
4.0K    /var/lib/edb/as16/data/pg_tblspc/
220K    /var/lib/edb/as16/data/pg_twophase/
4.0K    /var/lib/edb/as16/data/pg_xact/
8.2G    /var/lib/edb/as16/data/log/
```

Total disk: 200 GB. Used: 183 GB (91.5%).

You also run `pg_controldata`:

```
$ /usr/edb/as16/bin/pg_controldata /var/lib/edb/as16/data

pg_control version number:            1300
Catalog version number:               202307071
Database system identifier:           7384920155738291456
Database cluster state:               in production
pg_control last modified:             Sat Jun  7 02:47:12 2026
Latest checkpoint location:           A4/3F000028
Latest checkpoint's REDO location:    A4/3F000028
Latest checkpoint's REDO WAL file:    00000001000000A40000003F
Latest checkpoint's TimeLineID:       1
Latest checkpoint's PrevTimeLineID:   1
Latest checkpoint's full_page_writes: on
Latest checkpoint's NextXID:          0:1847293651
Latest checkpoint's NextOID:          24589
Latest checkpoint's NextMultiXactId:  1
Latest checkpoint's NextMultiOffset:  0
Latest checkpoint's oldestXID:        1694782103
Latest checkpoint's oldestXID's DB:   16384
Latest checkpoint's oldestActiveXID:  1847290022
Latest checkpoint's oldestMultiXid:   1
Latest checkpoint's oldestMulti's DB: 16384
Latest checkpoint's oldestCommitTsXid:0
Latest checkpoint's newestCommitTsXid:0
Time of latest checkpoint:            Sat Jun  7 02:45:01 2026
Minimum recovery ending location:     0/0
Min recovery ending loc's timeline:   0
Backup start location:                0/0
Backup end location:                  0/0
End-of-backup record required:        no
wal_level setting:                    replica
wal_log_hints setting:                on
max_connections setting:              200
max_worker_processes setting:         8
max_wal_senders setting:              10
max_prepared_transactions setting:    0
max_locks_per_transaction setting:    64
track_commit_timestamp setting:       off
Maximum data alignment:               8
Database block size:                  8192
Blocks per segment of large relation: 131072
WAL block size:                       8192
Bytes per WAL segment:                16777216
Maximum length of identifiers:        64
Maximum columns in an index:          32
Maximum size of a TOAST chunk:        1996
Size of a large-object chunk:         2048
Date/time type storage:               64-bit integers
Float8 argument passing:              by value
Data page checksum version:           1
Mock authentication nonce:            <redacted>
```

### 3A: Immediate Triage

You have 15 minutes before the disk hits 100% and the database crashes. Rank these three areas by urgency and explain what you would check first:

1. `pg_wal/` at 127 GB - why is it this large? _______________________________________________
2. `base/` at 48 GB - is this normal? _______________________________________________
3. `log/` at 8.2 GB - is this contributing? _______________________________________________

<details markdown="block">
<summary>Answer Key 3A</summary>

**Priority 1: `pg_wal/` at 127 GB - this is your emergency.**

Normal pg_wal size for a system with `max_wal_size = 1GB` (default) is 1-3 GB. 127 GB means WAL segments are not being cleaned up. The two most common causes:

1. **Stuck replication slot.** Check `pg_replication_slots` for a slot where `active = false` and `restart_lsn` is far behind the current WAL position. An inactive replication slot tells PostgreSQL "do not delete any WAL after this point" - even if that point was days ago. One abandoned replication slot from a decommissioned standby can fill your disk.

2. **Failed archiver.** Check `pg_stat_archiver` for `failed_count > 0` and look at `last_failed_wal`. If your `archive_command` is failing (e.g., the backup server is unreachable, S3 bucket permissions changed, disk full on the archive destination), PostgreSQL retains all WAL segments because they have not been safely archived. Look in the ps output from Step 1 - the archiver shows "last was ...3F" which is the same as the latest checkpoint WAL file. If that segment has been "last" for hours, archiving is stuck.

**Immediate fix:** If it is a stuck replication slot, drop it:
```sql
SELECT pg_drop_replication_slot('the_stuck_slot_name');
```
If it is archiver failure, fix the archive_command or temporarily switch to a local archive path, then clean up later.

**Priority 2: `base/` at 48 GB - probably normal, but check for bloat.**

48 GB for a transaction processing database is not alarming by itself. But you should verify after the emergency. Check `pg_stat_user_tables` for tables with high `n_dead_tup` counts - the idle-in-transaction sessions from Step 1 would cause exactly this pattern: dead tuples accumulate because VACUUM cannot clean them.

**Priority 3: `log/` at 8.2 GB - contributing but not the root cause.**

8.2 GB of logs on a 200 GB disk is not nothing (4%), but it is not the 127 GB elephant either. Check if `log_statement` is set to `all` or if `log_min_duration_statement` is set too low. On a 1,200 TPS system, logging every statement generates enormous log files. After the emergency, set up log rotation with `log_rotation_age` and `log_rotation_size`.

</details>

### 3B: pg_controldata Interpretation

> **Concept:** `pg_controldata` is like the flight data recorder for your database. When everything else is broken - when you cannot even start the database - this file still tells you what state the cluster was in. Every senior DBA should be able to read it fluently.

Look at the `pg_controldata` output above. Answer these questions:

1. What is the current XID (transaction ID)? How close is this system to XID wraparound? _______________________________________________
2. What does the gap between `oldestXID` (1,694,782,103) and `NextXID` (1,847,293,651) tell you? _______________________________________________
3. What does `oldestActiveXID` (1,847,290,022) tell you? Is there a problem? _______________________________________________
4. Is this cluster configured for Point-In-Time Recovery? How can you tell? _______________________________________________
5. Are data checksums enabled? Why does this matter? _______________________________________________

<details markdown="block">
<summary>Answer Key 3B</summary>

**1. XID wraparound risk:**

NextXID is 1,847,293,651. The XID space is 2^32 = ~4.3 billion, but only half (2^31 = ~2.15 billion) is usable in each direction. So the system can consume about 2.15 billion XIDs before wraparound forces a shutdown.

XIDs consumed so far: roughly 1.85 billion of the 2.15 billion budget. That is **86% consumed**. This is a warning sign but not yet critical - the database will enter emergency "anti-wraparound" autovacuum mode at about 200 million XIDs remaining (configurable via `autovacuum_freeze_max_age`, default 200 million). You have about 300 million XIDs remaining before that, which at 1,200 TPS is roughly 3 days.

This should be escalated as a P2 issue. The idle-in-transaction sessions from Step 1 are likely preventing autovacuum from freezing old tuples, which is why the oldest XID is not advancing.

**2. The gap between oldestXID and NextXID:**

oldestXID = 1,694,782,103, NextXID = 1,847,293,651. The gap is about 152 million XIDs. This means there is at least one database that has not had its oldest frozen tuple updated in 152 million transactions. VACUUM FREEZE needs to run on this database (OID 16384, which is the cardauth database). If this gap reaches `autovacuum_freeze_max_age` (default 200M), PostgreSQL will force aggressive autovacuum. If it reaches 2 billion, the database shuts down.

**3. oldestActiveXID:**

oldestActiveXID = 1,847,290,022, while NextXID = 1,847,293,651. The gap is only ~3,600 XIDs. This means the oldest active (in-progress) transaction started about 3,600 transactions ago. At 1,200 TPS, that is about 3 seconds - not concerning by itself. However, the idle-in-transaction sessions could be holding transaction snapshots that prevent cleanup even if their XID gap is small. The real danger is the snapshot they hold, not the XID they consume.

**4. Point-In-Time Recovery capability:**

`wal_level = replica` - this means WAL contains enough information for physical replication and PITR. If it were set to `minimal`, PITR would not be possible. Combined with the archiver process running (visible in the ps output), this system is configured for PITR. The key question is whether archiving is actually working (see 3A).

**5. Data checksums:**

`Data page checksum version: 1` means checksums are **enabled**. This is critical for production because it detects silent data corruption (bit flips from bad RAM, faulty storage controllers, cosmic rays). Without checksums, corrupt data pages can propagate to backups undetected. Checksums must be enabled at `initdb` time - you cannot turn them on later without a full dump and restore (or `pg_checksums` on a stopped cluster).

In Oracle, this is like `DB_BLOCK_CHECKSUM = TYPICAL` - but in EPAS, it is all-or-nothing and must be decided at cluster creation.

</details>

---

## Step 4: WAL Lifecycle Walkthrough

A card transaction hits the CardAuth application. The application sends this to EPAS:

```sql
UPDATE card_balances SET available_balance = available_balance - 47.50
WHERE card_id = 'MC-4532-XXXX-XXXX-7891';
COMMIT;
```

> **Concept:** WAL (Write-Ahead Logging) is the single most important concept in PostgreSQL/EPAS. It is the reason the database can survive a power failure without losing committed data. It is the foundation of replication, PITR, and crash recovery. In Oracle, this is the redo log - but EPAS handles it differently. Understanding this flow is not optional.

### Trace the Full Journey

The diagram below shows every step from the moment the UPDATE arrives to the moment the client gets "COMMIT OK." Read through it, then answer the questions that follow.

![WAL Lifecycle]({{ '/assets/images/wal-lifecycle.svg' | relative_url }})

```
 CLIENT (CardAuth app on 10.0.4.21)
    |
    | 1. TCP packet: "UPDATE card_balances SET ..."
    v
 BACKEND (PID 5001, dedicated to this connection)
    |
    | 2. PARSE: tokenize SQL, build parse tree
    |    - Checks syntax. If "UPDTE" instead of "UPDATE", error here.
    |
    | 3. ANALYZE: resolve names against system catalogs
    |    - Looks up card_balances in pg_class -> OID 16401
    |    - Looks up available_balance in pg_attribute -> attnum 3
    |    - Looks up card_id in pg_attribute -> attnum 1
    |    - Checks permissions: does cardauth_app have UPDATE on card_balances?
    |
    | 4. REWRITE: apply any rules or views
    |    - (No rewrite rules on this table, so pass-through)
    |
    | 5. PLAN: cost-based optimizer chooses execution strategy
    |    - Option A: Seq Scan card_balances (cost 0..45000)
    |    - Option B: Index Scan using card_balances_pkey (cost 0..8)
    |    - Planner picks B (index scan) because card_id has a unique index
    |    - Uses pg_statistic for cardinality estimates
    |
    | 6. EXECUTE begins:
    |    |
    |    | 6a. Read the index page for card_id = 'MC-4532-...-7891'
    |    |     - Check shared_buffers first (buffer cache hit?)
    |    |     - If not cached: read 8KB page from disk into shared_buffers
    |    |     - Follow index pointer to heap page
    |    |
    |    | 6b. Read the heap page containing the target row
    |    |     - Find the current tuple version (check xmin/xmax visibility)
    |    |     - Verify row matches WHERE clause
    |    |
    |    | 6c. Create a new tuple version on the SAME page (or a new page)
    |    |     - Old tuple: set xmax = current XID (marks it "deleted by this txn")
    |    |     - New tuple: xmin = current XID, available_balance = (old - 47.50)
    |    |     - Mark the buffer page as DIRTY in shared_buffers
    |    |
    |    | 6d. WRITE WAL RECORD to wal_buffers (in shared memory)
    |    |     - WAL record contains: page ID, offset, old bytes, new bytes
    |    |     - This is the CHANGE DESCRIPTION, not the whole page
    |    |     - If this is the first change to this page since last checkpoint,
    |    |       write a FULL PAGE IMAGE (the entire 8KB page) for safety
    |    |
    | 6e. Return "UPDATE 1" to client (rows affected)
    |
    | --- At this point, the change is in shared_buffers and wal_buffers ---
    | --- The data file on disk is UNCHANGED ---
    | --- If the server crashes RIGHT NOW, the change is LOST ---
    |
    | 7. Client sends "COMMIT;"
    |
    | 8. Backend writes COMMIT WAL record to wal_buffers
    |
    | 9. Backend calls walwriter to FLUSH wal_buffers to pg_wal/ on disk
    |    - fsync() to guarantee the WAL is on persistent storage
    |    - This is the DURABILITY POINT
    |
    | --- After this fsync(), the change survives a crash ---
    | --- The data file STILL has the old value on disk ---
    | --- But the WAL file has the recipe to reconstruct the new value ---
    |
    | 10. Backend sends "COMMIT" response to client over TCP
    |
    v
 CLIENT receives confirmation. Transaction complete.

 LATER (seconds to minutes):
    - bgwriter or checkpointer writes the dirty page from
      shared_buffers to base/16384/16401 (the actual data file)
    - This is called a "checkpoint" - it brings the data files
      up to date with what is already in WAL
    - AFTER the data file is written, the WAL for this change
      can eventually be recycled

 EVEN LATER:
    - autovacuum marks the old tuple version as reclaimable
    - The space is available for new tuples
```

### Questions

**4A: The Durability Question**

At exactly which step does the data become crash-safe? Explain WHY the data file does not need to be written for the transaction to be durable.

Your answer: _______________________________________________

**4B: The Crash Recovery Question**

The server loses power 10 seconds after the COMMIT. When it comes back up, the data file `base/16384/16401` still has the OLD balance. How does EPAS recover the committed transaction?

Your answer: _______________________________________________

**4C: The Performance Question**

Why does EPAS write to WAL (sequential writes to one file) instead of immediately updating the data file (random writes to many files)? What performance advantage does this give on spinning disks? On SSDs?

Your answer: _______________________________________________

**4D: The Oracle Comparison**

In Oracle, this flow involves redo logs, LGWR, DBWR, and undo tablespace. Map each Oracle component to its EPAS equivalent:

| Oracle | EPAS |
|:-------|:-----|
| Redo log buffer | ___ |
| LGWR (Log Writer) | ___ |
| Redo log files | ___ |
| DBWR (Database Writer) | ___ |
| UNDO tablespace | ___ |

<details markdown="block">
<summary>Answer Key Step 4</summary>

**4A: Durability**

The data becomes crash-safe at **Step 9** - when the WAL (including the COMMIT record) is fsynced to disk. The data file does not need to be written because the WAL contains a complete description of every change. If the server crashes, EPAS reads the WAL from the last checkpoint forward and replays every change to reconstruct the correct state of the data files. This is called "crash recovery" or "WAL replay."

The key insight: WAL is the source of truth. The data files are an optimization - a cached materialization of what is in the WAL. This is the same principle as Oracle's redo logs, but understanding it deeply is essential for EPAS operations.

**4B: Crash Recovery**

When EPAS starts after a crash:

1. It reads `pg_control` to find the latest checkpoint location
2. It opens the WAL files starting from that checkpoint's REDO location
3. It replays every WAL record forward: reading the affected data pages, applying the changes described in each WAL record, and writing them back to the data files
4. When it hits the COMMIT record for our transaction, it knows the transaction committed, so the changes are permanent
5. When it reaches the end of the WAL, recovery is complete
6. The database opens for connections

The old balance in the data file gets overwritten during replay. The new balance (with -47.50) is now on disk. From the application's perspective, the transaction was never lost.

**4C: Performance**

WAL writes are **sequential** - every new record is appended to the end of the current WAL segment. Data file writes are **random** - each UPDATE might touch a different page in a different file in a different location on disk.

On spinning disks: sequential writes are 100-1000x faster than random writes because the disk head does not need to seek. Writing one WAL record (sequential) is far cheaper than writing the data page (random seek). This is why WAL exists - it converts random writes into sequential writes.

On SSDs: the seek penalty is eliminated, so the gap is smaller. But WAL still wins because: (a) one WAL write per transaction vs. potentially many data page writes per transaction, (b) batching - walwriter can flush multiple transactions' WAL records in a single fsync, and (c) full page writes would be needed for every page on every change without WAL batching.

**4D: Oracle to EPAS mapping**

| Oracle | EPAS |
|:-------|:-----|
| Redo log buffer | **wal_buffers** (shared memory area for WAL records before flush) |
| LGWR (Log Writer) | **walwriter** (flushes wal_buffers to pg_wal/ on disk) |
| Redo log files | **pg_wal/ files** (WAL segment files, each 16 MB by default) |
| DBWR (Database Writer) | **bgwriter + checkpointer** (both write dirty pages from shared_buffers to data files - bgwriter does continuous trickle writes, checkpointer does periodic bulk writes) |
| UNDO tablespace | **No direct equivalent.** EPAS uses MVCC with old tuple versions stored directly in the heap (data) pages. Dead tuples are cleaned up by autovacuum. There is no separate undo segment or tablespace. This is a fundamental architectural difference. |

</details>

---

## Step 5: EPAS vs Community PostgreSQL

> **Concept:** EPAS is not a fork of PostgreSQL - it is PostgreSQL with proprietary extensions bolted on. Roughly 95% of what you will do as an EPAS DBA uses standard PostgreSQL features. The EPAS-specific additions exist primarily to ease migration from Oracle. Knowing which features are EPAS-only vs. community PostgreSQL tells you where to look for documentation and whether a solution is portable.

### Document the EPAS-Specific Features

For each feature below, write whether it is **EPAS-only** or **community PostgreSQL**, and explain when you would use it in production.

| Feature | EPAS-only or Community PG? | When you use it |
|:--------|:---------------------------|:----------------|
| Port 5444 default | ___ | ___ |
| Service user `enterprisedb` | ___ | ___ |
| EDB-SPL (PL/SQL compatible language) | ___ | ___ |
| DBMS_OUTPUT, DBMS_SQL, UTL_FILE packages | ___ | ___ |
| CREATE PROFILE (password policies) | ___ | ___ |
| Oracle-style hints (/*+ IndexScan ... */) | ___ | ___ |
| edbplus (SQL*Plus compatible CLI) | ___ | ___ |
| edb-psql (enhanced psql) | ___ | ___ |
| PEM (Postgres Enterprise Manager) | ___ | ___ |
| Streaming replication | ___ | ___ |
| pg_stat_statements | ___ | ___ |
| EFM (Enterprise Failover Manager) | ___ | ___ |
| Barman (backup tool) | ___ | ___ |
| edb_redwood_strings (empty string = NULL) | ___ | ___ |
| Row Level Security (RLS) | ___ | ___ |

### Documentation Decision Tree

When you need to look something up, where do you search?

```
Is this feature Oracle-compatibility related?
    |
    YES --> Search EDB docs first (docs.enterprisedb.com)
    |       Examples: EDB-SPL, DBMS_ packages, profiles, hints, edbplus
    |
    NO  --> Search community PG docs first (postgresql.org/docs)
            Examples: pg_stat_activity, EXPLAIN, WAL, replication,
                      pg_hba.conf, postgresql.conf parameters
```

<details markdown="block">
<summary>Answer Key Step 5</summary>

| Feature | EPAS-only or Community PG? | When you use it |
|:--------|:---------------------------|:----------------|
| Port 5444 default | **EPAS-only** (community PG uses 5432) | Always. Every connection string, firewall rule, and monitoring check must use 5444, not 5432. This is the #1 "why can't I connect?" issue for new EPAS DBAs. |
| Service user `enterprisedb` | **EPAS-only** (community PG uses `postgres`) | Always. File ownership, cron jobs, systemd services, SSH keys - all run as `enterprisedb`, not `postgres`. If you create files as `postgres`, EPAS cannot read them. |
| EDB-SPL | **EPAS-only** | When migrating PL/SQL code from Oracle. EDB-SPL supports Oracle PL/SQL syntax natively - packages, procedures, functions, triggers. You do not need to rewrite most Oracle PL/SQL. |
| DBMS_OUTPUT, DBMS_SQL, UTL_FILE | **EPAS-only** | When migrated Oracle code calls these packages. EPAS provides Oracle-compatible implementations. DBMS_OUTPUT works the same way. UTL_FILE can read/write server-side files. |
| CREATE PROFILE | **EPAS-only** | When security policy requires password complexity, expiration, or failed login lockout. Community PG has no profile mechanism - you need extensions like `passwordcheck` and `pg_auth_mon`. |
| Oracle-style hints | **EPAS-only** (community PG uses `pg_hint_plan` extension) | When the optimizer chooses a bad plan and you need to force an index or join method. EPAS supports Oracle hint syntax natively. In community PG, you install `pg_hint_plan`. |
| edbplus | **EPAS-only** | When Oracle DBAs need a familiar SQL*Plus-like interface. Supports Oracle SQL*Plus commands (SET, SPOOL, COLUMN formatting). Useful during migration transition period. |
| edb-psql | **EPAS-only** (enhanced version of community `psql`) | Daily interactive use. Similar to community `psql` but with EPAS-specific tab completion and compatibility. |
| PEM | **EPAS-only** (commercial product) | Web-based monitoring and management. Equivalent to Oracle Enterprise Manager. Provides alerts, performance dashboards, SQL Profiler. |
| Streaming replication | **Community PG** | High availability and read replicas. This is not an EPAS feature - it is built into PostgreSQL core. Works identically in community PG and EPAS. |
| pg_stat_statements | **Community PG** (extension) | Always install this. It tracks query execution statistics (total time, calls, rows). It is the EPAS equivalent of AWR's SQL section. Works in both community PG and EPAS. |
| EFM | **EPAS-only** (commercial product) | Automatic failover management. Monitors primary and standby, promotes standby if primary fails, updates application connection routing. Equivalent to Oracle Data Guard Broker. |
| Barman | **Community PG** (open source, EDB maintains it) | Backup and PITR. Works with both community PG and EPAS. Equivalent to RMAN. |
| edb_redwood_strings | **EPAS-only** (GUC parameter) | When Oracle code treats empty strings as NULL. In standard PostgreSQL, `'' != NULL`. Setting `edb_redwood_strings = on` makes EPAS behave like Oracle. Critical for migration - one wrong comparison can cause data bugs. |
| Row Level Security | **Community PG** | Multi-tenant security, data isolation. Built into PostgreSQL core since 9.5. Equivalent to Oracle VPD but with a different (simpler) API. |

</details>

---

## Summary: Printable Reference Card

This is your completed reference card. Print it. Keep it visible for the next 8 weeks.

```
+=========================================================================+
|              EPAS 16 PRODUCTION REFERENCE CARD                          |
|              Mastercard DBA Team                                        |
+=========================================================================+
|                                                                         |
|  DEFAULTS                                                               |
|    Port:                  5444                                           |
|    Service user:          enterprisedb                                   |
|    PGDATA:                /var/lib/edb/as16/data                         |
|    Service unit:          edb-as-16                                      |
|    Main CLI:              edb-psql                                       |
|    SQL*Plus replacement:  edbplus                                        |
|    Config files:          postgresql.conf, postgresql.auto.conf          |
|    Auth config:           pg_hba.conf                                    |
|                                                                         |
+-------------------------------------------------------------------------+
|                                                                         |
|  PROCESS TREE (child processes of postmaster)                           |
|    1. checkpointer        - periodic full dirty-page flush              |
|    2. bgwriter            - continuous trickle dirty-page flush          |
|    3. walwriter           - flushes WAL buffer to pg_wal/ on disk       |
|    4. autovacuum launcher - spawns workers to clean dead tuples         |
|    5. stats collector     - feeds pg_stat_* monitoring views            |
|    6. archiver            - copies WAL segments to backup destination   |
|    7. logical rep launcher- manages logical replication workers         |
|                                                                         |
+-------------------------------------------------------------------------+
|                                                                         |
|  MEMORY SIZING (for 64 GB host, OLTP)                                  |
|    shared_buffers       = 16 GB    (25% of RAM)                         |
|    wal_buffers          = 64 MB    (or -1 for auto)                     |
|    work_mem             = 32-64 MB (per backend per sort/hash op)       |
|    maintenance_work_mem = 1 GB     (for VACUUM, CREATE INDEX)           |
|    effective_cache_size = 48 GB    (hint only - no allocation)          |
|    max_connections      = 200      (use PgBouncer for more clients)     |
|                                                                         |
|  MEMORY FORMULA:                                                        |
|    Total = shared_buffers                                               |
|          + (active_backends * work_mem * ops_per_query)                  |
|          + (autovac_workers * maintenance_work_mem)                      |
|          + OS overhead (10-15%)                                          |
|    MUST be < total RAM or OOM killer strikes                            |
|                                                                         |
+-------------------------------------------------------------------------+
|                                                                         |
|  STORAGE (PGDATA subdirectories)                                        |
|    base/        - heap files (tables + indexes), one subdir per DB      |
|    global/      - cluster-wide catalogs + pg_control                    |
|    pg_wal/      - WAL segments (16 MB each). If growing = problem.      |
|    pg_tblspc/   - symlinks to tablespace locations                      |
|    log/         - server log files                                      |
|    pg_control   - cluster metadata, read with pg_controldata            |
|                                                                         |
|  DISK FULL TRIAGE (check in this order):                                |
|    1. pg_wal/   - stuck archiver or abandoned replication slot          |
|    2. base/     - table bloat from missing VACUUM                       |
|    3. log/      - verbose logging (log_statement = all)                 |
|                                                                         |
+-------------------------------------------------------------------------+
|                                                                         |
|  ORACLE -> EPAS TRANSLATION                                             |
|    Redo logs         -> WAL (pg_wal/)                                   |
|    Archive logs      -> Archived WAL (archive_command destination)      |
|    UNDO tablespace   -> NONE (MVCC in heap, VACUUM cleans dead tuples) |
|    SGA                -> shared_buffers + wal_buffers                   |
|    PGA                -> work_mem (per backend, per operation)          |
|    LGWR              -> walwriter                                       |
|    DBWR              -> bgwriter + checkpointer                         |
|    Data Guard        -> Streaming replication + EFM                     |
|    RMAN              -> Barman                                          |
|    OEM               -> PEM (Postgres Enterprise Manager)              |
|    SQL*Plus          -> edbplus                                         |
|    GoldenGate        -> PGD (Postgres Distributed) or logical rep      |
|    init.ora/SPFILE   -> postgresql.conf + postgresql.auto.conf          |
|    listener.ora      -> pg_hba.conf + listen_addresses param           |
|    AWR               -> pg_stat_statements + pgBadger                  |
|    DBMS_STATS        -> ANALYZE command (autovacuum runs it too)       |
|    v$session         -> pg_stat_activity                                |
|    DBA_SEGMENTS      -> pg_total_relation_size()                       |
|    CONNECT BY        -> CONNECT BY (EPAS) or WITH RECURSIVE (std PG)  |
|    Profiles          -> CREATE PROFILE (EPAS-only)                     |
|    DB links          -> postgres_fdw / dblink extension                |
|                                                                         |
+-------------------------------------------------------------------------+
|                                                                         |
|  CRITICAL GOTCHAS                                                       |
|    1. idle in transaction = ticking bomb (blocks VACUUM, causes bloat) |
|    2. Port 5444, not 5432. User enterprisedb, not postgres.            |
|    3. '' != NULL in PG (use edb_redwood_strings for Oracle compat)     |
|    4. XID wraparound at ~2.1B txns - monitor oldest unfrozen XID      |
|    5. No UNDO - dead tuples live in heap until VACUUM cleans them      |
|    6. work_mem is per-op, not per-session - multiply carefully         |
|    7. effective_cache_size does NOT allocate memory                    |
|    8. Docs: EDB docs for Oracle compat, PG docs for everything else   |
|                                                                         |
+=========================================================================+
```

---

## How To Know You Are Done

You can confidently do all of the following without looking at any reference material:

- **Process model:** Given a `ps` output, identify every EPAS process, explain its role, and spot anomalies (too many autovac workers, idle-in-transaction backends, missing background processes)
- **Memory sizing:** Given a server spec, calculate whether the memory budget is safe using the formula. Identify what breaks first under load.
- **Storage triage:** Given `du -sh` output of PGDATA, rank the most likely causes of disk pressure and explain the fix for each
- **WAL lifecycle:** Trace an UPDATE from parse to commit, identify the exact durability point, and explain why the data file does not need to be written for a transaction to be committed
- **EPAS vs community PG:** For any feature, know whether to search EDB docs or community PG docs first
- **Oracle mapping:** Translate any Oracle concept (redo, UNDO, LGWR, DBWR, Data Guard, RMAN) to the EPAS equivalent without hesitation

If any of these are shaky, re-read the Concepts docs and redo the specific Step that gave you trouble. This foundation is everything - Modules 02-08 build directly on it.
