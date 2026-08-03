---
layout: default
title: "02 - EPAS Architecture Deep Dive"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 2
---

# EPAS Architecture Deep Dive

## Why This Document Matters

If you do not know what is running inside an EPAS instance, you cannot
diagnose performance problems, you cannot tune memory, and you cannot
explain to a developer why their query is slow. This document covers every
process, memory area, and storage component that makes up a running EPAS
instance.

We will cover EPAS 16 specifically. Earlier and later versions have
slightly different process names and tuning parameters.

Quick Oracle parallels are sprinkled throughout. The full Oracle-to-EPAS
mapping is in document 03 - this document focuses on the EPAS side.

---

## Part 1: The Process Model

EPAS uses a **multi-process architecture**, not a multi-threaded one. Every
client connection gets its own dedicated OS process. This is different from
Oracle (which can use either dedicated server processes or shared servers)
and very different from MySQL (which is thread-based).

When you start an EPAS instance, here is what shows up in `ps`:

![EPAS Process Model]({{ '/assets/images/epas-process-model.svg' | relative_url }})

```
$ ps -ef | grep edb
edb-as-16  postmaster -D /var/lib/edb/as16/data
edb-as-16   \_ checkpointer
edb-as-16   \_ background writer
edb-as-16   \_ walwriter
edb-as-16   \_ autovacuum launcher
edb-as-16   \_ logical replication launcher
edb-as-16   \_ stats collector
edb-as-16   \_ archiver
edb-as-16   \_ edb-as: novapay_app novapay 10.0.1.45(54322) idle
edb-as-16   \_ edb-as: novapay_app novapay 10.0.1.45(54323) SELECT
edb-as-16   \_ edb-as: postgres postgres [local] idle
```

Every process you see has a specific job. Learn them all.

### The Postmaster

```
postmaster -D /var/lib/edb/as16/data
```

The parent process. Started by `systemctl start edb-as-16`. Its job:

1. Read configuration files (`postgresql.conf`, `pg_hba.conf`)
2. Allocate shared memory and semaphores
3. Start all background utility processes
4. Listen on the TCP port (5444 by default for EPAS, NOT 5432 like
   community PG - this is an EPAS-specific change)
5. Accept new connections from clients and fork a backend process for each
6. Reap dead child processes and restart them if needed

The postmaster does NOT process queries. It is purely a parent process.

If the postmaster dies, the whole instance dies. If a child process dies,
the postmaster usually kills all other backends and restarts everything
(a "crash recovery"). This is intentional - shared memory corruption from
one bad backend could affect every other backend, so the safe response is
restart.

**Oracle parallel:** Closest equivalent is PMON + SMON combined - the
parent process that manages everything else.

### Backend Processes

```
edb-as: novapay_app novapay 10.0.1.45(54322) idle
edb-as: novapay_app novapay 10.0.1.45(54323) SELECT
```

One per client connection. Each backend:

- Parses, plans, and executes SQL for its one client
- Reads from and writes to shared buffers
- Holds locks on rows and tables
- Logs its activity to the WAL buffer

The status field (idle / SELECT / INSERT / idle in transaction) is shown
in `pg_stat_activity` and in `ps`. You will spend a lot of time querying
`pg_stat_activity` to see what backends are doing.

Backend processes do not share memory directly with each other - they
share through the shared buffer pool (more on that below).

**Oracle parallel:** Dedicated server processes (no shared server
equivalent in EPAS - every connection gets its own process).

### Checkpointer

```
checkpointer
```

Periodically writes all dirty buffers from shared memory to disk. Runs
either on a time schedule (`checkpoint_timeout`, default 5 minutes) or
when WAL volume hits a threshold (`max_wal_size`, default 1GB).

Checkpoints are I/O intensive. A bad checkpoint can spike disk write
latency for everything else on the system. Tuning checkpoint behavior is
a topic in Module 12.

**Oracle parallel:** CKPT process. Same job.

### Background Writer (bgwriter)

```
background writer
```

Writes dirty buffers from shared memory to disk continuously, in small
batches, BEFORE the checkpointer needs to write them. Goal: smooth out
I/O so checkpoints have less work to do.

Runs every `bgwriter_delay` (default 200ms), writes up to
`bgwriter_lru_maxpages` (default 100 pages) per cycle.

**Oracle parallel:** DBWn (DBWriter) processes. Similar role.

