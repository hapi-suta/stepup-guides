# Runbook 07 - Archive Command Failure

**Severity:** High - WAL archiving broken, backup chain at risk
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Check pg_stat_archiver for failures

SSH to [NODE1] (primary) and inspect the archiver stats:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
  SELECT archived_count, failed_count,
         last_archived_wal, last_archived_time,
         last_failed_wal, last_failed_time
  FROM pg_stat_archiver;
"
```

```bash
exit
```

Expected: `failed_count` is non-zero and `last_failed_time` is recent.

> **Concept - pg_stat_archiver**: This view tracks the archiver process. When archive_command fails, `failed_count` increments and `last_failed_wal` shows which segment could not be archived. The archiver retries indefinitely until it succeeds.

### Step 2: Check the PostgreSQL log for archiver errors

On [NODE1]:

The pipe to `grep -i archiv` filters the log to only show lines containing "archiv" (case-insensitive):

```bash
sudo tail -40 /var/lib/pgsql/16/data/log/postgresql-*.log | grep -i archiv
```

Look for errors like:
- "archive command failed with exit code"
- "Permission denied"
- "No such file or directory"

### Step 3: Inspect the archive_command and target directory

On [NODE1]:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SHOW archive_command;"
```

```bash
psql -c "SHOW archive_mode;"
```

```bash
exit
```

Identify the destination directory from the archive_command output. Then check its permissions:

```bash
sudo ls -la /var/lib/pgsql/16/archive/
```

Expected: The directory permissions are `000` (no read, write, or execute for anyone).

### Step 4: Fix the archive directory permissions

On [NODE1], restore proper permissions:

```bash
sudo chmod 750 /var/lib/pgsql/16/archive/
```

`750` means owner can read/write/execute, group can read/execute, others have no access.

```bash
sudo chown postgres:postgres /var/lib/pgsql/16/archive/
```

Verify:

```bash
sudo ls -la /var/lib/pgsql/16/ | grep archive
```

Expected: `drwxr-x---` owned by `postgres:postgres`.

> **Concept - Archive directory ownership**: The archive_command runs as the `postgres` OS user. The target directory must be readable, writable, and traversable (at minimum 700) by that user. If the directory is on a mounted volume, check that the mount options allow the postgres user to write.

### Step 5: Trigger a WAL switch and verify archiving resumes

On [NODE1]:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_switch_wal();"
```

Wait a few seconds, then check:

```bash
psql -c "
  SELECT archived_count, failed_count,
         last_archived_wal, last_archived_time
  FROM pg_stat_archiver;
"
```

Expected output (yours will differ):
```
 archived_count | failed_count |      last_archived_wal       |      last_archived_time
----------------+--------------+------------------------------+------------------------------
             15 |            3 | 000000010000000000000008     | 2026-04-19 10:25:00.456+00
```

```bash
exit
```

Expected: `last_archived_time` is recent (after your fix), and `failed_count` is no longer increasing.

### Step 6: Verify archived files exist

On [NODE1]:

Switch to the postgres user:

```bash
sudo -iu postgres
```

List the most recent archived WAL files. `-l` shows details, `-t` sorts by time (newest first). The pipe to `head -5` limits to 5 lines:

```bash
ls -lt /var/lib/pgsql/16/archive/ | head -5
```

```bash
exit
```

Expected: Recent WAL segment files are present.

### Step 7: Reset archiver stats (optional)

On [NODE1]:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_stat_reset_shared('archiver');"
```

```bash
exit
```

This resets failed_count to 0 so future monitoring starts clean.

### Step 8: Verify replication still streaming

On [NODE1]:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT client_addr, state FROM pg_stat_replication;"
```

Expected: `state` is `streaming`.

Expected output (yours will differ):
```
 client_addr  |   state
--------------+-----------
 10.0.1.52    | streaming
```

```bash
exit
```

---

## Key Concepts for Revision

- **archive_command** is a shell command run by the archiver process for each completed WAL segment. It receives `%p` (full path of the WAL file) and `%f` (filename only). The command must return exit code 0 for success.
- **archive_mode** must be `on` (or `always` on a standby) for archiving to be active. Changing it requires a restart. archive_command can be changed with a reload.
- **Retry behavior**: When archive_command fails, PostgreSQL retries it indefinitely. This is intentional - WAL segments must not be recycled until successfully archived. However, this can cause pg_wal to grow if the failure persists.
- **pg_stat_archiver** is the primary monitoring view. Alert on: failed_count increasing, last_archived_time being stale (more than a few minutes old), or the gap between last_archived_wal and the current WAL position.
- **WAL retention risk**: If archiving is broken and the archive is needed for PITR or standby catchup, your backup chain is broken. New base backups taken during the outage will not have a continuous WAL chain.
- **archive_cleanup_command** on standbys removes archived WAL no longer needed for recovery. It is separate from archive_command but related in the overall archiving workflow.
- **pg_wal growth**: While archive_command fails, PostgreSQL keeps WAL segments in pg_wal (they cannot be recycled). This is the same disk pressure problem as a stalled replication slot - monitor pg_wal size alongside archiver health.

---

## Interview Discussion Points

1. **Monitoring archive health**: How do you monitor WAL archiving in production? What metrics do you alert on? How quickly should you respond to archive failures?

2. **Archive vs streaming replication**: How does WAL archiving complement streaming replication? Can you have one without the other? When do you need both?

3. **PITR dependency**: Explain how a broken archive_command affects your ability to do Point-in-Time Recovery. What is the impact if the archive is broken for 30 minutes vs 12 hours?

4. **Archive destinations**: Compare archiving to local disk, NFS, S3 (via wal-g or pgbackrest), and rsync to a remote host. What are the failure modes of each?

5. **archive_mode always**: When would you set archive_mode = always on a standby? Explain the use case for cascading standbys and PITR from a standby.

6. **WAL segment accumulation**: If archive_command has been failing for hours and pg_wal is filling the disk, what is your recovery plan? Can you skip WAL segments, or must every segment be archived?

7. **Testing archive_command**: How do you test that your archive_command works correctly before relying on it in production? What edge cases should you test (permissions, disk full, network timeout)?
