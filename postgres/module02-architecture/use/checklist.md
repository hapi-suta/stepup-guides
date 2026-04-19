# Phase 2 (USE) - Knowledge Check

Answer each question before moving to Phase 3. Hidden answers are provided - try answering from memory first, then expand the answer to check yourself.

---

## Instructions

For each question, formulate your answer mentally or on paper. Then expand the answer block to verify. If you get fewer than 12 correct, review the relevant exercises before proceeding.

---

## Questions

### Process Architecture

**1. Name at least 5 PostgreSQL background processes and explain what each one does.**

<details>
<summary>Answer</summary>

- **postmaster** - the main supervisor process. Listens for incoming connections and spawns all other processes. Parent of every PostgreSQL process.
- **checkpointer** - writes dirty pages from shared_buffers to disk at checkpoint intervals. Ensures crash recovery starts from a known-good point.
- **background writer** - continuously writes dirty pages to disk between checkpoints to reduce the work the checkpointer must do at each checkpoint and to free buffer space for backends.
- **walwriter** - flushes WAL (Write-Ahead Log) buffers to disk. Ensures committed transactions are durable even if the server crashes before the next checkpoint.
- **autovacuum launcher** - monitors tables for dead tuples and launches autovacuum worker processes to clean them up and update table statistics.
- **logical replication launcher** - manages logical replication workers for subscriptions.
- **stats collector** (PG15 and earlier) / **cumulative stats system** (PG16+) - collects usage statistics from all backends and writes them to the stats views (pg_stat_activity, pg_stat_database, etc.).

</details>

---

**2. What is the difference between pg_cancel_backend and pg_terminate_backend? What is the correct escalation order?**

<details>
<summary>Answer</summary>

- `pg_cancel_backend(pid)` sends SIGINT to the backend. It cancels the currently running query but keeps the connection alive. The client can immediately run another query. This is the **first step** in the escalation.

- `pg_terminate_backend(pid)` sends SIGTERM to the backend. It kills the entire connection - the backend process exits and the client is disconnected with a "server closed the connection unexpectedly" error. This is the **second step**.

Escalation order:
1. `pg_cancel_backend` - polite, preserves the connection
2. `pg_terminate_backend` - forceful, kills the connection
3. Never use `kill -9` on individual backends - PostgreSQL must handle its own process cleanup

On CentOS, connect as postgres and use: `SELECT pg_cancel_backend(<pid>);` or `SELECT pg_terminate_backend(<pid>);`

</details>

---

**3. What happens if you run kill -9 on the postmaster process? Why is this dangerous?**

<details>
<summary>Answer</summary>

Sending `kill -9` (SIGKILL) to the postmaster immediately terminates it and all child processes without any cleanup. This is equivalent to pulling the power cord. The consequences:

- All in-flight transactions are lost (not committed to WAL)
- Shared memory is abandoned in a potentially inconsistent state
- The `postmaster.pid` file is left behind (must be manually removed or PostgreSQL checks on restart)
- On the next startup, PostgreSQL must perform crash recovery by replaying WAL from the last checkpoint forward

Data corruption is possible if `fsync` was disabled or if the filesystem does not honor fsync correctly. Even with fsync enabled, crash recovery takes time proportional to the amount of WAL since the last checkpoint.

The safe shutdown methods are:
- `pg_ctl stop -m fast` - rolls back active transactions, then shuts down cleanly
- `pg_ctl stop -m smart` - waits for all clients to disconnect, then shuts down
- `pg_ctl stop -m immediate` - aborts all backends without rollback, but still performs a clean crash recovery on next startup (safer than kill -9)

</details>

---

**4. What information does the postmaster.pid file contain? Name at least 5 of its 8 lines.**

<details>
<summary>Answer</summary>

The `postmaster.pid` file (at `/opt/pgsql/data/postmaster.pid`) contains 8 lines:

1. **Postmaster PID** - the process ID of the main PostgreSQL process
2. **PGDATA path** - the data directory (e.g., `/opt/pgsql/data`)
3. **Start timestamp** - Unix epoch when the postmaster started
4. **Port number** - the TCP port PostgreSQL listens on (e.g., `5432`)
5. **Unix socket directory** - where the Unix domain socket is created (e.g., `/run/postgresql`)
6. **Listen address** - the first `listen_addresses` value (e.g., `*` for all interfaces)
7. **Shared memory key/ID** - identifies the System V shared memory segment
8. **Server status** - `ready` when the server has completed startup

PostgreSQL writes this file at startup and removes it at clean shutdown. If it exists when PostgreSQL starts, it checks whether a process with that PID is running to prevent two instances from using the same data directory.

</details>

---

### Memory Architecture

**5. Write the worst-case memory formula for a PostgreSQL instance. Explain each component.**