### WAL Writer

```
walwriter
```

Writes WAL records from the WAL buffer (in shared memory) to disk
(`pg_wal/` directory). Runs every `wal_writer_delay` (default 200ms).

This is critical for durability. If walwriter falls behind, transactions
that COMMIT cannot acknowledge until their WAL is on disk.

**Oracle parallel:** LGWR (Log Writer). Same job.

### Autovacuum Launcher and Workers

```
autovacuum launcher
```

The launcher decides which tables need VACUUM or ANALYZE, then forks
worker processes to do the actual work. Maximum concurrent workers is
controlled by `autovacuum_max_workers` (default 3).

VACUUM in PostgreSQL is fundamentally different from anything in Oracle.
You will spend an entire module (Module 05) on MVCC and VACUUM. For now,
know that:

- VACUUM removes dead row versions left behind by UPDATE and DELETE
- Without VACUUM, table files grow forever (bloat) and queries get slower
- Autovacuum runs continuously in the background
- If autovacuum cannot keep up, you have a serious operational problem

**Oracle parallel:** Loosely similar to SMON cleaning up after itself.
But Oracle uses undo segments for old row versions, so there is no
equivalent to "VACUUM." This is the single biggest architectural
difference between Oracle and PostgreSQL.

### Logical Replication Launcher

```
logical replication launcher
```

If logical replication is configured (publications and subscriptions),
this process manages worker processes that apply replication changes.

For physical streaming replication (used by EFM), this process is not
involved. Streaming uses dedicated walsender and walreceiver processes
that spawn on demand.

**Oracle parallel:** GoldenGate Extract/Replicat processes for logical;
no direct equivalent for physical streaming (Data Guard's redo apply is
similar but operates differently).

### Stats Collector

```
stats collector
```

Collects runtime statistics about the database - row counts, index usage,
buffer hit ratios, transaction counts. Other backends query these stats
through views like `pg_stat_user_tables`, `pg_stat_user_indexes`,
`pg_stat_database`.

In PostgreSQL 15+, the stats collector was rewritten to use shared memory
instead of a separate process and file. In EPAS 16 it still appears in
`ps` for backwards compatibility but does much less work than in older
versions.

**Oracle parallel:** AWR collector + V$ views. AWR persists snapshots to
disk; PostgreSQL stats are kept in memory and reset on restart unless you
install `pg_stat_statements` extension (which you will, always).

### Archiver

```
archiver
```

If WAL archiving is enabled (`archive_mode = on` plus an
`archive_command`), this process runs the archive command once per
completed WAL segment. The command copies the WAL file to a backup
location (NFS, S3, Barman repository, etc.).

WAL archiving is required for point-in-time recovery and for replication
beyond the configured `wal_keep_size`. Module 06 covers this in depth.

**Oracle parallel:** ARCn (Archiver) processes.

---

## Part 2: Memory Architecture

EPAS uses two distinct memory categories: **shared memory** (accessible
to all processes) and **per-backend local memory** (private to one
backend).

![EPAS Memory Layout]({{ '/assets/images/epas-memory-layout.svg' | relative_url }})

### Shared Memory (set once at startup)

**shared_buffers** - The page cache. When a backend needs a table or
index page, it first checks shared_buffers. If found, no disk I/O. If
not, the page is read from disk into shared_buffers, evicting another
page if needed (LRU-ish algorithm).

Default: 128MB (laughable - always tune this).
Recommended: 25% of system RAM, up to about 8GB. Above 8GB the returns
diminish because the OS page cache takes over.

Resizing shared_buffers requires a restart.

**Oracle parallel:** Database Buffer Cache (DB_CACHE_SIZE).

**wal_buffers** - Where backends write WAL records before walwriter
flushes them to disk. Default 1/32 of shared_buffers, capped at 16MB.

Default is usually fine. Increase if you see high WAL contention.

**Oracle parallel:** Log Buffer (LOG_BUFFER).

**Lock tables, proc array, shared catalog caches** - Internal structures
for tracking locks, active processes, and parsed catalog entries.
Auto-sized, you rarely tune these directly.

### Per-Backend Memory (per session)

**work_mem** - Memory each backend can use for sorts, hash joins, and
similar operations. If a sort exceeds work_mem, it spills to disk in
temp files (much slower).

