# Scenario 07 - Tablespace Path Conflict

**Severity:** HIGH
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Queries on the archive table are failing with
'could not open file' errors. The table was stored
in a custom tablespace. During a storage migration,
the tablespace directory may have been moved or renamed.
```

---

## Key Concepts for Revision

- **Tablespaces map to filesystem directories** - A tablespace in PostgreSQL is a directory on disk where database objects (tables, indexes) can be stored. It allows you to spread data across multiple filesystems or storage devices. For example, putting archive tables on slower storage and active tables on fast SSDs.

- **PostgreSQL uses symlinks to track tablespaces** - Inside `$PGDATA/pg_tblspc/`, PostgreSQL creates symlinks named by the tablespace OID. Each symlink points to the actual directory on disk. If the target directory is moved, renamed, or deleted, the symlink becomes broken and queries on objects in that tablespace fail.

- **Tablespace location is fixed at creation time** - You cannot `ALTER TABLESPACE ... SET LOCATION`. The directory path is permanent. To move a tablespace, you must: stop PostgreSQL, move the directory, update the symlink in `pg_tblspc/`, and restart. Or create a new tablespace and move tables with `ALTER TABLE ... SET TABLESPACE`.

- **Why this happens during upgrades** - During `pg_upgrade`, tablespace locations must match between old and new clusters. If a storage migration changes directory paths (e.g., from `/data/pg15` to `/data/pg16`), and the tablespace paths are not updated, the new cluster starts with broken symlinks.

- **pg_tblspc directory** - Located at `$PGDATA/pg_tblspc/`. Contains one symlink per tablespace. The symlink name is the tablespace OID. `ls -la $PGDATA/pg_tblspc/` shows all tablespace mappings.

---

## Diagnostic Steps

### Step 1 - Try to query the table

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT count(*) FROM chaos7_archive;
```

Expected output (yours will differ):

```
ERROR:  could not open file "pg_tblspc/12345/PG_16_202307071/16384/...": No such file or directory
```

The error mentions `pg_tblspc` - a tablespace issue.

### Step 2 - Identify which tablespace the table uses

```sql
SELECT
  t.spcname AS tablespace,
  c.relname AS table_name
FROM pg_class c
JOIN pg_tablespace t ON t.oid = c.reltablespace
WHERE c.relname = 'chaos7_archive';
```

Expected output:

```
  tablespace  |  table_name
--------------+----------------
 chaos7_tbs   | chaos7_archive
(1 row)
```

### Step 3 - Check the tablespace location

```sql
SELECT spcname, oid, pg_tablespace_location(oid)
FROM pg_tablespace
WHERE spcname = 'chaos7_tbs';
```

Expected output (yours will differ):

```
   spcname   |  oid   | pg_tablespace_location
-------------+--------+---------------------------------------
 chaos7_tbs  | 12345  | /opt/pgsql/tablespaces/chaos7_archive
(1 row)
```

### Step 4 - Check the symlink

```sql
\q
```

```bash
ls -la /opt/pgsql/data/pg_tblspc/
```

Expected output (yours will differ):

```
lrwxrwxrwx 1 postgres postgres 43 ... 12345 -> /opt/pgsql/tablespaces/chaos7_archive
```

The symlink points to `/opt/pgsql/tablespaces/chaos7_archive`.

### Step 5 - Verify the target directory is missing

```bash
ls -la /opt/pgsql/tablespaces/chaos7_archive
```

Expected output:

```
ls: cannot access '/opt/pgsql/tablespaces/chaos7_archive': No such file or directory
```

The target directory was moved or renamed.

### Step 6 - Find the moved directory

```bash
ls -la /opt/pgsql/tablespaces/
```

Expected output (yours will differ):

```
drwx------ 3 postgres postgres 4096 ... chaos7_archive_moved
```

The directory was renamed to `chaos7_archive_moved`.

```bash
exit
```

---

## Resolution

There are two approaches. The simplest is to move the directory back.

### Option A - Move the directory back (simplest)

#### Step 1 - Stop PostgreSQL

```bash
sudo systemctl stop postgresql-16
```

#### Step 2 - Move the directory back to the original path

```bash
sudo -iu postgres
```

```bash
mv /opt/pgsql/tablespaces/chaos7_archive_moved /opt/pgsql/tablespaces/chaos7_archive
```

#### Step 3 - Verify the symlink target exists now

```bash
ls -la /opt/pgsql/tablespaces/chaos7_archive
```

Expected output (yours will differ):

```
drwx------ 3 postgres postgres 4096 ... .
```

The directory exists.

```bash
exit
```

#### Step 4 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

#### Step 5 - Verify the table is accessible

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT count(*) FROM chaos7_archive;"
```

Expected output:

```
 count
-------
  5000
(1 row)
```

```bash
exit
```

### Option B - Update the symlink (if directory cannot be moved back)

If the directory must stay at the new location:

#### Step 1 - Stop PostgreSQL

```bash
sudo systemctl stop postgresql-16
```

#### Step 2 - Find the tablespace OID

Check the existing (broken) symlink:

```bash
sudo -iu postgres
```

```bash
ls -la /opt/pgsql/data/pg_tblspc/
```

Note the symlink name (the OID number).

#### Step 3 - Update the symlink

```bash
rm /opt/pgsql/data/pg_tblspc/<OID>
```

Replace `<OID>` with the actual OID number from Step 2.

```bash
ln -s /opt/pgsql/tablespaces/chaos7_archive_moved /opt/pgsql/data/pg_tblspc/<OID>
```

```bash
exit
```

#### Step 4 - Start PostgreSQL and verify

```bash
sudo systemctl start postgresql-16
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- chaos7_archive table is accessible
- Query returns 5000 rows
- Tablespace symlink target exists

---

## Interview Discussion Points

1. **How do tablespace symlinks work internally?** - PostgreSQL stores tablespace mappings as symlinks in `$PGDATA/pg_tblspc/`. Each symlink is named by the tablespace OID and points to the actual filesystem directory. Inside that directory, PostgreSQL creates a version-specific subdirectory (e.g., `PG_16_202307071/`) containing the database OID subdirectories and then the actual data files. This structure allows multiple PostgreSQL versions to share a tablespace directory.

2. **Can you change a tablespace location without downtime?** - Not directly. The symlink update requires stopping PostgreSQL. However, you can move tables to a new tablespace while the server is running: `ALTER TABLE ... SET TABLESPACE new_tbs`. This rewrites the entire table to the new location while holding an AccessExclusive lock. For large tables, this can take a long time and blocks all access.

3. **What happens during pg_upgrade with tablespaces?** - `pg_upgrade` expects the tablespace directories to exist at the same paths in both old and new clusters. It creates new version-specific subdirectories inside each tablespace. If the paths have changed, you must create symlinks or mount points so the old paths still work, or use the `--tablespace-mapping` option in some distributions.

4. **When should you use tablespaces?** - To spread I/O across multiple storage devices. To put large archive tables on slower/cheaper storage. To place frequently-accessed indexes on fast SSDs. To isolate WAL on a dedicated device (though PostgreSQL uses symlinks for `pg_wal` rather than tablespaces). In cloud environments, tablespaces are less common because EBS volumes can be resized.

5. **What is the risk of broken tablespace symlinks during crash recovery?** - If a tablespace symlink is broken during crash recovery, PostgreSQL cannot replay WAL for objects in that tablespace. Recovery will fail and the server will not start. This is why tablespace directory availability is critical for high availability. Always include tablespace paths in your backup and disaster recovery plans.
