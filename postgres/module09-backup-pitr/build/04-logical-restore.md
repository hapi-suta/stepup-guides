# Build 04: Logical Restore

Learn every pg_restore and psql restore option. By the end of this guide you can
restore full databases, single tables, and custom object subsets from any dump format.

All commands run on NODE1 unless noted otherwise.

---

## 1. Restore plain SQL format with psql

**Run on NODE1 (pg-primary):**

Create a fresh database and restore the plain SQL dump into it.

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Create an empty database to restore into:

```bash
psql -c "CREATE DATABASE appdb_restored;"
```

`-c` runs the SQL command in quotes and exits immediately.

Restore the plain SQL dump. Since plain dumps are just SQL scripts, we use `psql` to replay them. The `<` operator feeds a file's contents into a command as input:

```bash
psql -d appdb_restored < /opt/pgsql/backup/dumps/appdb.sql
```

`-d appdb_restored` connects to the `appdb_restored` database.

```
Expected output (yours will differ):
SET
SET
SET
SET
SET
...
CREATE TABLE
ALTER TABLE
COPY 100000
...
```

Verify the data was restored:

```bash
psql -d appdb_restored -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

```
Expected output:
 count
--------
 100000
(1 row)
```

> **Concept - psql for plain format**: Plain SQL dumps are just SQL scripts.
> You replay them with psql. Errors are printed to stderr but do not stop
> execution by default. Add `--set ON_ERROR_STOP=on` to halt on the first error.

## 2. Restore custom format with pg_restore

**Run on NODE1 (pg-primary):**

Create an empty database:

```bash
psql -c "CREATE DATABASE appdb_custom;"
```

Restore the custom format dump using pg_restore:

```bash
pg_restore -d appdb_custom /opt/pgsql/backup/dumps/appdb.dump
```

(`-d appdb_custom` = target database, then the path to the dump file)

Verify:

```bash
psql -d appdb_custom -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

```
Expected output:
 count
--------
 100000
(1 row)
```

## 3. pg_restore with --create

**Run on NODE1 (pg-primary):**

Instead of creating the database manually, let pg_restore do it automatically from the dump metadata.

First, drop the database we just created so --create can recreate it:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_custom;"
```

Restore with --create. Notice we connect to the `postgres` database (not appdb):

```bash
pg_restore --create -d postgres /opt/pgsql/backup/dumps/appdb.dump
```

--create tells pg_restore to create the database first. It reads the original database name from inside the dump and issues a CREATE DATABASE before restoring objects. You must connect to a different database (like `postgres`) since you cannot create a database while connected to it.

> **Concept - The --create flag**: When you use `--create`, pg_restore issues
> `CREATE DATABASE` followed by `\connect` before restoring objects. You must
> connect to a different database (like `postgres`) since you cannot create a
> database while connected to it. The database name comes from inside the dump.

Verify:

```bash
psql -d appdb -c "SELECT count(*) FROM employees;"
```

Expected: `100000`. Note - it restores to the original name `appdb` because
that is what is in the dump. If `appdb` already exists, this will fail.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_custom;"
```

## 4. pg_restore with --clean and --if-exists

**Run on NODE1 (pg-primary):**

Drop existing objects before restoring - useful for refreshing a database.

Create a test database:

```bash
psql -c "CREATE DATABASE appdb_clean_test;"
```

Restore with --clean and --if-exists:

```bash
pg_restore -d appdb_clean_test --clean --if-exists /opt/pgsql/backup/dumps/appdb.dump
```

--clean tells pg_restore to drop existing objects before recreating them. --if-exists prevents errors if the objects don't exist yet. Always pair these two flags together.

> **Concept - Clean restore**: `--clean` adds DROP statements before each CREATE.
> `--if-exists` adds IF EXISTS to those DROPs so they do not error on the first
> run (when objects do not exist yet). Always pair these two flags together.

Verify:

```bash
psql -d appdb_clean_test -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_clean_test;"
```

## 5. Restore schema only, then data only

**Run on NODE1 (pg-primary):**

This two-step approach lets you load the table structure first, optionally modify it, then load the data.

Create the database:

```bash
psql -c "CREATE DATABASE appdb_split;"
```

Step 1 - restore just the schema (table definitions, no data):

```bash
pg_restore -d appdb_split --schema-only /opt/pgsql/backup/dumps/appdb.dump
```

Verify the tables exist but are empty:

```bash
psql -d appdb_split -c "SELECT count(*) FROM employees;"
```

Expected: `0`.

Step 2 - restore just the data:

```bash
pg_restore -d appdb_split --data-only /opt/pgsql/backup/dumps/appdb.dump
```

Verify the data is loaded:

```bash
psql -d appdb_split -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

> **Concept - Split restore**: Restoring schema and data separately is useful when
> you need to modify the schema between steps. For example, adding partitioning
> before loading data, or disabling triggers during a large data load.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_split;"
```

## 6. Restore a single table from a full dump

**Run on NODE1 (pg-primary):**

