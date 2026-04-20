# Exercise 02 - Selective Restore

**Time estimate:** 25-35 minutes
**Prerequisites:** Exercise 01 complete - you have custom format dumps of labdb and appdb in `/opt/pgsql/backup/`

---

## Objective

Master selective restore techniques using pg_restore. By the end of this exercise, you should be able to extract any combination of objects from a full backup and restore them precisely where you need them.

---

## Step 1 - Create a Fresh Custom Format Dump of appdb

On **NODE1** (pg-primary):

Switch to the postgres user. All restore commands run as postgres.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_dump -d appdb -F custom -f /opt/pgsql/backup/appdb_full.dump
```

Verify the dump contents:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/appdb_full.dump
```

**Expected:** A numbered list showing all tables (employees, plus any other appdb tables), their data, indexes, constraints, and sequences.

---

## Step 2 - Generate and Edit the Table of Contents

Export the TOC to a file:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/appdb_full.dump > /opt/pgsql/backup/appdb_toc.txt
```

View it:

```bash
cat /opt/pgsql/backup/appdb_toc.txt
```

**Expected:** Lines like:

```
;
; Archive created at 2026-04-17 10:15:00 UTC
;     dbname: appdb
;
200; 1259 16385 TABLE public employees postgres
201; 0 16385 TABLE DATA public employees postgres
...
```

Now edit the file to select only the employees table. Comment out everything except employees-related entries by adding a semicolon at the start of each unwanted line:

```bash
cp /opt/pgsql/backup/appdb_toc.txt /opt/pgsql/backup/appdb_toc_employees.txt
```

Edit `/opt/pgsql/backup/appdb_toc_employees.txt` and comment out (`;`) all lines that do NOT relate to the employees table.

> **Concept:** The `--use-list` technique is one of the most powerful features of custom format dumps. By editing the TOC file, you have surgical control over exactly which objects get restored. This is how experienced DBAs extract specific tables from a full backup without restoring the entire database. You can also reorder lines to change the restore sequence.

---

## Step 3 - Restore Using the Edited List

Create a target database:

```bash
/usr/pgsql-16/bin/psql -c "CREATE DATABASE appdb_selective;"
```

Restore only the employees table:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_selective --use-list=/opt/pgsql/backup/appdb_toc_employees.txt /opt/pgsql/backup/appdb_full.dump
```

Verify the table was restored:

```bash
/usr/pgsql-16/bin/psql -d appdb_selective -c "\dt"
```

**Expected:** Only the employees table exists.

Confirm the row count matches the original:

```bash
/usr/pgsql-16/bin/psql -d appdb_selective -c "SELECT count(*) FROM employees;"
```

**Expected:** 100,000 rows - the same count as in the original appdb.

---

## Step 4 - Restore a Single Table Directly

Create another target database:

```bash
/usr/pgsql-16/bin/psql -c "CREATE DATABASE appdb_single;"
```

Restore just the employees table without editing a TOC file:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_single -t employees /opt/pgsql/backup/appdb_full.dump
```

List the tables in the restored database:

```bash
/usr/pgsql-16/bin/psql -d appdb_single -c "\dt"
```

Expected output (yours will differ):

```
             List of relations
 Schema |   Name    | Type  |  Owner
--------+-----------+-------+----------
 public | employees | table | postgres
(1 row)
```

Confirm all rows are present:

```bash
/usr/pgsql-16/bin/psql -d appdb_single -c "SELECT count(*) FROM employees;"
```

**Expected:** 100,000 rows - same as the original appdb.

> **Concept:** The `-t` flag is a shortcut for single-table restore. It is simpler than `--use-list` but less flexible - you cannot control which associated objects (indexes, constraints) come along. For precise control, `--use-list` is better. For quick single-table extraction, `-t` works well.

---

## Step 5 - Two-Step Restore: Schema First, Then Data

Create another target database:

```bash
/usr/pgsql-16/bin/psql -c "CREATE DATABASE appdb_twostep;"
```

Step one - restore schema only:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_twostep --schema-only /opt/pgsql/backup/appdb_full.dump
```

Confirm the tables exist:

```bash
/usr/pgsql-16/bin/psql -d appdb_twostep -c "\dt"
```

Verify the tables are empty:

```bash
/usr/pgsql-16/bin/psql -d appdb_twostep -c "SELECT count(*) FROM employees;"
```

**Expected:** All tables exist, all counts are 0.

Step two - restore data only:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_twostep --data-only /opt/pgsql/backup/appdb_full.dump
```

Verify the data loaded correctly:

```bash
/usr/pgsql-16/bin/psql -d appdb_twostep -c "SELECT count(*) FROM employees;"
```

**Expected:** 100,000 rows - matches the original appdb.

> **Concept:** Two-step restore is useful when you need to modify the schema before loading data - for example, adding partitioning, changing column types, or adding indexes after the data load for faster restore. Many production restore procedures use this pattern: restore schema, make schema adjustments, then load data.

---

## Step 6 - Section-Based Restore

Create another target database:

```bash
/usr/pgsql-16/bin/psql -c "CREATE DATABASE appdb_sections;"
```

PostgreSQL divides a dump into three sections. Restore each separately.

Restore pre-data - this creates tables, types, and functions (no indexes, no constraints):

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_sections --section=pre-data /opt/pgsql/backup/appdb_full.dump
```