<details>
<summary>Answer</summary>

```
Worst-case memory =
    shared_buffers
  + (max_connections x work_mem x sorts_per_query)
  + (autovacuum_max_workers x maintenance_work_mem)
  + temp_buffers (per session, if temp tables used)
  + OS overhead (~1-2 GB)
```

Components:
- **shared_buffers** - fixed allocation at startup. The main buffer cache shared by all backends. Typically 25% of total RAM.
- **max_connections x work_mem x sorts_per_query** - the dangerous multiplier. Each backend can allocate `work_mem` multiple times per query (once per sort, hash join, or bitmap operation). A query with 3 hash joins uses 3 x `work_mem`.
- **autovacuum_max_workers x maintenance_work_mem** - autovacuum workers use `maintenance_work_mem` (or `autovacuum_work_mem` if set) for their operations.
- **temp_buffers** - per-session allocation for temporary tables. Only allocated if the session uses temp tables.
- **OS overhead** - kernel buffers, page cache, system services.

Example with defaults on a 16GB server: 128MB + (100 x 4MB x 3) + (3 x 64MB) + 1GB = ~2.5GB. Safe, but increasing work_mem to 256MB makes it: 128MB + (100 x 256MB x 3) + 192MB + 1GB = ~76GB - far exceeding available RAM.

</details>

---

**6. Explain the difference between shared_buffers, work_mem, and effective_cache_size. Which ones allocate actual memory?**

<details>
<summary>Answer</summary>

- **shared_buffers** - allocates real shared memory at PostgreSQL startup. This is the main buffer cache where table and index pages are cached. All backends share this pool. Changing it requires a restart. Typical setting: 25% of total RAM.

- **work_mem** - allocates real per-operation memory during query execution. Used for sorts, hash joins, hash aggregations, and bitmap operations. Each operation in a query gets its own `work_mem` allocation. The memory is freed when the operation completes. Can be set per session with SET.

- **effective_cache_size** - does NOT allocate any memory. It is a hint to the query planner about the total amount of cache available (shared_buffers + OS page cache). It affects cost estimates for index scans vs sequential scans. A higher value makes the planner favor index scans because it assumes more data is cached. Typical setting: 75% of total RAM.

Only `shared_buffers` and `work_mem` allocate actual memory. `effective_cache_size` is purely advisory.

</details>

---

**7. You see buffers_backend is 45% of total writes in pg_stat_bgwriter. What does this mean and how do you fix it?**

<details>
<summary>Answer</summary>

A `buffers_backend` percentage of 45% means that 45% of all dirty page writes are being performed by regular client backend processes instead of the checkpointer or background writer. This is bad because:

- Backends are spending time doing I/O instead of processing queries
- Each backend write causes a latency spike for the client waiting on that query
- The workload is generating dirty pages faster than the background writer can clean them

Fixes (try in this order):
1. **Increase `bgwriter_lru_maxpages`** - raise from the default 100 to 200 or 400. This lets the background writer clean more pages per round.
2. **Increase `bgwriter_lru_multiplier`** - raise from the default 2.0 to 4.0. This makes the background writer more aggressive about predicting future demand.
3. **Increase `shared_buffers`** - a larger buffer pool reduces eviction pressure, giving the background writer more time to clean pages before backends need the space.
4. **Check `checkpoint_completion_target`** - ensure it is 0.9 (PG16 default) so checkpoints spread writes over time.

Target: `buffers_backend` should be under 5% of total writes.

</details>

---

**8. A developer sets work_mem = 2GB because their analytical query is slow. The server has 32GB RAM and max_connections = 200. Is this safe?**

<details>
<summary>Answer</summary>

No, this is extremely dangerous. Worst-case calculation:

200 connections x 2GB x 3 sorts per query = 1,200GB of work_mem demand. Even if only 10% of connections run simultaneously: 20 x 2GB x 3 = 120GB - far exceeding the 32GB available.

The Linux OOM killer will fire and kill PostgreSQL or other critical processes.

Safe approaches:
- Set `work_mem` globally to a conservative value (e.g., 64MB)
- For the specific analytical query, set it per session: `SET work_mem = '512MB';` then run the query, then `RESET work_mem;`
- Better yet, run analytical queries on a dedicated read replica with a higher `work_mem` and lower `max_connections`
- Best: use `SET LOCAL work_mem = '512MB';` inside a transaction so it automatically resets when the transaction ends

</details>

---

### Storage Architecture

**9. Why does PostgreSQL split table files into 1GB segments? What are the segment files named?**

<details>
<summary>Answer</summary>

PostgreSQL splits table files at 1GB boundaries to avoid filesystem limitations. Some older filesystems (and some network filesystems) have maximum file size limits or performance degradation with very large files. The 1GB limit is a compile-time default (`--with-segsize`) that provides broad compatibility.