Restore only the employees table from the full appdb dump. This is one of the biggest advantages of custom format over plain SQL.

Create the database:

```bash
psql -c "CREATE DATABASE appdb_partial;"
```

Restore just the employees table (both schema and data):

```bash
pg_restore -d appdb_partial -t employees /opt/pgsql/backup/dumps/appdb.dump
```

(`-t employees` = restore only the `employees` table)

Verify employees was restored:

```bash
psql -d appdb_partial -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

Verify that the departments table does NOT exist (it was not included in the restore):

```bash
psql -d appdb_partial -c "SELECT count(*) FROM departments;" 2>&1
```

Expected: `ERROR: relation "departments" does not exist`.

```
Expected output:
ERROR:  relation "departments" does not exist
LINE 1: SELECT count(*) FROM departments;
                             ^
```

> **Concept - Selective restore**: The `-t` flag in pg_restore is surgical.
> Combined with a custom or directory format dump, you can extract exactly the
> tables you need. This is why custom format (`-Fc`) is superior to plain SQL -
> you dump once and restore selectively as many times as needed.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_partial;"
```

## 7. Custom restore order with --list and --use-list

**Run on NODE1 (pg-primary):**

This two-step workflow gives you total control over what gets restored and in what order.

Step 1 - generate the table of contents from the dump file:

```bash
pg_restore --list /opt/pgsql/backup/dumps/appdb.dump > /tmp/appdb_toc.list
```

View the list:

```bash
cat /tmp/appdb_toc.list
```

Expected: numbered entries like:
```
;
; Archive created at ...
;
; Selected TOC Entries:
;
232; 1259 16389 TABLE public employees postgres
...
```

Step 2 - edit the list to comment out entries you don't want. We will comment out any SEQUENCE SET entries by adding a `;` at the start of those lines.

Open the file in vim:

```bash
vi /tmp/appdb_toc.list
```

Inside vim:

1. Type `/SEQUENCE SET` and press Enter to find the first SEQUENCE SET line.
2. Press `I` (capital i) to move to the beginning of the line and enter insert mode.
3. Type `;` to comment out that line, then press Escape.
4. If there are more SEQUENCE SET lines, press `n` to jump to the next match and repeat steps 2-3.
5. When all SEQUENCE SET lines are commented out, type `:wq` and press Enter to save and exit.

Lines starting with `;` are treated as comments and will be skipped during restore.

Step 3 - restore using the edited list:

```bash
psql -c "CREATE DATABASE appdb_custom_order;"
```

```bash
pg_restore -d appdb_custom_order --use-list=/tmp/appdb_toc.list /opt/pgsql/backup/dumps/appdb.dump
```

(`--use-list` = only restore the entries in this file, skipping commented lines)

Verify:

```bash
psql -d appdb_custom_order -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

> **Concept - Custom restore order**: The `--list` / `--use-list` workflow gives
> you total control over what gets restored and in what order. Comment lines
> (starting with `;`) are skipped. You can reorder entries, skip problematic
> objects, or restore only specific types (TABLE DATA, INDEX, CONSTRAINT).
> This is your scalpel for complex restore scenarios.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_custom_order;"
```

## 8. Parallel restore with --jobs

**Run on NODE1 (pg-primary):**

Restore the labdb directory dump using multiple workers to speed up the process.

Create the database:

```bash
psql -c "CREATE DATABASE labdb_parallel;"
```

Restore with 4 parallel workers:

```bash
pg_restore -d labdb_parallel -j 4 /opt/pgsql/backup/dumps/labdb_dir/
```

(`-j 4` = use 4 workers to restore tables simultaneously)

> **Concept - Parallel restore**: The `-j` flag spawns multiple workers that
> restore tables simultaneously. It only works with directory or custom format.
> Each worker restores a different table's data in parallel, then indexes and
> constraints are rebuilt. For large databases, this cuts restore time dramatically.
> Set `-j` to the number of CPU cores.

Verify:

```bash
psql -d labdb_parallel -c "SELECT count(*) FROM pgbench_accounts;"
```

Expected: `33000000`.

```
Expected output:
   count
----------
 33000000
(1 row)
```

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS labdb_parallel;"
```

## 9. Restore with --section

**Run on NODE1 (pg-primary):**

pg_restore organizes dumps into three sections: pre-data, data, and post-data. You can restore each section independently.

Create the database:

```bash
psql -c "CREATE DATABASE appdb_sections;"
```

Restore pre-data (table definitions, sequences - no indexes or constraints yet):

```bash
pg_restore -d appdb_sections --section=pre-data /opt/pgsql/backup/dumps/appdb.dump
```

Restore data (the actual rows):

```bash
pg_restore -d appdb_sections --section=data /opt/pgsql/backup/dumps/appdb.dump
```

Restore post-data (indexes, constraints, triggers):

```bash
pg_restore -d appdb_sections --section=post-data /opt/pgsql/backup/dumps/appdb.dump
```

Verify:

```bash
psql -d appdb_sections -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

