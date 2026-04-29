# PostgreSQL Architecture

## Why This Module Matters

Before you touch a single config file or write a single query, you need a mental model
of what PostgreSQL actually is. Not "a database" - that's too vague. PostgreSQL is a
multi-process client/server system with a shared memory region, a background worker
pool, and a storage layout that was designed in the 1980s and is still running millions
of production databases today. Once you understand the pieces and how they connect,
every tuning decision, every error message, and every failure mode will start making
sense instead of feeling like guesswork.

---

## The Client/Server Model

PostgreSQL is not an embedded library. It is a server that listens for connections and
a client that connects to it. The two communicate over a protocol called libpq.

```
  [ Your App / psql ]
         |
         | TCP (port 5432) or Unix socket
         |
  [ PostgreSQL Server ]
```

When you run `psql`, it is a client. When you run `pg_dump`, it is a client. When your
application connects via a connection pool, that pool is a client. All of them speak the
same wire protocol. None of them share memory with the server - they send messages and
receive results.

The default connection point is a Unix domain socket at `/var/run/postgresql/.s.PGSQL.5432`
for local connections, or TCP port 5432 for remote connections. You configure which one
(or both) PostgreSQL listens on via `listen_addresses` in postgresql.conf.

---

## Process Architecture

PostgreSQL is multi-process, not multi-threaded. This is a deliberate design choice -
it gives each connection isolation and stability. A bug in one backend cannot corrupt
another.

```
  postmaster (PID 1)
  |
  +-- backend (for client A)
  +-- backend (for client B)
  +-- backend (for client C)
  |
  +-- background workers
       |
       +-- autovacuum launcher
       +-- autovacuum worker(s)
       +-- WAL writer
       +-- background writer (bgwriter)
       +-- checkpointer
       +-- stats collector
       +-- WAL sender (when replicas are connected)
```

**postmaster** - The parent process. It is the first process that starts. It listens for
new connections and forks a new backend process for each one. If a backend crashes,
postmaster cleans up and keeps running.

**backend processes** - One per connection. A backend handles exactly one client session
from start to finish. It parses queries, plans them, executes them, and sends results
back. When the session ends, the backend process exits.

**autovacuum** - Runs in the background reclaiming dead row versions. You will spend
time with this one. It has a launcher (always running) that starts worker processes as
needed.

**WAL writer** - Flushes write-ahead log records to disk so they are durable before
transactions commit.

**bgwriter** - Writes dirty pages from shared_buffers to disk proactively so that
checkpoint work is spread out rather than hitting all at once.

**checkpointer** - Runs checkpoints (more on that below).

---

## Memory Architecture

PostgreSQL uses two kinds of memory: shared memory (visible to all processes) and
per-process local memory.

```
  Shared Memory (all backends see this)
  +-------------------------------+
  |  shared_buffers               |  <-- page cache for table/index data
  |  WAL buffers (wal_buffers)    |  <-- in-flight WAL records
  |  lock tables                  |  <-- lock state for all sessions
  |  shared catalog cache         |  <-- cached system catalog lookups
  +-------------------------------+

  Per-Backend Memory (private to each connection)
  +-------------------------------+
  |  work_mem                     |  <-- sort, hash join scratch space
  |  maintenance_work_mem         |  <-- VACUUM, CREATE INDEX, REINDEX
  |  temp_buffers                 |  <-- temporary table data
  +-------------------------------+
```

**shared_buffers** - The most important memory setting. This is PostgreSQL's own page
cache - an in-memory pool of 8KB pages from your data files. Reads and writes go through
here first. A typical starting point is 25% of total RAM.

**work_mem** - Memory allocated per sort or hash operation inside a query. Not per query,
per operation - a complex query can allocate several multiples of work_mem at once.
Set it too high and you risk OOM when many connections run complex queries simultaneously.

**wal_buffers** - Memory used to buffer WAL records before they are written to the WAL
files on disk. Usually fine at the default (auto-tuned to about 3% of shared_buffers).

**maintenance_work_mem** - Used by VACUUM, CREATE INDEX, and ALTER TABLE operations.
Safe to set higher (512MB or more) because these are typically run one at a time.

---

## Storage Layout - The PGDATA Directory

When PostgreSQL initializes a cluster (via initdb), it creates a directory structure
called PGDATA. On a typical Linux install this is `/var/lib/pgsql/16/data/`.

```
$PGDATA/
  postgresql.conf       <-- main configuration file
  pg_hba.conf           <-- client authentication rules
  pg_ident.conf         <-- ident mapping
  PG_VERSION            <-- cluster major version number
  global/               <-- cluster-wide tables (pg_database, pg_auth...)
  base/                 <-- per-database subdirectories
    1/                  <-- database OID 1 (template1)
    16384/              <-- your database (OID assigned at creation)
      12345             <-- heap file for a table (named by relfilenode)
      12345_fsm         <-- free space map for that table
      12345_vm          <-- visibility map for that table
  pg_wal/               <-- write-ahead log files (16MB segments by default)
  pg_xact/              <-- transaction commit status (clog)
  pg_stat_tmp/          <-- temporary stats files
  pg_tblspc/            <-- symlinks to tablespace directories
```