Default: 4MB (also laughable).
Recommended: Start at 16-64MB. But careful - this is PER BACKEND PER
OPERATION. A query with 3 sorts and 2 hash joins can use 5 x work_mem.
With 100 connections doing complex queries, you can OOM the box.

You will tune this in Module 12.

**Oracle parallel:** Roughly PGA SORT_AREA_SIZE / HASH_AREA_SIZE. But
Oracle's PGA is auto-managed via PGA_AGGREGATE_TARGET; PostgreSQL has no
equivalent global budget. You set work_mem per session and pray.

**maintenance_work_mem** - Memory for VACUUM, CREATE INDEX, REINDEX,
ALTER TABLE ADD FOREIGN KEY. Default 64MB. Set higher (256MB-1GB) for
servers that run nightly maintenance.

**temp_buffers** - Per-backend memory for temporary tables. Default 8MB.

---

## Part 3: Storage Layout

EPAS data lives in PGDATA - one directory tree per instance. On a typical
EPAS 16 install from EDB packages:

```
PGDATA = /var/lib/edb/as16/data
```

Inside that directory:

![EPAS Storage Layout]({{ '/assets/images/epas-storage-layout.svg' | relative_url }})

### Key paths to memorize

| Path | What it holds | When you touch it |
|:-----|:--------------|:------------------|
| `base/{db_oid}/` | Heap and index files | When you need to find where data is on disk |
| `pg_wal/` | WAL segments (16MB each) | When debugging replication lag, archive issues, full disk |
| `global/pg_control` | Cluster control file | When restoring from backup (must match WAL) |
| `pg_xact/` | Commit log | When transaction wraparound is approaching |
| `postgresql.conf` | Main configuration | Constantly |
| `pg_hba.conf` | Authentication rules | When fixing "permission denied" errors |
| `postgresql.auto.conf` | ALTER SYSTEM overrides | When you ran ALTER SYSTEM and need to revert |

### Tablespaces

By default, every table lives under `base/`. You can move tables to a
different filesystem with `CREATE TABLESPACE`:

```sql
CREATE TABLESPACE archive_ts LOCATION '/mnt/slow_disk/archive';
CREATE TABLE old_orders (...) TABLESPACE archive_ts;
```

PostgreSQL tablespaces are filesystem directories. Unlike Oracle, they
are not fixed-size pre-allocated files. Each table is one file (well, a
few files - heap, fsm, vm, plus toast tables for large rows) and grows
as data is inserted.

Each tablespace creates a symlink in `pg_tblspc/` pointing to the
filesystem location.

**Oracle parallel:** Logical concept is similar (group of related
storage), implementation is very different (filesystem dir vs.
preallocated datafiles).

---

## Part 4: Write-Ahead Logging (WAL)

Every change to data is first written to WAL, then to data files later.
This is the durability guarantee that lets a CRASH recover cleanly.

### How a write happens

```
1. Client sends UPDATE statement
2. Backend parses, plans, executes the UPDATE
3. Backend modifies the relevant page in shared_buffers (in memory)
4. Backend writes WAL records describing the change to WAL buffer
5. Backend marks the buffer "dirty" - needs to be written to disk
6. Client sends COMMIT
7. Backend appends a COMMIT record to WAL buffer
8. walwriter flushes WAL buffer to disk (pg_wal/...)
9. Backend acknowledges COMMIT to client (data is durable now)
10. Later, bgwriter or checkpointer writes dirty buffer to data file
```

The key point: **commit requires WAL on disk, not data on disk.** If
the server crashes after step 9 but before step 10, recovery replays
WAL to redo the change. Durability is preserved.

### WAL file naming

```
000000010000000000000001
\____/\______________/
  |          |
  |          +--- LSN (Log Sequence Number) prefix
  |
  +--- Timeline ID (changes on failover/recovery)
```

Each file is exactly 16MB (default). When full, EPAS switches to the
next file. Old files are either deleted (after checkpoint) or archived
(if archive_mode = on) or retained for replication slots.

**Oracle parallel:** Redo logs + archive logs combined. PostgreSQL does
not have separate "online redo" and "archive" files - just WAL, with
optional archiving of old WAL files.

---

## Part 5: Query Processing Pipeline

When a backend receives a SQL statement, here is what happens:

![EPAS Query Lifecycle]({{ '/assets/images/epas-query-lifecycle.svg' | relative_url }})