> **Concept - Section-based restore**: The three sections map to pg_dump's internal
> organization:
> - **pre-data**: CREATE TABLE, CREATE SEQUENCE, CREATE TYPE
> - **data**: COPY or INSERT statements
> - **post-data**: CREATE INDEX, ALTER TABLE ADD CONSTRAINT, CREATE TRIGGER
>
> Restoring data before indexes is faster because PostgreSQL does not update indexes
> during bulk COPY. This is why pg_restore defers index creation to post-data.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_sections;"
```

## 10. Restore with --no-owner and --no-privileges

**Run on NODE1 (pg-primary):**

Restore without trying to set ownership. Useful when the original roles don't exist in your environment.

Create the database:

```bash
psql -c "CREATE DATABASE appdb_portable;"
```

Restore, skipping ownership and permission statements:

```bash
pg_restore -d appdb_portable --no-owner --no-privileges /opt/pgsql/backup/dumps/appdb.dump
```

(`--no-owner` = skip ALTER OWNER statements, `--no-privileges` = skip GRANT/REVOKE. All objects will be owned by the user running the restore.)

> **Concept - Portable restores**: When restoring a dump from production into
> development, the production roles may not exist. `--no-owner` skips
> `ALTER OWNER` statements. `--no-privileges` skips `GRANT` and `REVOKE`.
> All objects will be owned by the user running the restore.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_portable;"
```

## 11. Restore to a different database name

**Run on NODE1 (pg-primary):**

The dump contains the original database name, but you can restore to any name you want.

Create a database with a different name:

```bash
psql -c "CREATE DATABASE appdb_renamed;"
```

Restore into it:

```bash
pg_restore -d appdb_renamed /opt/pgsql/backup/dumps/appdb.dump
```

Verify:

```bash
psql -d appdb_renamed -c "SELECT count(*) FROM employees;"
```

Expected: `100000`. The data is identical but lives in `appdb_renamed`.

> **Concept - Name independence**: Custom format dumps are target-agnostic. The
> `-d` flag tells pg_restore where to put the data. This is how you clone
> databases: dump production, restore to `staging_db`. The original database
> name inside the dump is only used with `--create`.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_renamed;"
```

## 12. Cross-version considerations

**Run on NODE1 (pg-primary):**

Check your pg_dump version:

```bash
pg_dump --version
```

```
Expected output:
pg_dump (PostgreSQL) 16.13
```

Check the server version:

```bash
psql -c "SELECT version();"
```

```
Expected output (yours will differ):
                                                  version
------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.13 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.5.0 20240719 (Red Hat 11.5.0-11), 64-bit
(1 row)
```

These should match. If they don't, you could run into compatibility issues.

> **Concept - Cross-version restores**: pg_dump can dump from older servers using
> a newer pg_dump binary (pg_dump 16 can dump from PG 14). But pg_restore from
> a newer dump to an older server may fail if the dump uses new syntax. The
> golden rule - always use a pg_dump/pg_restore version that is >= the target
> server version. When migrating across major versions, this is the recommended
> path:
> 1. Install the newer PG version
> 2. Use the newer pg_dump to dump from the older server
> 3. Use the newer pg_restore to load into the newer server

## 13. Restore from NODE2

**Run on NODE1 (pg-primary):**

Verify you can restore from dumps stored on the backup server.

Exit back to ec2-user:

```bash
exit
```

Switch to the postgres user (we need the postgres SSH keys to connect to NODE2):

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Copy the dump from NODE2 to a temp location on NODE1. `scp` is secure copy over SSH - this pulls the file from NODE2 to NODE1:

```bash
scp postgres@pg-backup:/opt/pgsql/backup/logical/appdb.dump /tmp/appdb_from_backup.dump
```

```
Expected output (yours will differ):
appdb.dump     100%  407KB   5.2MB/s   00:00
```

Stay as the postgres user for the next steps.

Create the target database:

```bash
psql -c "CREATE DATABASE appdb_from_backup;"
```

Restore from the copied dump:

```bash
pg_restore -d appdb_from_backup /tmp/appdb_from_backup.dump
```

Verify:

```bash
psql -d appdb_from_backup -c "SELECT count(*) FROM employees;"
```

Expected: `100000`.

Clean up:

```bash
psql -c "DROP DATABASE IF EXISTS appdb_from_backup;"
```

```bash
psql -c "DROP DATABASE IF EXISTS appdb_restored;"
```

Exit back to ec2-user:

```bash
exit
```

---

## Checkpoint

- [x] Restored plain SQL dump with psql
- [x] Restored custom format with pg_restore
- [x] Used --create to auto-create database
- [x] Used --clean --if-exists for idempotent restore
- [x] Restored --schema-only and --data-only separately
- [x] Restored a single table from a full dump
- [x] Used --list + --use-list for custom restore order
- [x] Used --jobs for parallel restore
- [x] Used --section for pre-data/data/post-data control
- [x] Used --no-owner and --no-privileges
- [x] Restored to a different database name
- [x] Understand cross-version restore rules
- [x] Restored from a dump stored on NODE2

Proceed to `05-physical-backup.md`.
