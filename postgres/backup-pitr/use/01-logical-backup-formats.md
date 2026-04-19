# Exercise 01 - Logical Backup Formats

**Time estimate:** 20-30 minutes
**Prerequisites:** BUILD phase complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb (5GB pgbench data, scale 330), appdb (100K employees), blobdb (1000 documents). NODE2 (pg-backup) accessible via SSH.

---

## Objective

Learn every pg_dump output format, understand what each produces, and know when to use each one. By the end of this exercise, you should be able to choose the right format for any backup scenario without referencing this guide.

---

## Step 1 - Dump labdb in Plain Format

On **NODE1** (pg-primary):

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb -F plain -f /opt/pgsql/backup/labdb_plain.sql
```

Examine the output:

```bash
head -50 /opt/pgsql/backup/labdb_plain.sql
```

**Expected:** A readable SQL file starting with `--` comments, followed by `SET` statements, `CREATE TABLE`, `COPY` data blocks, and `ALTER TABLE` for constraints. Because labdb has ~33M rows in pgbench_accounts (scale 330), the COPY block for that table alone is massive.

> **Concept:** Plain format produces a raw SQL script. It is human-readable and can be restored with `psql` (not `pg_restore`). This is the only format you can open in a text editor to inspect exactly what will happen during restore. The downside - you cannot selectively restore individual tables from a plain dump.

---

## Step 2 - Dump labdb in Custom Format

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb -F custom -f /opt/pgsql/backup/labdb_custom.dump
```

Examine the table of contents:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/labdb_custom.dump
```

**Expected:** A numbered list of objects showing the order they will be restored - schemas, tables, data, indexes, constraints, triggers. You will see pgbench_accounts, pgbench_branches, pgbench_history, and pgbench_tellers among the entries.

```
;
; Archive created at 2026-04-17 10:00:00 UTC
;     dbname: labdb
;
; Selected TOC Entries:
;
200; 1259 16384 TABLE public pgbench_accounts postgres
201; 1259 16390 TABLE public pgbench_branches postgres
202; 1259 16395 TABLE public pgbench_history postgres
203; 1259 16400 TABLE public pgbench_tellers postgres
...
```

> **Concept:** Custom format is compressed by default and supports selective restore. The `--list` flag shows the table of contents (TOC) - a manifest of every object in the dump. You can edit this list and use `--use-list` to restore only specific objects. This is the most versatile format for production use.

---

## Step 3 - Dump labdb in Directory Format

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb -F directory -f /opt/pgsql/backup/labdb_dir
```

Examine the directory structure:

```bash
ls -la /opt/pgsql/backup/labdb_dir/
```

**Expected:**

```
total 540000
drwx------  2 postgres postgres     4096 Apr 17 10:00 .
drwxr-xr-x  4 postgres postgres     4096 Apr 17 10:00 ..
-rw-------  1 postgres postgres      456 Apr 17 10:00 toc.dat
-rw-------  1 postgres postgres 536870912 Apr 17 10:00 3456.dat.gz
...
```

Each table's data is stored in a separate compressed file. The `toc.dat` file is the table of contents. The pgbench_accounts file will be by far the largest (~700MB-1GB compressed).

> **Concept:** Directory format is the only format that supports parallel dump and restore (`--jobs`). Each table goes into its own file, so multiple worker processes can dump or restore different tables simultaneously. For databases with many large tables, this dramatically reduces backup and restore time.

---

## Step 4 - Dump labdb in Tar Format

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb -F tar -f /opt/pgsql/backup/labdb_tar.tar
```

Examine the archive:

```bash
tar tf /opt/pgsql/backup/labdb_tar.tar | head -20
```

**Expected:** A list of files inside the tar archive - `toc.dat` plus numbered `.dat` files for each table's data.

---

## Step 5 - Compare File Sizes

```bash
ls -lh /opt/pgsql/backup/labdb_plain.sql /opt/pgsql/backup/labdb_custom.dump /opt/pgsql/backup/labdb_tar.tar
du -sh /opt/pgsql/backup/labdb_dir
```

**Expected:** With the 5GB pgbench dataset:
- **Plain** (`labdb_plain.sql`): ~5.0GB (uncompressed SQL text)
- **Custom** (`labdb_custom.dump`): ~850MB-1.2GB (compressed by default)
- **Directory** (`labdb_dir`): ~850MB-1.2GB (similar to custom, compressed)
- **Tar** (`labdb_tar.tar`): ~5.0GB (uncompressed by default)

Custom format is the smallest. Plain SQL and tar are the largest.

> **Concept:** Custom and directory formats use zlib compression by default. Plain format is uncompressed SQL text. Tar format does not compress by default (you can pipe through gzip externally). In production, storage cost matters - custom or directory format saves significant disk space on large databases. On a 5GB dataset like this one, the compression ratio is roughly 4-6x.

---

## Step 6 - Parallel Dump With Directory Format

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d appdb -F directory --jobs=4 -f /opt/pgsql/backup/appdb_parallel
```