Segment naming:
- First segment: `<relfilenode>` (e.g., `16385`) - no suffix, up to 1GB
- Second segment: `<relfilenode>.1` (e.g., `16385.1`) - the next 1GB
- Third segment: `<relfilenode>.2` (e.g., `16385.2`)
- And so on

Related files use underscore suffixes:
- `<relfilenode>_fsm` - Free Space Map
- `<relfilenode>_vm` - Visibility Map
- `<relfilenode>_init` - initialization fork (for unlogged tables)

On CentOS with custom mount points, these files live under `/opt/pgsql/data/base/<database_oid>/`.

</details>

---

**10. What are the FSM and VM files? What optimization does each enable?**

<details>
<summary>Answer</summary>

**FSM (Free Space Map)** - `<relfilenode>_fsm`
- Tracks how much free space is available on each page of the table
- When PostgreSQL needs to INSERT a new row, it consults the FSM to find a page with enough free space
- Without the FSM, PostgreSQL would have to scan every page to find room for new rows
- VACUUM updates the FSM when it frees space from dead tuples

**VM (Visibility Map)** - `<relfilenode>_vm`
- Tracks two bits per page: "all-visible" and "all-frozen"
- **All-visible**: every tuple on this page is visible to all current transactions
- **All-frozen**: every tuple on this page is frozen (no longer needs transaction ID checks)

Optimizations enabled:
1. **Index-only scans** - when all requested columns are in the index, PostgreSQL can skip the heap fetch for all-visible pages (the VM confirms no dead tuples exist on that page)
2. **VACUUM skip** - VACUUM skips all-visible pages because they have no dead tuples to clean
3. **Freeze skip** - aggressive VACUUM skips all-frozen pages because they are already frozen

</details>

---

**11. What does pgstattuple tell you? How do you interpret dead_tuple_percent = 35%?**

<details>
<summary>Answer</summary>

`pgstattuple` scans the entire table and reports:
- `table_len` - total size of the table on disk
- `tuple_count` / `tuple_len` - number and total size of live tuples
- `dead_tuple_count` / `dead_tuple_len` - number and total size of dead tuples
- `free_space` / `free_percent` - space marked as free in the FSM

A `dead_tuple_percent` of 35% means 35% of the table's disk space is occupied by dead (deleted or updated) rows that are no longer visible to any transaction. This is significant bloat.

Interpretation and actions:
- **Under 10%** - normal, autovacuum is keeping up
- **10-20%** - moderate bloat, check if autovacuum is running frequently enough. Consider lowering `autovacuum_vacuum_scale_factor` for this table.
- **20-50%** - significant bloat. Run `VACUUM` manually. If it does not reduce bloat, check for long-running transactions blocking cleanup (query `pg_stat_activity` for `idle in transaction`).
- **Over 50%** - severe bloat. Consider `VACUUM FULL` (requires downtime / exclusive lock) or `pg_repack` (online, no lock) to reclaim space.

Note: `pgstattuple` performs a full table scan and takes an `AccessShareLock`. On large tables, it can be slow and I/O-intensive.

</details>

---

**12. When does PostgreSQL use TOAST? Name at least 2 TOAST storage strategies.**

<details>
<summary>Answer</summary>

PostgreSQL uses TOAST (The Oversized-Attribute Storage Technique) when a row's data exceeds roughly 2KB (the TOAST threshold, which is about 1/4 of the 8KB page size). TOAST can compress values, store them out-of-line in a separate TOAST table, or both.

Four TOAST storage strategies:

1. **EXTENDED** (default for text, bytea, jsonb) - first tries compression. If the value is still too large after compression, stores it out-of-line in the TOAST table. This is the most flexible strategy.

2. **EXTERNAL** - stores values out-of-line in the TOAST table without compression. Useful for already-compressed data (images, encrypted blobs) where compression would waste CPU without reducing size. Also allows faster substring operations because the data does not need decompression.

3. **MAIN** - tries compression but prefers to keep the value in-line (in the main table heap). Only moves to the TOAST table as a last resort when the row absolutely cannot fit on a page. Rarely used.

4. **PLAIN** - no TOAST at all. The value must fit on a single page. If it is too large, PostgreSQL raises an error. Used for fixed-size types like integer and boolean that are guaranteed to be small.

You can check a column's TOAST strategy with: `SELECT attname, attstorage FROM pg_attribute WHERE attrelid = 'tablename'::regclass;` where `x` = extended, `e` = external, `m` = main, `p` = plain.

</details>

---

### Query Processing

**13. Name the 5 stages of PostgreSQL query processing in order. At which stage does a query referencing a nonexistent table fail?**

<details>
<summary>Answer</summary>

The 5 stages in order:

1. **Parser** - checks SQL grammar and builds a parse tree. Fails on syntax errors (e.g., `SELEC` instead of `SELECT`).

2. **Analyzer** (also called semantic analysis) - resolves table names, column names, data types, and checks permissions. **A query referencing a nonexistent table fails here** with `ERROR: relation "tablename" does not exist`.

3. **Rewriter** - applies rewrite rules and expands views. If you query a view, the rewriter replaces the view reference with its underlying query definition.

4. **Planner/Optimizer** - generates possible execution plans and chooses the one with the lowest estimated cost. Considers indexes, join methods, scan types, and statistics from `pg_statistic`.

5. **Executor** - runs the chosen plan, fetches data, applies filters, performs joins, and returns results to the client.

A query that passes the parser (valid syntax) but references a nonexistent table fails at stage 2 (Analyzer) because the analyzer is where name resolution happens.

</details>

---

**14. What is the difference between estimated rows and actual rows in EXPLAIN ANALYZE? What causes them to diverge?**

<details>
<summary>Answer</summary>

- **Estimated rows** (`rows=N` in the EXPLAIN output) - the planner's prediction of how many rows a node will produce, based on table statistics in `pg_statistic`. This number appears in both `EXPLAIN` and `EXPLAIN ANALYZE`.

- **Actual rows** (`actual ... rows=N`) - the real number of rows the node produced during execution. This number only appears in `EXPLAIN ANALYZE` because the query must actually run to measure it.

Common causes of divergence:

1. **Stale statistics** - the table has been heavily modified since the last `ANALYZE`. Fix: run `ANALYZE tablename;`

2. **Correlated columns** - the planner assumes column values are independent. If `city = 'New York'` AND `state = 'NY'` are correlated, the planner underestimates the combined selectivity. Fix (PG14+): create extended statistics with `CREATE STATISTICS`.

3. **Non-uniform distribution** - the planner uses average statistics. If data is heavily skewed (e.g., 90% of orders belong to 1% of customers), estimates for specific values may be far off.

4. **Complex expressions** - the planner cannot estimate selectivity for functions or complex expressions accurately. It falls back to default selectivity estimates (typically 0.5% for equality, 33% for range).

Large divergences cause bad plan choices. If estimated rows = 1 but actual rows = 100,000, the planner may choose a Nested Loop (efficient for 1 row) when a Hash Join would be far better for 100,000 rows.

</details>

---

**15. Why is running EXPLAIN ANALYZE on a DELETE or UPDATE query dangerous? How do you safely analyze destructive queries?**

<details>
<summary>Answer</summary>

`EXPLAIN ANALYZE` actually executes the query. Unlike plain `EXPLAIN` (which only plans without executing), `EXPLAIN ANALYZE` must run the query to measure actual times and row counts. If you run:

```sql
EXPLAIN ANALYZE DELETE FROM users;
```

It will delete every row in the users table. The EXPLAIN output shows you the plan and timing, but the damage is done.

Safe approach - wrap the query in a transaction and roll back:

```sql
BEGIN;
EXPLAIN ANALYZE DELETE FROM users WHERE id = 12345;
ROLLBACK;
```

The `BEGIN` starts a transaction. `EXPLAIN ANALYZE` executes the DELETE within that transaction. `ROLLBACK` undoes the DELETE. You get the plan and timing without permanent data loss.

Important caveats:
- The DELETE does happen (briefly) - it acquires row locks and generates WAL. Other transactions may be blocked during the analysis.
- If you forget the `ROLLBACK` and the session disconnects, PostgreSQL automatically rolls back the transaction. But if you accidentally `COMMIT`, the data is gone.
- For long-running destructive queries, the transaction holds locks for the entire duration of `EXPLAIN ANALYZE`, which can impact other sessions.

</details>

---

## Scoring

- **15/15 correct** - You are ready for Phase 3 (SURVIVE). Proceed with confidence.
- **12-14 correct** - Review the exercises for the questions you missed, then re-test yourself.
- **Below 12** - Repeat the full USE phase. Mastery comes from repetition, not from rushing forward.

---

## What Phase 3 Expects From You

Phase 3 (SURVIVE) will test your ability to handle architecture-level incidents without step-by-step instructions. You will face:

- Runaway queries consuming all available connections
- Memory pressure from misconfigured work_mem or shared_buffers
- Table bloat causing query performance degradation
- Corrupted or missing system catalog entries
- Checkpoint storms and I/O saturation

The SURVIVE scenarios give you a symptom and expect you to diagnose the root cause, apply the fix, and verify recovery. If you cannot perform the USE phase tasks from memory - listing processes, calculating memory budgets, tracing tables to disk, reading EXPLAIN plans - Phase 3 will be frustrating rather than educational. Take the time now.

---

**Next:** Phase 3 - SURVIVE exercises