Restore data - this runs the COPY statements to load rows:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_sections --section=data /opt/pgsql/backup/appdb_full.dump
```

Restore post-data - this creates indexes, constraints, and triggers:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_sections --section=post-data /opt/pgsql/backup/appdb_full.dump
```

List the restored tables:

```bash
/usr/pgsql-16/bin/psql -d appdb_sections -c "\dt"
```

List the restored indexes:

```bash
/usr/pgsql-16/bin/psql -d appdb_sections -c "\di"
```

Verify the row count:

```bash
/usr/pgsql-16/bin/psql -d appdb_sections -c "SELECT count(*) FROM employees;"
```

**Expected:** All tables, all indexes, all data present - identical to the original.

> **Concept:** Section-based restore gives you the fastest possible data load. By deferring indexes and constraints to post-data, the COPY operations do not need to update indexes or check constraints on every row. This is the default behavior of pg_restore, but understanding the sections helps when troubleshooting restore failures - a post-data failure (index creation) does not mean your data is missing.

---

## Step 7 - Restore With --no-owner and --no-privileges

This is the most common pattern when migrating between environments (dev to staging, on-prem to cloud):

```bash
/usr/pgsql-16/bin/createdb appdb_migration
```

Restore with ownership and privilege flags stripped:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_migration \
  --no-owner \
  --no-privileges \
  /opt/pgsql/backup/appdb_full.dump
```

List the restored tables:

```bash
/usr/pgsql-16/bin/psql -d appdb_migration -c "\dt"
```

Confirm the table owner is the current user, not the original dump owner:

```bash
/usr/pgsql-16/bin/psql -d appdb_migration -c "SELECT tableowner FROM pg_tables WHERE schemaname = 'public';"
```

**Expected:** All tables are owned by the user who ran pg_restore (not the original owner from the dump).

> **Concept:** In production, the source and target environments often have different role names. `--no-owner` skips the `ALTER TABLE ... OWNER TO` commands. `--no-privileges` skips `GRANT` and `REVOKE` commands. Without these flags, pg_restore will emit warnings about missing roles. These two flags should be your default when restoring across environments.

---

## Step 8 - Cross-Database Restore

Dump from appdb, restore into a completely new database:

```bash
/usr/pgsql-16/bin/createdb appdb_copy
```

Restore the full dump into the new database:

```bash
/usr/pgsql-16/bin/pg_restore -d appdb_copy \
  --no-owner \
  --no-privileges \
  /opt/pgsql/backup/appdb_full.dump
```

Verify data integrity by comparing row counts. Check the original first:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT 'employees' AS tbl, count(*) FROM employees;"
```

Now check the copy:

```bash
/usr/pgsql-16/bin/psql -d appdb_copy -c "SELECT 'employees' AS tbl, count(*) FROM employees;"
```

**Expected:** Identical row counts in both databases (100,000 employees).

> **Concept:** Cross-database restore is one of the key advantages of logical backups. You can restore a dump into any database with any name on any PostgreSQL server (even a different major version, within reason). Physical backups cannot do this - they restore the entire cluster exactly as it was.

---

## Step 9 - Verify Foreign Key Integrity After Restore

After restoring appdb_copy, verify that foreign key relationships are intact:

```bash
/usr/pgsql-16/bin/psql -d appdb_copy -c "
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY';
"
```

**Expected:** Any foreign key constraints defined in appdb are present and valid.

Test referential integrity (if foreign keys exist):

```bash
/usr/pgsql-16/bin/psql -d appdb_copy -c "
INSERT INTO employees (name, department, hired_at)
VALUES ('fk_test_user', 'NonexistentDept', NOW());
"
```

**Expected:** If there is a department foreign key, this fails with a foreign key violation. If there is no FK on department, the insert succeeds - this confirms the schema matches the original.

---

## Step 10 - Clean Up Test Databases

Drop each test database one at a time:

```bash
/usr/pgsql-16/bin/psql -c "DROP DATABASE IF EXISTS appdb_selective;"
```

```bash
/usr/pgsql-16/bin/psql -c "DROP DATABASE IF EXISTS appdb_single;"
```

```bash
/usr/pgsql-16/bin/psql -c "DROP DATABASE IF EXISTS appdb_twostep;"
```

```bash
/usr/pgsql-16/bin/psql -c "DROP DATABASE IF EXISTS appdb_sections;"
```

```bash
/usr/pgsql-16/bin/psql -c "DROP DATABASE IF EXISTS appdb_migration;"
```

```bash
/usr/pgsql-16/bin/psql -c "DROP DATABASE IF EXISTS appdb_copy;"
```

Switch back to your regular user:

```bash
exit
```

---

## Checkpoint

Before continuing, confirm:
- [ ] You created a custom format dump and listed its contents
- [ ] You edited a TOC file and restored only specific tables with `--use-list`
- [ ] You restored a single table with the `-t` flag
- [ ] You performed a two-step restore (schema-only, then data-only)
- [ ] You used `--section=pre-data`, `--section=data`, `--section=post-data`
- [ ] You restored with `--no-owner --no-privileges`
- [ ] You performed a cross-database restore and verified data integrity
- [ ] You verified foreign key constraints survive the restore

---

**Next:** [03 - Physical Backup and Restore](03-physical-backup-restore.md)
