# Runbook 02 - Archive Command Broken

**Severity:** Critical - WAL archiving is completely broken, backup gap growing
**Time to resolve:** 5-10 minutes
**Symptoms:** `pg_stat_archiver` shows high `failed_count`, WAL files accumulating in `pg_wal/`, pgbackrest check fails
**Impact:** No WAL files are being archived. The gap between the last backup and now cannot be recovered. If pg_wal fills the disk, PostgreSQL will crash.

---

## Layer 1 - Quick Fix

### Step 1: SSH to the server

Log in to your server:

```bash
ssh -i /path/to/your-key.pem ec2-user@[YOUR_SERVER_IP]
```

### Step 2: Switch to the postgres user

```bash
sudo -i -u postgres
```

### Step 3: Check the archive status

Look at pg_stat_archiver to see what is happening with WAL archiving. Open psql.

```bash
psql
```

Run this query.

```sql
SELECT archived_count, failed_count, last_archived_wal, last_failed_wal, last_failed_time FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 archived_count | failed_count |     last_archived_wal      |      last_failed_wal       |       last_failed_time
----------------+--------------+----------------------------+----------------------------+----------------------------
             25 |           53 | 000000010000000000000019    | 00000001000000000000001E    | 2026-04-20 14:25:10.456+00
(1 row)
```

The key indicators:
- `failed_count` is high (53 failures)
- `last_failed_time` is very recent (archiving keeps trying and failing)

> **Concept - pg_stat_archiver**: This view is your window into WAL archiving health. PostgreSQL tries to archive each completed WAL segment using the archive_command. If the command fails, `failed_count` increments and PostgreSQL retries. The WAL file stays in pg_wal until it is successfully archived.

### Step 4: Check what archive_command is set to

Run this query.

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
 archive_command
-----------------
 /bin/false
(1 row)
```

The archive_command is `/bin/false` - a program that always exits with failure. Every time PostgreSQL tries to archive a WAL file, `/bin/false` runs and returns exit code 1. PostgreSQL sees the failure and retries.

### Step 5: Check how many WAL files are piling up

The `|` (pipe) sends the output of the first command as input to the second.

```bash
ls /opt/pgsql/data/pg_wal/ | head -20
```

Expected output (yours will differ):

```
000000010000000000000019
00000001000000000000001A
00000001000000000000001B
00000001000000000000001C
00000001000000000000001D
00000001000000000000001E
archive_status
```

These WAL files cannot be recycled because they have not been archived yet. On a busy database, this directory fills up fast.

> **Concept - WAL lifecycle**: When PostgreSQL fills a 16MB WAL segment, it calls archive_command to copy it to your backup storage. Only after successful archiving can the WAL file be recycled. If archiving is broken, WAL files accumulate. If the disk fills, PostgreSQL stops accepting writes.

### Step 6: Fix the archive_command

Restore the correct archive_command that uses pgBackRest. Run this query.

```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';
```

Expected output (yours will differ):

```
ALTER SYSTEM
```

The `%p` is a placeholder - PostgreSQL replaces it with the full path to the WAL file being archived.

### Step 7: Reload the configuration

PostgreSQL needs to reload its config to pick up the change.

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

> **Concept - ALTER SYSTEM vs postgresql.conf**: `ALTER SYSTEM` writes to `postgresql.auto.conf`, which overrides `postgresql.conf`. After ALTER SYSTEM, you must reload (or restart for some parameters). archive_command only needs a reload - no restart required.

### Step 8: Force a WAL switch to test archiving

Run this query.

```sql
SELECT pg_switch_wal();
```

Expected output (yours will differ):

```
 pg_switch_wal
----------------
 0/1F000100
(1 row)
```

This forces PostgreSQL to finish the current WAL segment and start a new one. The finished segment will be passed to the archive_command.

### Step 9: Wait and verify archiving resumed

Wait about 5 seconds for the archive to complete, then check.

```sql
SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 archived_count | failed_count |     last_archived_wal      |     last_archived_time
----------------+--------------+----------------------------+----------------------------
             30 |           53 | 00000001000000000000001F    | 2026-04-20 14:32:05.789+00