```bash
ls -la /opt/pgsql/backup/appdb_parallel/
```

**Expected:** Multiple `.dat.gz` files, one per table. With `--jobs=4`, up to 4 tables are dumped simultaneously.

> **Concept:** Parallel dump only works with directory format. The `--jobs` flag specifies how many tables to dump concurrently. For a database with hundreds of tables, `--jobs=4` or `--jobs=8` can cut dump time dramatically. The number should not exceed your available CPU cores or the `max_connections` limit.

---

## Step 7 - Schema-Only vs Data-Only Dumps

Schema only:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb --schema-only -f /opt/pgsql/backup/labdb_schema.sql
```

Data only:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb --data-only -f /opt/pgsql/backup/labdb_data.sql
```

Compare:

```bash
wc -l /opt/pgsql/backup/labdb_schema.sql /opt/pgsql/backup/labdb_data.sql /opt/pgsql/backup/labdb_plain.sql
```

**Expected:** The schema file contains only DDL (CREATE TABLE, indexes, constraints) - a few hundred lines. The data file contains only COPY statements - millions of lines for the 33M pgbench_accounts rows. Together they roughly equal the full dump.

> **Concept:** Schema-only dumps are invaluable for version control - commit your schema to git without the data. Data-only dumps are useful when you need to reload data into an existing schema (after a schema migration, for example). In production, many teams keep nightly schema-only dumps in git as a safety net.

---

## Step 8 - Dump a Single Table

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d labdb -t pgbench_accounts -F custom -f /opt/pgsql/backup/pgbench_accounts_only.dump
```

Verify the contents:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/pgbench_accounts_only.dump
```

**Expected:** Only entries related to the pgbench_accounts table - the table definition, its data, and indexes.

---

## Step 9 - Dump With Exclusions

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -d appdb --exclude-table=orders -F custom -f /opt/pgsql/backup/appdb_no_orders.dump
```

Verify:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/appdb_no_orders.dump | grep -i orders
```

**Expected:** No output - the orders table is excluded from the dump.

> **Concept:** `--exclude-table` accepts patterns. You can use `--exclude-table='temp_*'` to skip all tables matching a wildcard. This is useful when your database has large staging or temp tables you do not need to back up.

---

## Step 10 - Dump Global Objects With pg_dumpall

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dumpall --globals-only -f /opt/pgsql/backup/globals.sql
```

Examine:

```bash
cat /opt/pgsql/backup/globals.sql
```

**Expected:** `CREATE ROLE` statements for every database role, plus `ALTER ROLE` for role attributes and passwords. No table data, no database-specific objects.

> **Concept:** `pg_dump` operates on a single database and does not capture roles, tablespaces, or other cluster-wide objects. `pg_dumpall --globals-only` fills that gap. In production, you should always pair your database dumps with a globals dump - otherwise, a full restore will fail because the owning roles do not exist yet.

---

## Step 11 - Think: When Would You Use Each Format?

Consider these scenarios and match each to the best format:

| Scenario | Best Format |
|---|---|
| Quick backup of a small dev database | Plain |
| Production backup of a 200GB database | Directory (parallel) |
| Backup you need to selectively restore from | Custom |
| Backup going to a tape archive system | Tar |
| Schema versioning in git | Plain (schema-only) |
| Migrating between PostgreSQL major versions | Custom or Plain |

---

## Checkpoint

Before continuing, confirm:
- [ ] You dumped labdb in all 4 formats (plain, custom, directory, tar)
- [ ] You compared file sizes and understand why custom is smallest
- [ ] You examined plain SQL output and can read what pg_dump generates
- [ ] You used `pg_restore --list` to view the custom format table of contents
- [ ] You performed a parallel dump with `--jobs=4`
- [ ] You created schema-only and data-only dumps
- [ ] You dumped a single table and used `--exclude-table`
- [ ] You captured global objects with `pg_dumpall --globals-only`
- [ ] You can explain when to use each format

---

**Next:** [02 - Selective Restore](02-selective-restore.md)