For prepared statements, the parse/analyze/rewrite phases happen once
and the plan is cached.

EPAS uses a **cost-based optimizer** like Oracle, but the cost model is
different. The optimizer relies on:

- Statistics in `pg_statistic` (gathered by ANALYZE or autovacuum)
- Cost parameters in `postgresql.conf` (`random_page_cost`,
  `seq_page_cost`, `effective_cache_size`)
- Table and index sizes from `pg_class`

When a query is slow, the diagnostic flow is:

1. Run `EXPLAIN` to see the plan (does not execute)
2. Run `EXPLAIN ANALYZE` to see actual times (does execute)
3. Run `EXPLAIN (ANALYZE, BUFFERS)` to see buffer hits and misses
4. Check `pg_stat_statements` for top queries by total time

Module 12 covers tuning in depth.

**Oracle parallel:** Pretty similar high level. Oracle has SQL Profile,
SQL Plan Management, Adaptive Cursor Sharing - PostgreSQL has none of
these. PostgreSQL also has no "hints" in standard PG, but **EPAS does
support Oracle-style hints** via the `pg_hint_plan` extension and the
EPAS-native /*+ HINT */ syntax.

---

## Part 6: EPAS-Specific Additions

Most of what we covered applies equally to community PostgreSQL. EPAS
adds:

1. **edb-spl PL/SQL parser** - When you write `CREATE PROCEDURE` in EPAS
   syntax, the engine accepts Oracle-style PL/SQL. Internally it
   translates to PL/pgSQL execution. Most Oracle packages port directly.

2. **DBMS_ packages** - DBMS_OUTPUT, DBMS_SCHEDULER, DBMS_LOCK, DBMS_SQL,
   DBMS_PIPE, UTL_FILE, UTL_SMTP, UTL_HTTP, UTL_ENCODE, and others.
   Implemented as EPAS extensions.

3. **Oracle compat types** - NUMBER, VARCHAR2, RAW, ROWID, LONG, DATE
   (Oracle DATE, includes time), INTERVAL DAY TO SECOND.

4. **Oracle compat syntax** - ROWNUM (works in WHERE), hierarchical
   queries (CONNECT BY / PRIOR / START WITH), hints (/*+ */), DUAL table,
   sequences with NEXTVAL/CURRVAL.

5. **Profiles** - Real CREATE PROFILE with FAILED_LOGIN_ATTEMPTS,
   PASSWORD_LIFE_TIME, PASSWORD_REUSE_TIME, PASSWORD_VERIFY_FUNCTION.

6. **EDB Resource Manager** - CPU and dirty-rate throttling per role.

7. **EDB Audit** - Built-in audit logging beyond pgAudit.

8. **EDB*Plus (edbplus)** - SQL*Plus replacement that runs SET, COL,
   DEFINE, SHOW, SPOOL, START commands.

9. **edb-psql** - psql variant with EDB-aware prompts and meta-commands.

10. **EPAS extensions** - dbms_aq, dbms_alert, edb_redwood_date, plus
    many more. Mostly auto-installed.

The default EPAS port is **5444**, not 5432. The default service user is
**enterprisedb**, not postgres. These two differences trip up everyone
who comes from community PG to EPAS for the first time.

---

## Reading Checkpoint

Before moving to the Oracle bridge doc, you should be able to answer
these without looking back:

1. What does the postmaster do?
2. What is the difference between bgwriter and walwriter?
3. Why does PostgreSQL need VACUUM and Oracle does not?
4. What is the default value of shared_buffers and what should you set
   it to?
5. What is the difference between work_mem (per-backend) and
   shared_buffers (shared)?
6. Where do tables physically live on disk?
7. What is in pg_wal/?
8. Walk through what happens when a backend processes an UPDATE statement
   from parse to commit acknowledgment.
9. What is the default EPAS port?
10. Name three Oracle compat features unique to EPAS.

If any are fuzzy, re-read the relevant section.

---

## Further Reading

- [PostgreSQL internals book (free online)](https://www.interdb.jp/pg/index.html)
- [EPAS 16 admin guide](https://www.enterprisedb.com/docs/epas/16/administration/)
- [Process architecture (community PG)](https://www.postgresql.org/docs/16/tutorial-arch.html)
- [WAL internals](https://www.postgresql.org/docs/16/wal-intro.html)
