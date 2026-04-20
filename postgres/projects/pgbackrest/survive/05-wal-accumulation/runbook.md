# Scenario 05 - WAL Accumulation

**Severity:** CRITICAL
**Expected Recovery Time:** 10-15 minutes
**Single Server**

---

## Alert

```
CRITICAL: pg_wal directory has 50+ WAL files. Disk at 85%. Archive failing.
```

---

## Symptoms

- pg_wal directory growing rapidly
- Disk space alerts firing
- pgBackRest archive-push failing
- WAL files not being cleaned up after checkpoints

---

## Impact

- If disk fills completely, PostgreSQL will crash (cannot write WAL)
- All transactions will halt
- Risk of data loss if crash occurs before WAL is archived
- Backups become useless if WAL chain is broken

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **WAL (Write-Ahead Log)** - PostgreSQL writes all changes to WAL files before applying them to data files. This guarantees crash recovery. WAL files are 16 MB each by default and live in `pg_wal/`.
- **archive_command** - The shell command PostgreSQL runs to copy each completed WAL file to an archive location. If this command fails (returns non-zero), PostgreSQL retains the WAL file and retries. Files pile up until archiving succeeds.
- **pg_stat_archiver** - System view that tracks archiving status. Key columns: `last_archived_wal`, `last_failed_wal`, `failed_count`, `last_archived_time`. This is your first stop when diagnosing archive problems.
- **CHECKPOINT** - Forces PostgreSQL to flush dirty buffers to disk and advance the WAL position. After a checkpoint, WAL files that have been both checkpointed AND archived can be recycled or removed.
- **WAL retention** - PostgreSQL keeps WAL files until they are: (a) no longer needed for crash recovery (past latest checkpoint), AND (b) archived (if archiving is enabled). If archiving is broken, condition (b) is never met and files accumulate forever.

---

## Layer 1 - Quick Fix

### Step 1 - Check disk space

Log in to the server and check overall disk usage.

```bash
df -h /
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use%  Mounted on
/dev/xvda1       20G   17G  3.0G  85%  /
```

Look at the `Use%` column. If it is above 80%, this is urgent.

### Step 2 - Check pg_wal size

See how much space WAL files are consuming.

```bash
du -sh /opt/pgsql/data/pg_wal/
```

Expected output (yours will differ):

```
1.2G    /opt/pgsql/data/pg_wal/
```

### Step 3 - Count WAL files

The `|` (pipe) sends the output of the first command as input to the second.

```bash
ls /opt/pgsql/data/pg_wal/ | wc -l
```

Expected output (yours will differ):

```
67
```

A healthy system typically has 5-15 WAL files. 50+ means archiving is backed up.

### Step 4 - Check the archiver status

Switch to the postgres user and open psql.

```bash
sudo -i -u postgres
```

The `-p 5432` flag tells psql to connect on port 5432 (the default PostgreSQL port).

```bash
/usr/pgsql-16/bin/psql -p 5432
```

Check pg_stat_archiver for failures.

```sql
SELECT archived_count, failed_count, last_archived_wal,
       last_failed_wal, last_archived_time, last_failed_time
FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 archived_count | failed_count | last_archived_wal        | last_failed_wal          | last_archived_time      | last_failed_time
----------------+--------------+--------------------------+--------------------------+-------------------------+-------------------------
            142 |           53 | 000000010000000000000032 | 000000010000000000000033 | 2026-04-20 10:05:00+00  | 2026-04-20 10:12:30+00
```

> **Concept: pg_stat_archiver** - The `failed_count` shows how many times archive_command has failed since the last stats reset. If `last_failed_time` is recent and `failed_count` is high, archiving is actively broken. The gap between `last_archived_wal` and `last_failed_wal` tells you how far behind you are.

### Step 5 - Check archive_command

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
 archive_command
-----------------
 /bin/false
```

The archive_command is set to `/bin/false`, which always returns exit code 1. Every archive attempt fails, so PostgreSQL retains all WAL files.

> **Concept: archive_command failure** - When archive_command returns a non-zero exit code, PostgreSQL marks the attempt as failed and retries on the next cycle (default: every `archive_timeout` seconds or when the next WAL file completes). The failed WAL file and all subsequent files are retained - they cannot be recycled until successfully archived.

### Step 6 - Fix the archive_command

```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';
```

Expected output (yours will differ):

```
ALTER SYSTEM
```

### Step 7 - Reload PostgreSQL configuration

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
```

### Step 8 - Verify the change took effect

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
 archive_command
-------------------------------------------------------
 pgbackrest --stanza=main archive-push %p
