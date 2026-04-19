# Runbook 04 - Archive Command Broken

**Severity:** Critical - WAL segments are not being archived, PITR window is shrinking
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Confirm archiving is failing

SSH to [NODE1] and check pg_stat_archiver:

```sql
SELECT
  archived_count,
  failed_count,
  last_archived_wal,
  last_archived_time,
  last_failed_wal,
  last_failed_time
FROM pg_stat_archiver;
```

Expected: failed_count is increasing and last_failed_time is recent.

### Step 2: Check the PostgreSQL log for archiver errors

```bash
sudo tail -50 /opt/pgsql/log/postgresql-*.log | grep -i archiv
```

Expected: Messages like "archive command failed with exit code 1" or "archiver process failed".

> **Concept - Archiver Process**: PostgreSQL runs a dedicated archiver process that invokes archive_command for each completed WAL segment. If the command returns non-zero, the archiver retries periodically. Failed segments pile up in pg_wal and can fill the disk.

### Step 3: Check the current archive_command

```sql
SHOW archive_command;
```

Expected: You will see a broken command like `/bin/false %f %p` instead of the correct pgBackRest or cp-based command.

### Step 4: Determine the correct archive_command

Check what pgBackRest expects:

```bash
cat /etc/pgbackrest/pgbackrest.conf
```

The correct archive_command for pgBackRest is typically:

```
pgbackrest --stanza=main archive-push %p
```

For a simple file-based archive:

```
test ! -f /opt/pgsql/backup/archive/%f && cp %p /opt/pgsql/backup/archive/%f
```

### Step 5: Fix the archive_command

```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';
SELECT pg_reload_conf();
```

Verify the change took effect:

```sql
SHOW archive_command;
```

### Step 6: Force archiving of accumulated segments

Trigger a WAL switch to get the archiver to retry:

```sql
SELECT pg_switch_wal();
```

Wait a few seconds and check if archiving resumes:

```sql
SELECT
  last_archived_wal,
  last_archived_time,
  failed_count
FROM pg_stat_archiver;
```

> **Concept - pg_stat_archiver Reset**: The failed_count is cumulative since the last stats reset. After fixing the issue, you can reset it with `SELECT pg_stat_reset_shared('archiver');` for cleaner monitoring. But do this only after confirming the fix works.

### Step 7: Verify all pending segments are archived

Check how many segments are waiting in pg_wal:

```bash
sudo -u postgres ls /opt/pgsql/data/pg_wal/ | wc -l
```

This count should decrease over time as the archiver catches up. Monitor for a minute:

```bash
watch -n 5 'sudo -u postgres ls /opt/pgsql/data/pg_wal/ | wc -l'
```

### Step 8: Confirm archive continuity

```bash
sudo -u postgres pgbackrest --stanza=main verify
```

Expected: No errors about missing WAL segments.

---

## Key Concepts for Revision

- **archive_command** is invoked by the archiver process for every completed WAL segment. It receives `%p` (full path to WAL file) and `%f` (filename only) as substitution parameters.
- **Archive failures are silent** to the application - writes continue normally. The only sign is pg_stat_archiver.failed_count increasing and WAL files accumulating in pg_wal.
- **pg_wal disk pressure** is the real danger. If archiving is broken, WAL segments cannot be recycled. Eventually pg_wal fills the disk and PostgreSQL shuts down.
- **archive_mode = on** means PostgreSQL will always try to archive. Even after a restart, it will retry failed segments. You cannot skip a segment - the archiver processes them in order.
- **ALTER SYSTEM** writes to postgresql.auto.conf. A `SELECT pg_reload_conf()` applies the change without restart. archive_command is a reload-able parameter.
- **archive_command idempotency**: A good archive_command checks if the file already exists at the destination (`test ! -f ... && cp ...`) to avoid overwriting. pgBackRest handles this internally.
- **Monitoring**: Alert on pg_stat_archiver.failed_count > 0 and on pg_wal directory size exceeding a threshold (e.g., 10 GB).

---

## Interview Discussion Points

1. **Failure detection speed**: How quickly would your monitoring detect a broken archive_command? What is the risk window between breakage and detection?

2. **pg_wal disk exhaustion**: If archiving is broken for hours and pg_wal fills the disk, what happens? How do you recover from a PostgreSQL shutdown caused by WAL disk exhaustion?

3. **archive_command vs pgBackRest archive-push**: What advantages does pgBackRest's archive-push provide over a raw `cp` or `rsync` archive_command? (Hint: compression, checksums, parallel push, async mode.)

4. **Testing archive_command changes**: How do you safely test a new archive_command in production? Can you test it without actually changing the setting? (Hint: manually run the command with a real WAL file path.)

5. **archive_mode = always vs on**: What is the difference? When would you use `always`? (Hint: `always` archives on standbys too, useful for cascading archive setups.)

6. **WAL segment ordering**: If three segments fail to archive (A, B, C), can segment C be archived before A? What are the implications for PITR consistency?

7. **Post-incident review**: After fixing a broken archive_command, what steps do you take to verify the backup chain is complete? How do you confirm there are no gaps in the archive?