Every table and index is stored as one or more files under `base/<db_oid>/`. The file
is named after the table's `relfilenode` (visible in `pg_class.relfilenode`). When a
table file exceeds 1GB, PostgreSQL automatically splits it into segments:
`12345`, `12345.1`, `12345.2`, etc.

**pg_wal/** is where WAL segments live. Do not delete files from here manually. Ever.

---

## How a Query Flows

When you send a query, it goes through five stages inside your backend process.

```
  Client sends SQL text
         |
         v
  [ Parser ]         -- tokenizes and builds a parse tree. Syntax errors caught here.
         |
         v
  [ Rewriter ]       -- applies rules (e.g., view definitions). Rewrites the parse tree.
         |
         v
  [ Planner/Optimizer ] -- generates possible query plans, estimates costs, picks the best one.
         |
         v
  [ Executor ]       -- walks the plan tree, fetches rows, applies filters, returns results.
         |
         v
  Results sent to client
```

The planner is where most tuning opportunities live. It uses table statistics (gathered
by ANALYZE) to estimate how many rows each operation will touch. If the statistics are
stale or missing, the planner picks bad plans. This is why autovacuum runs ANALYZE
automatically.

You can inspect what the planner chose with `EXPLAIN` and what it actually did with
`EXPLAIN ANALYZE`.

---

## WAL - Write-Ahead Log

WAL is PostgreSQL's durability guarantee. The rule is simple: before any change is
written to the actual data files, a record describing that change is written to the WAL
log first. The WAL write is durable (fsync'd) before the transaction commits.

```
  Write operation
       |
       +-> WAL record written and flushed to pg_wal/ first
       |
       +-> Data page updated in shared_buffers (not yet on disk)
       |
  Transaction commits (client gets confirmation)
       |
  (later) bgwriter / checkpointer writes dirty pages to data files
```

If PostgreSQL crashes between the commit and the data file write, it replays WAL records
on the next startup. This is crash recovery. The data files are brought back to a
consistent state from the WAL, and no committed transaction is lost.

WAL is also the foundation of replication - standbys receive WAL records and replay
them to stay in sync with the primary.

---

## Tablespaces

By default all your data lives under `$PGDATA/base/`. Tablespaces let you put databases,
tables, or indexes on a different filesystem or disk.

```
CREATE TABLESPACE fast_ssd LOCATION '/mnt/nvme/pg_tablespace';
CREATE TABLE orders (...) TABLESPACE fast_ssd;
```

Under the hood, PostgreSQL creates a directory at the specified location and adds a
symlink from `$PGDATA/pg_tblspc/` to it. Two built-in tablespaces always exist:
`pg_default` (for `base/`) and `pg_global` (for `global/`).

---

## System Catalogs

PostgreSQL stores its own metadata inside regular tables called system catalogs. They
live in the `pg_catalog` schema. You can query them like any other table.

```sql
-- What tables exist in a database?
SELECT relname, relkind FROM pg_class WHERE relkind = 'r';

-- What columns does a table have?
SELECT attname, atttypid::regtype FROM pg_attribute WHERE attrelid = 'orders'::regclass;

-- What schemas exist?
SELECT nspname FROM pg_namespace;
```

Key catalogs to know:

| Catalog | What it describes |
|---|---|
| pg_class | Tables, indexes, sequences, views (every "relation") |
| pg_attribute | Columns of every relation |
| pg_namespace | Schemas |
| pg_database | Databases in this cluster |
| pg_type | Data types |
| pg_proc | Functions and procedures |
| pg_stat_user_tables | Runtime stats per table (autovacuum, n_live_tup, etc.) |

---

## Checkpoints

A checkpoint is a point in time where PostgreSQL guarantees that all dirty pages in
shared_buffers have been written to the actual data files on disk. After a checkpoint,
crash recovery only needs to replay WAL from the checkpoint forward - not from the
beginning of time.

```
  ----[checkpoint]--------[checkpoint]--------[checkpoint]---->  time
                  ^
                  |
            crash here -> replay WAL from previous checkpoint only
```

Checkpoints are triggered by time (`checkpoint_timeout`, default 5 minutes) or by WAL
volume (`max_wal_size`, default 1GB). More frequent checkpoints mean less WAL to replay
on crash, but more I/O during normal operation. Less frequent checkpoints mean longer
recovery time but lower I/O overhead.

The checkpointer process runs these. The bgwriter helps by proactively writing dirty
pages between checkpoints so the checkpointer is not doing all the I/O at once.

If you see "checkpoint occurring too frequently" warnings in your logs, `max_wal_size`
is too small for your write volume and needs to be increased.

---

## What to Watch For in the Lab

You will be exploring these concepts hands-on. A few things to pay attention to:

- The process list (`ps aux | grep postgres`) - identify each background worker
- The shared memory size (`ipcs -m` on Linux, or just check shared_buffers)
- The PGDATA directory layout - open it, look at the files
- Running `EXPLAIN` on a query and reading the plan output
- The checkpoint log entries in `postgresql.log`

Do not worry about memorizing every detail. The goal is to build a map so that when
something goes wrong (and it will), you know where to look.
