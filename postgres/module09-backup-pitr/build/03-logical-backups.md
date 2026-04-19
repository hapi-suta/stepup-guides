# Build 03: Logical Backups

Learn every pg_dump and pg_dumpall option. By the end of this guide you can dump
any database in any format with surgical precision.

---

## 1. pg_dump basics - plain SQL format (-Fp)

**Run on NODE1 (pg-primary):**

The simplest backup - a plain SQL script. Use plain format (`-Fp`) when you have a small database and want a human-readable dump you can open and edit.

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Dump the appdb database in plain SQL format. The `-Fp` flag selects plain format:

```bash
pg_dump -Fp appdb > /opt/pgsql/backup/dumps/appdb.sql
```

The `>` operator sends the command's output into a file instead of printing it on screen.

(`-Fp` = plain format, `appdb` = the database to dump)

Inspect the first 30 lines of the dump to see what it looks like:

```bash
head -30 /opt/pgsql/backup/dumps/appdb.sql
```

Expected: SQL statements starting with `--` comments, `SET` commands, `CREATE TABLE`, `COPY`.

```
Expected output (yours will differ):
--
-- PostgreSQL database dump
--

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
...
```

Check the file size:

```bash
ls -lh /opt/pgsql/backup/dumps/appdb.sql
```

```
Expected output (yours will differ):
-rw-r--r--. 1 postgres postgres 4.1M Apr 19 01:20 /opt/pgsql/backup/dumps/appdb.sql
```

> **Concept - Plain SQL format**: The `-Fp` (plain) format produces a readable SQL
> script. It is human-inspectable and can be replayed with `psql`. The downside -
> you cannot selectively restore individual tables from a plain dump, and it does
> not support parallel restore. Use it for small databases or when you need to
> edit the dump manually.

## 2. Custom format (-Fc)

**Run on NODE1 (pg-primary):**

The most versatile format - compressed, supports selective restore. Use custom format (`-Fc`) as your go-to default for most backups.

Still as the postgres user, dump appdb in custom format:

```bash
pg_dump -Fc appdb > /opt/pgsql/backup/dumps/appdb.dump
```

(`-Fc` = custom format. Custom format compresses the output and lets you selectively restore individual tables later.)

Compare the size to the plain SQL dump:

```bash
ls -lh /opt/pgsql/backup/dumps/appdb.sql /opt/pgsql/backup/dumps/appdb.dump
```

Expected: the `.dump` file is significantly smaller (compressed by default).

```
Expected output (yours will differ):
-rw-r--r--. 1 postgres postgres 4.1M Apr 19 01:20 /opt/pgsql/backup/dumps/appdb.sql
-rw-r--r--. 1 postgres postgres 412K Apr 19 01:20 /opt/pgsql/backup/dumps/appdb.dump
```

Peek at the table of contents. This shows every object in the dump file:

```bash
pg_restore --list /opt/pgsql/backup/dumps/appdb.dump
```

Expected: a numbered list of objects (tables, indexes, sequences, data).

```
Expected output (yours will differ):
;
; Archive created at 2026-04-19 01:20:54 UTC
;     dbname: appdb
;     TOC Entries: 19
;     Compression: gzip
;     Dump Version: 1.15-0
;     Format: CUSTOM
...
```

> **Concept - Custom format is king**: Custom format (`-Fc`) is the recommended
> format for most use cases. It compresses automatically, supports parallel
> restore, and lets you selectively restore specific tables or schemas. Always
> use custom format unless you have a specific reason not to.

## 3. Directory format (-Fd)

**Run on NODE1 (pg-primary):**

Directory format dumps each table to a separate file, which enables parallel dumping. Use directory format (`-Fd`) when you have a large database and need the fastest possible dump and restore times.

Dump appdb in directory format. The `-f` flag specifies the output directory (instead of `>` for a single file):

```bash
pg_dump -Fd appdb -f /opt/pgsql/backup/dumps/appdb_dir/
```

(`-Fd` = directory format, `-f` = output directory path)

Inspect the directory:

```bash
ls -la /opt/pgsql/backup/dumps/appdb_dir/
```

Expected: a `toc.dat` file plus one compressed data file per table.

```
Expected output (yours will differ):
total 420K
-rw-r--r--. 1 postgres postgres  12K Apr 19 01:20 toc.dat
-rw-r--r--. 1 postgres postgres 400K Apr 19 01:20 3377.dat.gz
-rw-r--r--. 1 postgres postgres  247 Apr 19 01:20 3378.dat.gz
...
```

Now dump the large labdb using 2 parallel workers. The `-j` flag sets the number of workers:

```bash
pg_dump -Fd -j 2 labdb -f /opt/pgsql/backup/dumps/labdb_dir/
```

(`-j 2` = use 2 workers to dump tables simultaneously)

This will take a few minutes with the 5GB dataset. Be patient.

> **Concept - Parallel dump**: The `-j` (jobs) flag only works with directory
> format. Each worker dumps a different table simultaneously. For databases with
> many tables, this dramatically reduces dump time. The number of jobs should not
> exceed the number of CPU cores or available RAM. On small instances (1-2 GB RAM),
> keep `-j` low (1-2) to avoid running out of memory. On production servers with
> more RAM, you can increase it.

## 4. TAR format (-Ft)

**Run on NODE1 (pg-primary):**

A tar archive of the directory format - useful for transferring as a single file. Use tar format (`-Ft`) when you need a single portable file but still want the ability to selectively restore individual tables.

```bash
pg_dump -Ft appdb > /opt/pgsql/backup/dumps/appdb.tar
```

(`-Ft` = tar format)

Inspect the contents of the tar file. The `|` (pipe) operator takes the output of one command and feeds it as input to the next command:

```bash
tar tf /opt/pgsql/backup/dumps/appdb.tar | head -10
```

(`tar tf` = list the files inside a tar archive without extracting them. `head -10` = show only the first 10 lines.)

Expected: filenames like `toc.dat`, data files.

> **Concept - TAR format tradeoffs**: TAR format is essentially directory format
> packed into a single file. It supports selective restore like custom format, but
> does not support parallel restore (pg_restore cannot seek within a tar stream).
> Use it when you need a single file but still want selective restore capability.

## 5. Compare all format sizes

**Run on NODE1 (pg-primary):**

Check the plain SQL dump size:

```bash
ls -lh /opt/pgsql/backup/dumps/appdb.sql
```

Check the custom format dump size:

```bash
ls -lh /opt/pgsql/backup/dumps/appdb.dump
```

Check the directory format size:

```bash
du -sh /opt/pgsql/backup/dumps/appdb_dir/
```

Check the tar format size:

```bash
ls -lh /opt/pgsql/backup/dumps/appdb.tar
```

Expected: custom and directory formats are much smaller than plain SQL and tar.

```
Expected output (yours will differ):
appdb.sql:     4.1M
appdb.dump:    412K
appdb_dir/:    432K
appdb.tar:     4.1M
```

> **Concept - Format selection guide**:
> - **Small DB, need to read/edit**: plain (`-Fp`)
> - **General purpose, single file**: custom (`-Fc`) - this is your default
> - **Large DB, need parallel dump/restore**: directory (`-Fd`)
> - **Need single file + selective restore**: tar (`-Ft`)

## 6. pg_dump options deep dive - schema and data filtering

**Run on NODE1 (pg-primary):**

### Schema only (no data)

Dump only the table definitions, with no row data:

```bash
pg_dump -Fp --schema-only appdb > /opt/pgsql/backup/dumps/appdb_schema.sql
```

(`--schema-only` = dump CREATE TABLE, CREATE INDEX, etc. but skip all the data)

Verify there are no COPY or INSERT statements (which would contain data). The `grep` command searches text for a pattern and shows only the lines that match. The `-c` flag makes `grep` count the number of matching lines instead of printing them:

```bash
grep -c "^COPY\|^INSERT" /opt/pgsql/backup/dumps/appdb_schema.sql
```

Expected: `0`.

```
Expected output:
0
```

### Data only (no DDL)

Dump only the row data, with no table definitions:

```bash
pg_dump -Fp --data-only appdb > /opt/pgsql/backup/dumps/appdb_data.sql
```

(`--data-only` = dump COPY/INSERT statements but skip CREATE TABLE, etc.)

Verify there are no CREATE statements:

```bash
grep -c "^CREATE" /opt/pgsql/backup/dumps/appdb_data.sql
```

Expected: `0`.

> **Concept - Schema vs data separation**: Dumping schema and data separately is
> useful for migrations. You can load the schema into a new version of PostgreSQL,
> then load data separately. It also helps when you need to modify the schema
> before loading data (e.g., adding partitioning).

## 7. pg_dump options deep dive - table filtering

**Run on NODE1 (pg-primary):**

### Dump a single table

Use the `-t` flag to dump only the `employees` table:

```bash
pg_dump -Fc -t employees appdb > /opt/pgsql/backup/dumps/appdb_employees.dump
```

(`-t employees` = include only the `employees` table)

### Dump multiple tables

Repeat `-t` for each table you want:

```bash
pg_dump -Fc -t pgbench_accounts -t pgbench_branches labdb > /opt/pgsql/backup/dumps/labdb_partial.dump
```