```

### Step 9 - Force a checkpoint

This allows PostgreSQL to start cleaning up WAL files as they get archived.

```sql
CHECKPOINT;
```

Expected output (yours will differ):

```
CHECKPOINT
```

> **Concept: CHECKPOINT and WAL cleanup** - A checkpoint writes all dirty buffers to disk and records the current WAL position. After a checkpoint, any WAL files before that position that have also been archived are eligible for recycling. Without a checkpoint, PostgreSQL keeps WAL files even if they are archived, because it might still need them for crash recovery.

### Step 10 - Wait for archiver to catch up

The archiver will now process the backlog. Watch it work.

```sql
SELECT archived_count, failed_count, last_archived_wal, last_archived_time
FROM pg_stat_archiver;
```

Run this query a few times over 30-60 seconds. You should see `archived_count` increasing and `last_archived_wal` advancing.

Expected output (yours will differ):

```
 archived_count | failed_count | last_archived_wal        | last_archived_time
----------------+--------------+--------------------------+-------------------------
            189 |           53 | 000000010000000000000060 | 2026-04-20 10:15:22+00
```

### Step 11 - Drop the temp table if it exists

The injection script created a table called `chaos_wal_bloat` in labdb. Clean it up.

```
\c labdb
```

```sql
DROP TABLE IF EXISTS chaos_wal_bloat;
```

Expected output (yours will differ):

```
DROP TABLE
```

### Step 12 - Exit psql and postgres user

```
\q
```

```bash
exit
```

### Step 13 - Verify disk recovered

```bash
du -sh /opt/pgsql/data/pg_wal/
```

Expected output (yours will differ):

```
128M    /opt/pgsql/data/pg_wal/
```

```bash
ls /opt/pgsql/data/pg_wal/ | wc -l
```

Expected output (yours will differ):

```
8
```

```bash
df -h /
```

The disk usage should be well below 85% now.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected output (yours will differ):

```
[PASS] archive_command is correct (not /bin/false)
[PASS] Recent successful archive in pg_stat_archiver
[PASS] WAL file count is under 20
[PASS] Disk usage under 85%
[PASS] pgbackrest check passes
Result: ALL CHECKS PASSED
```

---

## Layer 2 - Concepts

### WAL Lifecycle

A WAL file goes through these stages:

1. **Active** - PostgreSQL is writing to it
2. **Complete** - File reached 16 MB and a new one was started
3. **Archive pending** - Waiting for archive_command to succeed
4. **Archived** - Successfully copied to archive storage
5. **Recyclable** - Past the latest checkpoint AND archived - can be reused or removed

If archiving breaks at stage 3, files pile up and never reach stages 4-5.

### Archive Backlog Recovery

When you fix a broken archive_command, PostgreSQL does not immediately archive all pending files. It processes them one at a time, in order. With 50+ files in the backlog, it can take several minutes to catch up. You can monitor progress in `pg_stat_archiver`.

### Disk Pressure Monitoring

Production systems should have alerts for:

- pg_wal directory size (absolute and relative to disk)
- WAL file count
- `pg_stat_archiver.failed_count` increasing
- Time since `last_archived_time`

> **Concept: Emergency WAL cleanup** - If disk is about to fill and you cannot wait for archiving, you can manually remove old WAL files using `pg_archivecleanup`. But this is dangerous - it breaks the WAL chain and makes PITR impossible for the removed range. Only do this if the alternative is a full crash.

> **Concept: wal_keep_size** - PostgreSQL 13+ has `wal_keep_size` (replaces `wal_keep_segments`) that sets a minimum amount of WAL to retain regardless of archiving status. If archiving is broken and `wal_keep_size` is set high, WAL accumulation happens even faster.

---

## Layer 3 - Interview Discussion Points

1. **What happens if pg_wal fills the entire disk?** - PostgreSQL will PANIC and crash because it cannot write new WAL records. This is a hard crash - all active transactions are lost. On restart, PostgreSQL performs crash recovery using whatever WAL it can read. If WAL files were corrupted during the disk-full event, recovery may fail and you need to restore from backup.

2. **How would you monitor WAL archiving in production?** - Use pg_stat_archiver to track failed_count and last_archived_time. Set alerts if failed_count increases or if last_archived_time is more than a few minutes old. Also monitor pg_wal directory size with OS-level tools. In pgBackRest specifically, check the archive-push log files in /var/log/pgbackrest/ for errors.

3. **What is the difference between archive_command and archive_library?** - archive_command (traditional) forks a shell process for each WAL file. archive_library (PostgreSQL 15+) loads a shared library that handles archiving in-process, avoiding the fork overhead. pgBackRest uses archive_command. The pg_basebackup tool can use archive_library via the basic_archive module.

4. **How does wal_level affect WAL volume?** - `wal_level = minimal` generates the least WAL (only crash recovery). `replica` (default in PG 16) adds information needed for replication and PITR. `logical` adds additional information for logical decoding. Higher levels generate more WAL. For pgBackRest PITR, you need at least `replica`.

5. **A junior DBA suggests deleting WAL files manually to free disk space. What do you tell them?** - Never delete WAL files directly from pg_wal. PostgreSQL tracks these files internally. Deleting active files causes a PANIC crash. Deleting archived-but-not-yet-checkpointed files breaks crash recovery. If you must remove old files, use `pg_archivecleanup` which respects the checkpoint boundary. The correct fix is always to repair archiving and let PostgreSQL clean up naturally.
