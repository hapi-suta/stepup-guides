# Build 03: Storage Architecture

**Lab 2.3 - Storage Architecture Explorer**
**Time:** 60 minutes
**Node:** NODE1 only

In this lab you will explore how PostgreSQL organizes data on disk. You will navigate the PGDATA directory, trace a table from its name to its physical file, examine the internal structure of an 8KB page, and learn how PostgreSQL handles oversized values, free space tracking, and table bloat.

## Prerequisites

- PostgreSQL 16 installed and running on NODE1
- Lab 2.2 (Memory Architecture) completed
- Data directory at `/opt/pgsql/data`
- pgbench data loaded (from a previous lab)

---

## 1. The PGDATA Directory

**Run on NODE1 (pg-primary):**

The PGDATA directory is the root of everything PostgreSQL stores on disk - data files, configuration, WAL, transaction status, and more. Let's explore it.

Log in to NODE1 as `ec2-user`, then switch to root.

```bash
sudo su -
```

**You are now root.**

Switch to the postgres user.

```bash
su - postgres
```

**You are now the postgres user.**

List the top-level contents of the data directory. The `-la` flags show all files (`a`) in long format (`l`) so you can see ownership and permissions.

```bash
ls -la /opt/pgsql/data/
```

Expected output (yours will differ - timestamps vary):

```
drwx------  19 postgres postgres  4096 Apr 15 10:00 .
drwxr-xr-x   5 postgres postgres    60 Apr 14 08:00 ..
drwx------   6 postgres postgres  4096 Apr 15 10:00 base
drwx------   2 postgres postgres  4096 Apr 15 10:01 global
drwx------   2 postgres postgres  4096 Apr 14 08:00 pg_wal
-rw-------   1 postgres postgres  4535 Apr 14 08:00 postgresql.conf
-rw-------   1 postgres postgres  4760 Apr 14 08:00 pg_hba.conf
```

> **Note:** `pg_wal` may appear as a symlink (arrow pointing to another location), for example: `pg_wal -> /opt/pgsql/wal`. This is normal when WAL is stored on a separate disk for performance or space reasons.

Here is what each key directory and file contains:

| Directory / File | Purpose |
|---|---|
| `base/` | One subdirectory per database, named by the database's OID (object ID) |
| `global/` | Cluster-wide tables shared across all databases (`pg_database`, `pg_authid`, etc.) |
| `pg_wal/` | Write-ahead log segment files (16MB each by default) |
| `pg_xact/` | Transaction commit status bits (called `pg_clog` in versions before 10) |
| `pg_tblspc/` | Symbolic links to tablespace locations on other mount points |
| `pg_stat/` | Permanent statistics files (survive a restart) |
| `pg_stat_tmp/` | Temporary statistics files (rebuilt on startup) |
| `postgresql.conf` | Main server configuration file |
| `pg_hba.conf` | Client authentication rules (host-based access) |
| `pg_ident.conf` | OS-to-PostgreSQL user name mappings |

> **Concept: PGDATA Is the Entire Cluster**
> Everything PostgreSQL needs to run lives inside this one directory tree. If you back up this directory (plus any tablespace directories), you have a complete copy of the database cluster. This is why physical backups target the PGDATA directory and WAL files.

---

## 2. Mapping Databases to Directories

**Run on NODE1 (pg-primary):**

**You are still the postgres user.**

Each database gets its own subdirectory inside `base/`. The subdirectory name is the database's OID (a numeric identifier that PostgreSQL assigns internally). Let's find the mapping.

Connect to `labdb`. We connect to `labdb` because that's where the pgbench tables were created in the backup-pitr lab.

```bash
psql -d labdb
```

Query the system catalog to see every database and its OID. The `oid` is a hidden column on `pg_database` that you can select explicitly.

```sql
SELECT oid, datname FROM pg_database ORDER BY oid;
```

Expected output (yours will differ - OIDs are assigned at creation time):

```
  oid  |  datname
-------+-----------
     1 | template1
     4 | template0
     5 | postgres
 16384 | labdb
 16385 | appdb
 16386 | blobdb
(6 rows)
```

Now exit psql so you can check the filesystem.

```sql
\q
```

List the directories inside `base/`. Each number corresponds to one of the OIDs from the query above.

```bash
ls -la /opt/pgsql/data/base/
```

Expected output (yours will differ):

```
drwx------  2 postgres postgres  12288 Apr 15 10:00 1
drwx------  2 postgres postgres  12288 Apr 14 08:00 4
drwx------  2 postgres postgres  12288 Apr 15 10:00 5
drwx------  2 postgres postgres  45056 Apr 15 10:01 16384
drwx------  2 postgres postgres  12288 Apr 15 10:01 16385
drwx------  2 postgres postgres  12288 Apr 15 10:01 16386
```