### Exclude a table

Use `-T` (uppercase) to exclude a table:

```bash
pg_dump -Fc -T pgbench_history labdb > /opt/pgsql/backup/dumps/labdb_no_history.dump
```

(`-T pgbench_history` = exclude the `pgbench_history` table. Note: lowercase `-t` includes, uppercase `-T` excludes.)

Verify pgbench_history is not in the dump:

```bash
pg_restore --list /opt/pgsql/backup/dumps/labdb_no_history.dump | grep -i "table data"
```

Expected: pgbench_history is not listed.

```
Expected output (yours will differ):
3375; 2606 16422 CONSTRAINT public pgbench_accounts pgbench_accounts_pkey postgres
3377; 0 16400 TABLE DATA public pgbench_accounts postgres
3378; 0 16397 TABLE DATA public pgbench_branches postgres
3379; 0 16403 TABLE DATA public pgbench_tellers postgres
```

### Dump by schema (namespace)

Dump only tables in the `public` schema:

```bash
pg_dump -Fc --schema=public appdb > /opt/pgsql/backup/dumps/appdb_public.dump
```

> **Concept - Surgical dumps**: In production, you often need to dump specific
> tables for data migration, debugging, or sharing with developers. The `-t` and
> `-T` flags accept patterns - `pg_dump -t 'pgbench_*'` dumps all tables starting
> with `pgbench_`. Combine with `--data-only` to extract just the rows from
> specific tables.

## 8. pg_dump options deep dive - ownership and privileges

**Run on NODE1 (pg-primary):**

Dump without ownership or permission statements. This creates a "portable" dump that works regardless of which roles exist:

```bash
pg_dump -Fp --no-owner --no-privileges appdb > /opt/pgsql/backup/dumps/appdb_portable.sql
```

(`--no-owner` = skip ALTER OWNER statements, `--no-privileges` = skip GRANT/REVOKE statements)

Verify there are no ownership or permission statements:

```bash
grep -c "ALTER.*OWNER\|^GRANT\|^REVOKE" /opt/pgsql/backup/dumps/appdb_portable.sql
```

Expected: `0`.

```
Expected output:
0
```

> **Concept - Portable dumps**: The `--no-owner` and `--no-privileges` flags
> create dumps that can be restored into any environment regardless of which
> roles exist. Essential when moving data between development, staging, and
> production where role names differ.

## 9. pg_dump with compression

**Run on NODE1 (pg-primary):**

Dump labdb with maximum compression (level 9):

```bash
pg_dump -Fc --compress=9 labdb > /opt/pgsql/backup/dumps/labdb_max_compress.dump
```

(`--compress=9` = highest compression level. Range is 0-9, where 0 is no compression.)

Dump labdb with default compression for comparison:

```bash
pg_dump -Fc labdb > /opt/pgsql/backup/dumps/labdb_default_compress.dump
```

Compare the two file sizes:

```bash
ls -lh /opt/pgsql/backup/dumps/labdb_max_compress.dump /opt/pgsql/backup/dumps/labdb_default_compress.dump
```

> **Concept - Compression tradeoffs**: Higher compression levels reduce file size
> but increase CPU time. Level 6 is the typical default and offers a good balance.
> Level 9 squeezes a few more percent but takes noticeably longer. For large
> databases, the difference between 6 and 9 is rarely worth the extra CPU time.

## 10. pg_dumpall - full cluster dump

**Run on NODE1 (pg-primary):**

pg_dumpall dumps every database plus cluster-level objects (roles, tablespaces):

```bash
pg_dumpall > /opt/pgsql/backup/dumps/full_cluster.sql
```

Check the size:

```bash
ls -lh /opt/pgsql/backup/dumps/full_cluster.sql
```

Look at the first 50 lines to see what is included:

```bash
head -50 /opt/pgsql/backup/dumps/full_cluster.sql
```

Expected: `CREATE ROLE` statements, then `CREATE DATABASE`, then the contents of each database.

```
Expected output (yours will differ):
--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS;
```

> **Concept - pg_dumpall limitations**: pg_dumpall only produces plain SQL format.
> It cannot produce custom or directory format. For large clusters, the better
> approach is `pg_dumpall --globals-only` (to get roles and tablespaces) combined
> with individual `pg_dump -Fc` for each database. This gives you the best of
> both worlds - cluster globals plus per-database custom format dumps.

## 11. pg_dumpall - globals only

**Run on NODE1 (pg-primary):**

Dump only the cluster-level objects (roles, tablespaces) without any database contents:

```bash
pg_dumpall --globals-only > /opt/pgsql/backup/dumps/globals.sql
```

