# Exercise 03 - Storage Forensics

**Time estimate:** 25-30 minutes
**Prerequisites:** BUILD phase complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb (pgbench data), postgres user, PGDATA at `/opt/pgsql/data`. Extensions installed: pg_buffercache, pageinspect, pgstattuple.

---

## Objective

Trace a table from its SQL name to its physical file on disk and back. Measure table bloat and understand how VACUUM reclaims space. By the end of this exercise, you should be able to navigate from a table name to its on-disk files and interpret the output of `pgstattuple`.

---

## Step 1 - Map Table Names to Physical Files

On **NODE1** (pg-primary), switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -d labdb
```

For each pgbench table, find its OID and physical file path:

```sql
SELECT
    c.relname,
    c.oid AS table_oid,
    d.oid AS database_oid,
    pg_relation_filepath(c.oid) AS filepath
FROM pg_class c
CROSS JOIN (SELECT oid FROM pg_database WHERE datname = 'labdb') d
WHERE c.relname IN ('pgbench_accounts', 'pgbench_branches', 'pgbench_tellers', 'pgbench_history')
ORDER BY c.relname;
```

**Expected:** Four rows showing each table's OID and its relative filepath (e.g., `base/16384/16385`). The `base` directory is the root for all databases. The first number is the database OID. The second number is the table's relfilenode.

> **Concept:** PostgreSQL stores every table as one or more files in the `base/<database_oid>/<relfilenode>` directory structure. The relfilenode usually matches the table OID, but it changes after operations like `VACUUM FULL`, `TRUNCATE`, or `REINDEX`. Always use `pg_relation_filepath()` to find the current file - never assume OID equals relfilenode.

---

## Step 2 - Verify Files on Disk

Exit psql temporarily:

```sql
\q
```

List the physical files for pgbench_accounts. Replace `<filepath>` with the value from Step 1 (e.g., `base/16384/16385`):

```bash
ls -lh /opt/pgsql/data/<filepath>*
```

**Expected:** You will see the main data file and possibly segment files. PostgreSQL splits tables larger than 1GB into 1GB segments:

```
-rw------- 1 postgres postgres 1.0G Apr 18 10:00 /opt/pgsql/data/base/16384/16385
-rw------- 1 postgres postgres 1.0G Apr 18 10:00 /opt/pgsql/data/base/16384/16385.1
-rw------- 1 postgres postgres 512M Apr 18 10:00 /opt/pgsql/data/base/16384/16385.2
-rw------- 1 postgres postgres  24K Apr 18 10:00 /opt/pgsql/data/base/16384/16385_fsm
-rw------- 1 postgres postgres 8.0K Apr 18 10:00 /opt/pgsql/data/base/16384/16385_vm
```

> **Concept:** PostgreSQL enforces a 1GB maximum file size per segment. This is a compile-time default (`--with-segsize`) that avoids filesystem limitations on older systems. The `_fsm` suffix is the Free Space Map - it tracks which pages have free space for new rows. The `_vm` suffix is the Visibility Map - it tracks which pages contain only tuples visible to all transactions, allowing index-only scans to skip heap fetches and VACUUM to skip pages that do not need cleaning.

---

## Step 3 - Inspect a Page Header With pageinspect

Connect back to labdb:

```bash
psql -d labdb
```

Enable the pageinspect extension if not already enabled:

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
```

Examine page 0 (the first page) of pgbench_accounts:

```sql
SELECT
    lsn,
    checksum,
    lower,
    upper,
    special,
    pagesize,
    version,
    upper - lower AS free_space_bytes
FROM page_header(get_raw_page('pgbench_accounts', 0));
```

**Expected:** A single row showing the page header fields:
- `lsn` - the WAL position when this page was last modified
- `pagesize` - 8192 (8KB - the default PostgreSQL page size)
- `lower` - offset to the end of the line pointer array (grows downward from the top of the page)
- `upper` - offset to the start of the actual tuple data (grows upward from the bottom)
- `free_space_bytes` - the gap between `lower` and `upper` represents unused space on this page