The directory `1` is `template1`, `4` is `template0`, `5` is `postgres`, `16384` is `labdb`, `16385` is `appdb`, and `16386` is `blobdb`. You can match these up using the OIDs from the query.

> **Concept: OIDs Are Internal, Names Are External**
> PostgreSQL uses numeric OIDs internally for almost everything - databases, tables, indexes, types. The human-readable names you use in SQL are just labels that map to these OIDs in the system catalogs. When you look at the filesystem, you see OIDs.

---

## 3. Finding a Table's Physical File

**Run on NODE1 (pg-primary):**

**You are still the postgres user.**

Now let's trace a specific table from its SQL name all the way to its file on disk. PostgreSQL provides a built-in function for this.

Connect to `labdb` where the pgbench tables live.

```bash
psql -d labdb
```

Ask PostgreSQL where the `pgbench_accounts` table lives on disk. The `pg_relation_filepath` function returns the path relative to PGDATA.

```sql
SELECT pg_relation_filepath('pgbench_accounts');
```

Expected output (yours will differ - the relfilenode number is assigned internally):

```
    pg_relation_filepath
--------------------------
 base/16384/16394
(1 row)
```

This tells you the file is inside `base/16384/` (the labdb database directory) and the file is named `16394` (the relation's file node number).

Exit psql so you can look at the file on disk.

```sql
\q
```

List the file using the path from the query above. Replace `16384/16394` with the values from your output. The `-lh` flags show file size in human-readable format.

```bash
ls -lh /opt/pgsql/data/base/16384/16394
```

Expected output (yours will differ - file size depends on pgbench scale factor):

```
-rw------- 1 postgres postgres 13M Apr 15 10:01 /opt/pgsql/data/base/16384/16394
```

If a table grows beyond 1GB, PostgreSQL splits it into multiple segment files. The first segment has no suffix, and subsequent segments are named with a dot and a number.

```bash
ls -lh /opt/pgsql/data/base/16384/16394*
```

Expected output (yours will differ - you may see only one file if the table is under 1GB):

```
-rw------- 1 postgres postgres  13M Apr 15 10:01 /opt/pgsql/data/base/16384/16394
-rw------- 1 postgres postgres  24K Apr 15 10:01 /opt/pgsql/data/base/16384/16394_fsm
-rw------- 1 postgres postgres 8.0K Apr 15 10:01 /opt/pgsql/data/base/16384/16394_vm
```

You can see the main data file plus two companion files - `_fsm` (free space map) and `_vm` (visibility map). We will explore these later in this lab.

> **Concept: The 1GB Segment Limit**
> PostgreSQL splits relation files at 1GB boundaries. A 3.5GB table would have four files: `16394`, `16394.1`, `16394.2`, and `16394.3`. This limit exists for compatibility with older filesystems that could not handle files larger than 2GB. The segment size is set at compile time and cannot be changed without recompiling.

---

## 4. The 8KB Page Structure

**Run on NODE1 (pg-primary):**

**You are still the postgres user.**

Every data file is made up of 8KB pages (also called blocks). Each page has a fixed internal layout: a header at the top, line pointers that grow downward, and tuple data that grows upward from the bottom. The free space is the gap in the middle.

Connect to `labdb` where the pgbench tables live.

```bash
psql -d labdb
```

Install the `pageinspect` extension. This extension lets you look at the raw contents of individual pages.

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
```

Expected output:

```
CREATE EXTENSION
```

Now examine the header of page 0 (the first page) of the `pgbench_accounts` table. Page numbering starts at 0.

```sql
SELECT lsn, checksum, flags, lower, upper, special, pagesize, version
FROM page_header(get_raw_page('pgbench_accounts', 0));
```

Expected output (yours will differ - LSN and values depend on data):

```
    lsn    | checksum | flags | lower | upper | special | pagesize | version
-----------+----------+-------+-------+-------+---------+----------+---------
 0/1A8F230 |        0 |     0 |   292 |   384 |    8192 |     8192 |       4
(1 row)
```

Here is what each column means:

| Column | Meaning |
|---|---|
| `lsn` | Log sequence number - the WAL position of the last change to this page |
| `checksum` | Data checksum (0 if checksums are disabled) |
| `flags` | Page flags (0 = normal) |
| `lower` | End of the line pointer array (grows downward from the top) |
| `upper` | Start of the tuple data area (grows upward from the bottom) |
| `special` | Start of the special space at the end of the page (used by indexes) |
| `pagesize` | Always 8192 bytes (8KB) |
| `version` | Page layout version number |

The free space on this page is the gap between `lower` and `upper`. When PostgreSQL inserts a new row, it adds a line pointer at `lower` (moving it down) and writes the tuple data at `upper` (moving it up). When they meet, the page is full.

> **Concept: Pages Are the Unit of I/O**
> PostgreSQL always reads and writes in whole 8KB pages - never individual rows. When you SELECT a single row, PostgreSQL reads the entire 8KB page that contains it into shared_buffers. When you UPDATE a row, the entire page is marked dirty and eventually written back to disk. This is why `shared_buffers` is measured in pages, and why understanding page layout matters for performance.

---

## 5. TOAST - The Oversized-Attribute Storage Technique

**Run on NODE1 (pg-primary):**

**You are still connected to psql in the labdb database.**

A single tuple must fit within one 8KB page. But what happens when you store a 10KB text string? PostgreSQL uses TOAST (The Oversized-Attribute Storage Technique) to handle this automatically.

Create a test table with a text column.

```sql
CREATE TABLE toast_test (id serial, big_text text);
```

Expected output:

```
CREATE TABLE
```

Insert a row with a very large text value. The `repeat` function creates a string by repeating 'x' 10,000 times - far too large for a single page.

```sql
INSERT INTO toast_test (big_text) VALUES (repeat('x', 10000));
```

Expected output:

```
INSERT 0 1
```

Now find the TOAST table that PostgreSQL created automatically. The `reltoastrelid` column in `pg_class` points to the TOAST table's OID.

```sql
SELECT relname, reltoastrelid FROM pg_class WHERE relname = 'toast_test';
```

Expected output (yours will differ - the OID varies):

```
  relname   | reltoastrelid
------------+---------------
 toast_test |         16401
(1 row)
```

Find the physical file path of the TOAST table using the OID from the previous query.

```sql
SELECT pg_relation_filepath(16401::regclass);
```

Expected output (yours will differ):

```
 pg_relation_filepath
-----------------------
 base/16384/16404
(1 row)
```

> **Concept: TOAST Happens Transparently**
> When a row's total size approaches 2KB, PostgreSQL automatically compresses the large values. If compression alone is not enough, it moves them to a separate TOAST table. This all happens behind the scenes - your SQL queries see the original values as if they were stored inline. Each table with TOASTable columns gets its own dedicated TOAST table. You can see TOAST strategy per column with `\d+` in psql.

Check the TOAST strategy for the table's columns.

```sql
\d+ toast_test
```

Expected output (yours will differ):

```
                                            Table "public.toast_test"
  Column  |  Type   | Collation | Nullable |               Default                | Storage  |
----------+---------+-----------+----------+--------------------------------------+----------+
 id       | integer |           | not null | nextval('toast_test_id_seq'::regclass)| plain    |
 big_text | text    |           |          |                                      | extended |
```

The `Storage` column shows `extended` for `big_text`, which means PostgreSQL will both compress and move the value to TOAST if needed. The `plain` strategy for `id` means it is always stored inline (integers are small enough).

---

## 6. Free Space Map (FSM) and Visibility Map (VM)

**Run on NODE1 (pg-primary):**

**You are still connected to psql in the labdb database.**

Exit psql to look at files on disk.

```sql
\q
```

Every relation has up to two companion files alongside its main data file. Let's look at them. Use the relfilenode from your `pg_relation_filepath` output in Section 3 (replace `16394` with your actual value).

```bash
ls -la /opt/pgsql/data/base/16384/16394*
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres 13631488 Apr 15 10:01 /opt/pgsql/data/base/16384/16394
-rw------- 1 postgres postgres    24576 Apr 15 10:01 /opt/pgsql/data/base/16384/16394_fsm
-rw------- 1 postgres postgres     8192 Apr 15 10:01 /opt/pgsql/data/base/16384/16394_vm
```

There are three files here:

| File | Purpose |
|---|---|
| `16394` | The main data file containing all the table's rows (pages of tuples) |
| `16394_fsm` | **Free Space Map** - tracks how much free space each page has, so INSERT knows where to put new rows without scanning every page |
| `16394_vm` | **Visibility Map** - tracks which pages contain only tuples visible to all transactions, so VACUUM can skip them and index-only scans know which pages are safe to read from the index alone |

The FSM is a compact tree structure - it does not store exact byte counts, but rather a rough category (0-255) of how full each page is. This lets PostgreSQL find a page with enough room in just a few lookups.

The VM stores two bits per page: one for "all-visible" and one for "all-frozen". A page marked "all-frozen" contains only tuples old enough that no transaction will ever need to check their visibility again.

> **Concept: VM Enables Index-Only Scans**
> An index-only scan reads data directly from the index without touching the table - but only for pages marked all-visible in the VM. If a page is not all-visible, PostgreSQL must check the table to confirm tuple visibility. Running VACUUM regularly keeps the VM up to date, which keeps index-only scans fast.

---

## 7. Table Bloat with pgstattuple

**Run on NODE1 (pg-primary):**

**You are still the postgres user.**

When you DELETE or UPDATE rows, PostgreSQL does not immediately reclaim the space. The old row versions (dead tuples) stay in the page until VACUUM cleans them up. If VACUUM falls behind, the table accumulates "bloat" - wasted space from dead tuples.

Connect to `labdb` where the pgbench tables live.

```bash
psql -d labdb
```

Install the `pgstattuple` extension. This extension provides functions to measure tuple-level statistics and detect bloat.

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

Expected output:

```
CREATE EXTENSION
```

Run `pgstattuple` against the `pgbench_accounts` table. This function reads every page in the table, so it can take a moment on large tables.

> **Note:** This query scans the entire table and may take a minute or more on large tables.

```sql
SELECT * FROM pgstattuple('pgbench_accounts');
```

Expected output (yours will differ significantly depending on the scale factor used when loading pgbench data):

```
 table_len | tuple_count | tuple_len | tuple_percent | dead_tuple_count | dead_tuple_len | dead_tuple_percent | free_space | free_percent
-----------+-------------+-----------+---------------+------------------+----------------+--------------------+------------+--------------
  13631488 |      100000 |  12100000 |         88.78 |                0 |              0 |                  0 |     200000 |         1.47
(1 row)
```

Here is what the key columns mean:

| Column | Meaning |
|---|---|
| `table_len` | Total size of the table in bytes |
| `tuple_count` | Number of live (visible) tuples |
| `tuple_len` | Total bytes used by live tuples |
| `tuple_percent` | Percentage of table space used by live tuples |
| `dead_tuple_count` | Number of dead tuples (deleted or updated rows not yet vacuumed) |
| `dead_tuple_len` | Total bytes used by dead tuples |
| `dead_tuple_percent` | Percentage of table space wasted on dead tuples |
| `free_space` | Total free space in bytes across all pages |
| `free_percent` | Percentage of table that is empty space |

If `dead_tuple_percent` is high (say, above 20%), the table has significant bloat and VACUUM should be run. If `free_percent` is very high even after VACUUM, the table may need `VACUUM FULL` or `pg_repack` to physically shrink it.

---

## 8. Relation Size Functions

**Run on NODE1 (pg-primary):**

**You are still connected to psql in the labdb database.**

PostgreSQL provides several built-in functions to check the size of tables, indexes, and databases without leaving SQL. The `pg_size_pretty` function converts raw byte counts into human-readable format.

Check the size of the `pgbench_accounts` table alone (data only, no indexes or TOAST).

```sql
SELECT pg_size_pretty(pg_relation_size('pgbench_accounts')) AS table_size;
```

Expected output (yours will differ significantly depending on the scale factor):

```
 table_size
------------
 13 MB
(1 row)
```

Check the total size including all indexes and TOAST data.

```sql
SELECT pg_size_pretty(pg_total_relation_size('pgbench_accounts')) AS total_with_indexes;
```

Expected output (yours will differ significantly depending on the scale factor):

```
 total_with_indexes
--------------------
 21 MB
(1 row)
```

Check the total size of the current database.

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;
```

Expected output (yours will differ significantly depending on the scale factor):

```
 database_size
---------------
 30 MB
(1 row)
```

> **Concept: pg_relation_size vs pg_total_relation_size**
> `pg_relation_size` returns only the main fork (the data file). `pg_total_relation_size` includes the main fork plus all indexes, the TOAST table, the FSM, and the VM. The difference between these two numbers tells you how much overhead your indexes and TOAST data add. If total is much larger than the table alone, you may have too many indexes.

---

## 9. Clean Up

**Run on NODE1 (pg-primary):**

**You are still connected to psql in the labdb database.**

Drop the test table created in Section 5.

```sql
DROP TABLE toast_test;
```

Expected output:

```
DROP TABLE
```

Exit psql.

```sql
\q
```

Exit back to root.

```bash
exit
```

**You are now root.**

Exit back to ec2-user.

```bash
exit
```

**You are now ec2-user.**

---

## Checkpoint

Confirm you can do each of the following before moving on:

- [x] Can navigate PGDATA and identify all key directories
- [x] Can map a database name to its OID directory in `base/`
- [x] Can find any table's physical file on disk using `pg_relation_filepath`
- [x] Understand the 8KB page structure (lower, upper, free space between them)
- [x] Understand TOAST and when it activates (values approaching 2KB)
- [x] Know what FSM and VM files do and how they help performance
- [x] Can check table bloat with `pgstattuple`
- [x] Can query table, index, and database sizes with `pg_size_pretty`

---

**Proceed to [Build 04: Query Processing](04-query-processing.md)**
