# Scenario 07 - Full Cluster Recovery

**Severity:** CRITICAL
**Expected Recovery Time:** 10-15 minutes
**Single Server**

---

## Alert

```
CRITICAL: PGDATA wiped. Database is completely gone. Must restore from backup.
```

---

## Symptoms

- PostgreSQL will not start
- PGDATA directory is empty
- systemctl status shows the service as failed or inactive
- No database files exist on disk

---

## Impact

- Complete data loss if no backup exists
- All databases (labdb, appdb) are gone
- All users, roles, and configurations stored in the cluster are gone
- Downtime until a full restore is completed

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **Full restore** - When PGDATA is completely empty, pgBackRest restores all files from the backup: data files, configuration files (postgresql.conf, pg_hba.conf), tablespace links, and WAL files needed for recovery. No `--delta` flag is needed because there is nothing to compare against.
- **Delta restore** - When PGDATA has existing files (e.g., a corrupted cluster), `--delta` checksums each file and only replaces those that differ from the backup. Faster than full restore but only works when PGDATA is not empty.
- **Backup repository** - pgBackRest stores backups in the repo path (`/opt/pgsql/backup/pgbackrest` in this lab). The repo is separate from PGDATA, so wiping PGDATA does not affect backups. In production, the repo should be on a different disk or remote storage.
- **Post-recovery WAL archiving** - After a restore, PostgreSQL starts on a new timeline. The archive_command in the restored postgresql.conf should still be configured correctly, so archiving resumes automatically.
- **Recovery target** - When restoring without a specific target (`--type=time` or `--type=xid`), pgBackRest restores to the end of the available WAL - recovering as much data as possible.

---

## Layer 1 - Quick Fix

### Step 1 - Verify PGDATA is empty

```bash
ls -la /opt/pgsql/data/
```

Expected output (yours will differ):

```
total 0
drwx------. 2 postgres postgres  6 Apr 20 10:30 .
drwxr-xr-x. 6 postgres postgres 58 Apr 20 09:00 ..
```

The directory exists but is empty. All database files are gone.

### Step 2 - Confirm PostgreSQL will not start

The `|` (pipe) sends the output of the first command as input to the second.

```bash
sudo systemctl status postgresql-16 | head -5
```

Expected output (yours will differ):

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded
     Active: inactive (dead)
...
```

Do not try to start it yet - there is nothing to start.

### Step 3 - Verify the backup repository is intact

The backup repo is stored separately from PGDATA. Confirm it still exists.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: error (no pg_control)
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000020

        full backup: 20260420-100000F
            timestamp start/stop: 2026-04-20 10:00:00+00 / 2026-04-20 10:02:30+00
            wal start/stop: 000000010000000000000010 / 000000010000000000000010
            database size: 850MB, database backup size: 850MB
            ...
```

The status shows "error (no pg_control)" because PGDATA is empty - that is expected. The important thing is that the backup information is displayed below it. Your backup is safe.

> **Concept: Backup repo separation** - The pgBackRest repository (`/opt/pgsql/backup/pgbackrest`) is deliberately stored on a different path from PGDATA. This means losing PGDATA does not mean losing backups. In production, the repo should be on entirely separate storage - a different disk, NFS mount, or cloud object storage (S3/GCS).

### Step 4 - Restore from backup

Since PGDATA is completely empty, we do not need the `--delta` flag. pgBackRest will restore all files from the backup.

```bash
pgbackrest --stanza=main restore
```

Expected output (yours will differ):

```
P00   INFO: repo1: restore backup set 20260420-100000F
P00   INFO: write updated /opt/pgsql/data/postgresql.auto.conf
P00   INFO: restore global/pg_control
            (performed last to ensure aborted restores cannot be started)
P00   INFO: restore command end: completed successfully (30s)
```

This may take 1-3 minutes depending on the backup size.

> **Concept: No --delta when PGDATA is empty** - When PGDATA is empty, there are no files to compare against, so `--delta` serves no purpose. pgBackRest detects this and performs a full file restore. If PGDATA had partial files (e.g., a corrupted cluster), then `--delta` would be beneficial because it skips unchanged files.

```bash
exit
```

### Step 5 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

Wait a few seconds, then verify it is running.

```bash
sudo systemctl status postgresql-16 | head -5
```

Expected output (yours will differ):

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded
     Active: active (running)
...
```

### Step 6 - Verify databases exist

```bash
sudo -i -u postgres
```

The `-p 5432` flag tells psql to connect on port 5432 (the default PostgreSQL port).

```bash
/usr/pgsql-16/bin/psql -p 5432
```

List all databases.

```sql
\l
```

Expected output (yours will differ):

```
                                  List of databases
   Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
-----------+----------+----------+-------------+-------------+-----------------------
 appdb     | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 labdb     | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
...
```

Both `labdb` and `appdb` should be present.

### Step 7 - Verify data in labdb

```sql
\c labdb
```

```sql
SELECT count(*) FROM pgbench_accounts;
```

Expected output (yours will differ):

```
  count
---------
 1000000
(1 row)
```

Compare this against the pre-disaster count in `/tmp/chaos-07-state.env`.

### Step 8 - Verify data in appdb

```sql
\c appdb
```

```sql
SELECT count(*) FROM employees;
```

Expected output (yours will differ):

```
 count
-------
    50
(1 row)
```

```sql
SELECT count(*) FROM departments;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

### Step 9 - Verify WAL archiving resumes