> **Concept:** Every PostgreSQL page has the same 8KB structure: a 24-byte header, followed by an array of line pointers (each 4 bytes, pointing to a tuple's offset on the page), then free space, then the actual tuple data packed from the bottom up. When `upper - lower` is small, the page is nearly full. When a tuple is deleted, its space is not immediately reusable - VACUUM must mark it as free in the FSM before new tuples can claim that space.

---

## Step 4 - Create a TOAST Table and Verify

Create a test table with large text values:

```sql
CREATE TABLE toast_test (
    id serial PRIMARY KEY,
    big_text text
);
```

Insert rows with text larger than the TOAST threshold (about 2KB):

```sql
INSERT INTO toast_test (big_text)
SELECT repeat('x', 5000)
FROM generate_series(1, 100);
```

Find the TOAST table:

```sql
SELECT
    c.relname AS main_table,
    c.reltoastrelid,
    t.relname AS toast_table,
    pg_size_pretty(pg_relation_size(c.reltoastrelid)) AS toast_size
FROM pg_class c
JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE c.relname = 'toast_test';
```

**Expected:** Shows the TOAST table name (e.g., `pg_toast.pg_toast_16400`) and its size. Because each row's text is 5000 bytes (well above the ~2KB threshold), the text data is stored in the TOAST table, not in the main heap.

> **Concept:** TOAST (The Oversized-Attribute Storage Technique) automatically moves large column values out of the main table heap and into a separate TOAST table. The threshold is roughly 2KB per value. PostgreSQL first tries to compress the value (strategy `extended`). If it is still too large after compression, it is stored out-of-line in the TOAST table. Other strategies: `plain` (no TOAST, error if too large), `main` (compress but keep in-line if possible), `external` (store out-of-line without compression - useful for already-compressed data like images).

Verify that the main table is small compared to the TOAST table:

```sql
SELECT
    pg_size_pretty(pg_relation_size('toast_test')) AS main_table_size,
    pg_size_pretty(pg_relation_size(c.reltoastrelid)) AS toast_table_size
FROM pg_class c
WHERE c.relname = 'toast_test';
```

**Expected:** The main table will be very small (a few KB for 100 row pointers) while the TOAST table holds the bulk of the data.

---

## Step 5 - Measure Bloat With pgstattuple

Enable the pgstattuple extension if not already enabled:

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

Create a test table for bloat measurement:

```sql
CREATE TABLE bloat_test AS
SELECT generate_series(1, 10000) AS id, repeat('y', 200) AS payload;
```

Check the table stats before any deletions:

```sql
SELECT
    table_len,
    tuple_count,
    tuple_len,
    dead_tuple_count,
    dead_tuple_len,
    free_space,
    free_percent
FROM pgstattuple('bloat_test');
```

**Expected:** `dead_tuple_count = 0` and `free_percent` is very low (under 5%). The table was just created with no deletions.

---

## Step 6 - Create and Measure Bloat

Delete half the rows:

```sql
DELETE FROM bloat_test WHERE id % 2 = 0;
```

Check the stats again before VACUUM:

```sql
SELECT
    table_len,
    tuple_count,
    tuple_len,
    dead_tuple_count,
    dead_tuple_len,
    free_space,
    free_percent
FROM pgstattuple('bloat_test');
```

**Expected:** `dead_tuple_count` is approximately 5000. `dead_tuple_len` shows the space occupied by dead tuples. The `table_len` has not changed - PostgreSQL does not shrink the file on DELETE.

> **Concept:** When you DELETE a row, PostgreSQL does not remove it from disk. It marks the row as dead (invisible to new transactions). The space is not reusable until VACUUM runs. This is MVCC (Multi-Version Concurrency Control) in action - other transactions that started before the DELETE may still need to see the old row version. The dead tuples are called "bloat" because they waste space without serving any active queries.

Now run VACUUM:

```sql
VACUUM bloat_test;
```

Check the stats after VACUUM:

```sql
SELECT
    table_len,
    tuple_count,
    tuple_len,
    dead_tuple_count,
    dead_tuple_len,
    free_space,
    free_percent
FROM pgstattuple('bloat_test');
```

**Expected:** `dead_tuple_count` drops to 0. `free_space` and `free_percent` increase significantly - VACUUM marked the dead tuple space as reusable in the FSM. However, `table_len` is still the same - regular VACUUM does not shrink the file. New inserts will fill the free space before the file grows.

> **Concept:** Regular `VACUUM` marks dead space as reusable but does not return it to the OS. The file stays the same size. Only `VACUUM FULL` rewrites the entire table to a new file, reclaiming all dead space - but it requires an `ACCESS EXCLUSIVE` lock (no reads or writes) and doubles disk usage temporarily. In production, regular VACUUM is preferred because it does not block queries. VACUUM FULL is a last resort for tables with extreme bloat (over 50% dead space).

---

## Step 7 - Find FSM and VM Files on Disk

Exit psql:

```sql
\q
```

Find the filesystem path for pgbench_accounts and look for its FSM and VM files:

```bash
psql -d labdb -t -A -c "SELECT pg_relation_filepath('pgbench_accounts');"
```

The `-t` flag removes the header and footer. The `-A` flag removes alignment padding. This gives you the raw path.

Use that path to list all associated files. Replace `<filepath>` with the output:

```bash
ls -lh /opt/pgsql/data/<filepath>*
```

**Expected:** You will see the main data file(s), plus `_fsm` and `_vm` suffixed files:
- `<relfilenode>` - main data file (and `.1`, `.2` for segments beyond 1GB)
- `<relfilenode>_fsm` - Free Space Map
- `<relfilenode>_vm` - Visibility Map

> **Concept:** The FSM is a compact data structure that tracks free space on each page. When PostgreSQL needs to insert a row, it consults the FSM to find a page with enough free space rather than scanning every page. The VM tracks which pages are "all-visible" - meaning every tuple on the page is visible to all current transactions. This enables two optimizations: index-only scans can skip the heap fetch for all-visible pages, and VACUUM can skip all-visible pages entirely (they have no dead tuples to clean).

---

## Step 8 - Clean Up Test Tables

```bash
psql -d labdb
```

```sql
DROP TABLE IF EXISTS toast_test;
```

```sql
DROP TABLE IF EXISTS bloat_test;
```

```sql
\q
```

```bash
exit
```

---

## Checkpoint

Before continuing, confirm:
- [ ] You traced pgbench tables from SQL name to OID to physical file on disk
- [ ] You verified the 1GB segment file limit and found multiple segments for large tables
- [ ] You inspected a page header with `pageinspect` and understand the page layout
- [ ] You created a TOAST table and verified large values are stored out-of-line
- [ ] You measured dead tuples with `pgstattuple` before and after VACUUM
- [ ] You understand that regular VACUUM marks space as reusable but does not shrink the file
- [ ] You found FSM and VM files on disk and know what each one tracks

---

**Next:** [04 - Query Pipeline Diagnostics](04-query-pipeline-diagnostics.md)