(1 row)
```

Key checks:
- `archived_count` has increased (new archives are succeeding)
- `last_archived_time` is very recent (within the last minute)
- `failed_count` has stopped growing

> **Concept - Catching up on archives**: Once you fix the archive_command, PostgreSQL works through the backlog. It archives each pending WAL file one at a time. On a busy system with a large backlog, this can take a while.

### Step 10: Verify pgBackRest check passes

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00   INFO: check command end: completed successfully (210ms)
```

### Step 11: Confirm the archive_command is correct

Double-check the setting persisted.

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
              archive_command
--------------------------------------------
 pgbackrest --stanza=main archive-push %p
(1 row)
```

Exit psql.

```
\q
```

Return to ec2-user:

```bash
exit
```

---

## Layer 2 - Concepts

> **What archive_command does**
> PostgreSQL calls archive_command once for each completed WAL segment (16MB file). The command must copy the file to your backup storage and exit 0 on success. pgBackRest's `archive-push` handles this - it compresses the WAL file and copies it to the repo. If the command returns non-zero, PostgreSQL keeps retrying.

> **Why /bin/false is dangerous**
> `/bin/false` is a Unix program that does nothing except return exit code 1. When used as archive_command, every WAL file fails to archive. PostgreSQL retries every `archive_timeout` seconds (default 0 - meaning it retries after each checkpoint cycle). WAL files pile up because they cannot be recycled until archived.

> **What happens when pg_wal fills the disk**
> If unarchived WAL files fill the disk, PostgreSQL stops. It cannot write new WAL, so all transactions halt. The server enters a PANIC state. You must free space (or fix archiving so WAL can be recycled) before PostgreSQL can restart. This is a full outage.

> **pg_stat_archiver columns explained**
> - `archived_count`: Total WAL files successfully archived since stats reset
> - `failed_count`: Total archive failures since stats reset
> - `last_archived_wal`: Name of the most recently archived WAL file
> - `last_archived_time`: When the last successful archive happened
> - `last_failed_wal`: Name of the WAL file that last failed to archive
> - `last_failed_time`: When the last failure happened

> **ALTER SYSTEM vs editing postgresql.conf**
> `ALTER SYSTEM` writes to `postgresql.auto.conf`, which takes precedence over `postgresql.conf`. This is the safest way to change parameters because it does not touch the main config file. To undo, use `ALTER SYSTEM RESET archive_command`.

---

## Layer 3 - Interview Discussion

1. **How do you monitor WAL archiving in production?** Query `pg_stat_archiver` on a schedule. Alert if `failed_count` increases between checks. Alert if `last_archived_time` is older than your threshold (e.g., 5 minutes). Some teams also monitor the number of files in pg_wal/ directly.

2. **What is the difference between archive_mode and archive_command?** `archive_mode = on` tells PostgreSQL to call archive_command for every completed WAL segment. `archive_command` defines what command to run. Changing archive_mode requires a restart. Changing archive_command only needs a reload. You can set archive_command to `/bin/true` temporarily to "disable" archiving without restarting (but you lose WAL history).

3. **A developer accidentally runs ALTER SYSTEM SET archive_command = '' in production. What happens?** An empty archive_command means PostgreSQL has no way to archive WAL. On PostgreSQL 16 with archive_mode=on, an empty command is treated as an error - archiving fails. WAL files accumulate. Fix it immediately with ALTER SYSTEM SET archive_command to the correct value and reload.

4. **How do you test archive_command changes before applying them in production?** Test on a staging server first. You can also run the command manually: `pgbackrest --stanza=main archive-push /opt/pgsql/data/pg_wal/SOME_WAL_FILE` to verify it works. After applying with ALTER SYSTEM, force a WAL switch and watch pg_stat_archiver for success.

5. **Your pg_wal directory is 95% full and growing. Walk through your emergency response.** First, fix the archive_command so archiving resumes. Force a WAL switch to test. Watch pg_stat_archiver for successful archives. As WAL files get archived, PostgreSQL recycles them and disk usage drops. If the disk is truly full and PostgreSQL has stopped, you may need to manually move some WAL files (carefully!) to free space before PostgreSQL can restart. Never delete WAL files - move them, archive them manually, then let PostgreSQL recover.