```sql
\c postgres
```

```sql
SELECT last_archived_wal, last_failed_wal, last_archived_time
FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 last_archived_wal        | last_failed_wal | last_archived_time
--------------------------+-----------------+-------------------------
 000000020000000000000021 |                 | 2026-04-20 10:35:00+00
```

If `last_archived_wal` has a value and `last_failed_wal` is empty, archiving is working.

> **Concept: Post-recovery archiving** - After restore, PostgreSQL starts on a new timeline (notice the `00000002` prefix in the WAL file name). The archive_command from the restored postgresql.conf is still configured, so archiving resumes automatically. pgBackRest handles new timelines seamlessly.

### Step 10 - Exit psql and postgres user

```
\q
```

```bash
exit
```

### Step 11 - Take a new full backup

Establish a fresh backup chain on the new timeline.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main --type=full backup
```

Expected output (yours will differ):

```
...
P00   INFO: new backup label = 20260420-103500F
P00   INFO: full backup size = 850MB
P00   INFO: backup command end: completed successfully
```

```bash
exit
```

> **Concept: Post-recovery backup** - Always take a full backup after a major recovery. This gives you a clean backup on the current timeline and reduces dependency on older backups from previous timelines. It also validates that the backup infrastructure is working correctly after the disaster.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected output (yours will differ):

```
[PASS] PostgreSQL is running
[PASS] labdb exists with pgbench_accounts data
[PASS] appdb exists with employees data
[PASS] appdb has departments data
[PASS] WAL archiving is working
[PASS] pgbackrest check passes
Result: ALL CHECKS PASSED
```

---

## Layer 2 - Concepts

### Full Restore vs Delta Restore

| Aspect | Full Restore | Delta Restore |
|--------|-------------|---------------|
| PGDATA state | Must be empty | Can have existing files |
| Speed | Restores everything | Only replaces changed files |
| Use case | Total loss | Corruption, re-recovery |
| Flag | (none) | `--delta` |
| Safety | Cannot accidentally overwrite wrong cluster | Checksums verify each file |

### Post-Recovery Checklist

After any full restore, verify these items:

1. All expected databases exist (`\l`)
2. Row counts match pre-disaster baseline
3. Application users can connect (pg_hba.conf was restored)
4. WAL archiving is working (pg_stat_archiver)
5. pgbackrest check passes
6. Take a new full backup
7. Notify applications to reconnect
8. Review PostgreSQL logs for any warnings

### Importance of Backup Verification

A backup you have never tested is a backup you cannot trust. Schedule regular restore drills:

- Monthly: restore to a test server and verify data
- After schema changes: take and verify a new backup
- After pgBackRest upgrades: test restore compatibility

### What pgBackRest Restores

When you run `pgbackrest restore`, it restores:

- All data files (base/, global/, pg_tblspc/)
- postgresql.conf, pg_hba.conf, pg_ident.conf
- postgresql.auto.conf (including ALTER SYSTEM settings)
- pg_control (restored last - prevents starting a partial restore)
- Recovery configuration (recovery.signal or standby.signal)

It does NOT restore:
- pg_wal/ contents (WAL is replayed from the archive during recovery)
- Tablespace data on other mount points (restored separately)
- External tools or cron jobs

---

## Layer 3 - Interview Discussion Points

1. **PGDATA is gone but you also lost the backup repository. What are your options?** - If both PGDATA and the backup repo are on the same disk and both are gone, you are looking at data loss. Options: (a) check if WAL archives exist on a separate location, (b) check for filesystem snapshots (LVM, ZFS, EBS), (c) check for any standby servers that might have the data, (d) check for logical backups (pg_dump files). This is why backup repos should always be on separate storage from PGDATA.

2. **How would you restore only a single database from a pgBackRest backup?** - pgBackRest supports `--db-include` to restore specific databases. For example: `pgbackrest --stanza=main --db-include=appdb restore`. This restores only the specified database's files, but still restores the global objects (roles, tablespaces). Other databases will exist as empty shells. This is faster when you only need one database from a multi-database cluster.

3. **What is the role of pg_control in the restore process?** - pg_control is the cluster's "birth certificate" - it tracks the checkpoint position, timeline, WAL segment size, and system identifier. pgBackRest restores pg_control last because if the restore is interrupted, PostgreSQL will refuse to start with a mismatched pg_control. This "last-file" strategy prevents accidentally starting a partially restored cluster.

4. **Your 2 TB database needs to be restored but you only have a 30-minute maintenance window. What strategies can reduce restore time?** - (a) Use parallel restore processes: `--process-max=4` or higher depending on CPU/IO, (b) Use delta restore if PGDATA has existing files, (c) Consider tablespace-level restore if only one tablespace is affected, (d) Use compressed backups with fast decompression (lz4 or zstd), (e) Place the backup repo on fast storage (NVMe, local SSD), (f) Pre-stage: restore to a standby and promote when ready.

5. **After restoring, applications report that some recent transactions are missing. How do you investigate?** - Check the restore log for the exact WAL position recovered to. Compare the last archived WAL (from pgbackrest info) with the WAL that was active when the disaster occurred. If the active WAL file was not yet archived when PGDATA was wiped, those transactions are lost. This is the RPO (Recovery Point Objective) gap. To minimize this in the future: (a) reduce archive_timeout so WAL is archived more frequently, (b) use synchronous archiving, (c) stream WAL to a standby server for near-zero RPO.