Inspect the output:

```bash
cat /opt/pgsql/backup/dumps/globals.sql
```

Expected: only `CREATE ROLE` and related statements - no database contents.

> **Concept - Globals-only pattern**: The standard backup strategy for
> multi-database clusters is:
> 1. `pg_dumpall --globals-only > globals.sql` (roles, tablespaces)
> 2. `pg_dump -Fc dbname > dbname.dump` for each database
>
> This gives you selective, parallel-capable restores per database while still
> capturing cluster-wide objects that pg_dump alone misses.

## 12. Dump to NODE2 over SSH

**Run on NODE1 (pg-primary):**

Send a backup directly to the backup server without storing it locally. This pipes the output of pg_dump through an SSH connection to NODE2.

Still as the postgres user, dump appdb and stream it directly to NODE2:

```bash
pg_dump -Fc appdb | ssh postgres@pg-backup "cat > /opt/pgsql/backup/logical/appdb.dump"
```

(This pipes pg_dump's output through SSH to NODE2, where `cat >` writes it to a file. We run this as the postgres user because postgres has the SSH keys to connect to NODE2.)

Now dump labdb to NODE2:

```bash
pg_dump -Fc labdb | ssh postgres@pg-backup "cat > /opt/pgsql/backup/logical/labdb.dump"
```

Now dump blobdb to NODE2:

```bash
pg_dump -Fc blobdb | ssh postgres@pg-backup "cat > /opt/pgsql/backup/logical/blobdb.dump"
```

Dump globals to NODE2:

```bash
pg_dumpall --globals-only | ssh postgres@pg-backup "cat > /opt/pgsql/backup/logical/globals.sql"
```

Verify the files arrived on NODE2:

```bash
ssh postgres@pg-backup "ls -lh /opt/pgsql/backup/logical/"
```

Expected: `labdb.dump`, `appdb.dump`, `blobdb.dump`, `globals.sql` all present.

```
Expected output (yours will differ):
total 1.5G
-rw-r--r--. 1 postgres postgres 407K Apr 19 01:24 appdb.dump
-rw-r--r--. 1 postgres postgres  40K Apr 19 01:24 blobdb.dump
-rw-r--r--. 1 postgres postgres  671 Apr 19 01:24 globals.sql
-rw-r--r--. 1 postgres postgres 1.4G Apr 19 01:24 labdb.dump
```

> **Concept - Stream to remote**: Piping pg_dump through SSH avoids writing the
> dump to local disk on the primary. This is critical when the primary's disk is
> nearly full - you cannot afford to temporarily double your storage usage. The
> tradeoff is that a network interruption means you restart the entire dump.

## 13. Dump the blobdb to verify binary data handling

**Run on NODE1 (pg-primary):**

Still as the postgres user, dump blobdb in custom format:

```bash
pg_dump -Fc blobdb > /opt/pgsql/backup/dumps/blobdb.dump
```

List the objects in the dump:

```bash
pg_restore --list /opt/pgsql/backup/dumps/blobdb.dump
```

Expected: `TABLE DATA documents` appears in the listing.

Compare the dump file size to the actual database size:

Check the actual database size. The `-tAc` flags give tuples only, unaligned output, and run a command - producing a clean value without table headers:

```bash
psql -tAc "SELECT pg_size_pretty(pg_database_size('blobdb'));"
```

```
Expected output (yours will differ):
8855 kB
```

Check the dump file size:

```bash
ls -lh /opt/pgsql/backup/dumps/blobdb.dump
```

```
Expected output (yours will differ):
-rw-r--r--. 1 postgres postgres 40K Apr 19 01:24 /opt/pgsql/backup/dumps/blobdb.dump
```

The dump is much smaller than the database itself due to compression.

Exit back to ec2-user:

```bash
exit
```

**You are now back to the ec2-user.**

> **Concept - Binary data compression**: Custom format compresses bytea data
> effectively. A dump of binary data is often smaller than the database itself
> because PostgreSQL stores bytea with overhead (TOAST, page headers) that the
> dump format eliminates.

---

## Checkpoint

- [x] Dumped appdb in all four formats (plain, custom, directory, tar)
- [x] Dumped labdb with parallel directory format
- [x] Understand when to use each format
- [x] Used --schema-only and --data-only
- [x] Used -t (include table) and -T (exclude table)
- [x] Used --no-owner and --no-privileges
- [x] Used --compress for custom format
- [x] Ran pg_dumpall for full cluster dump
- [x] Ran pg_dumpall --globals-only
- [x] Dumped all databases to NODE2 over SSH
- [x] Verified binary data handling with blobdb

Proceed to `04-logical-restore.md`.
