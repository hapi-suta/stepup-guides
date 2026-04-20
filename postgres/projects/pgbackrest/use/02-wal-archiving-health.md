# USE Exercise 02 - WAL Archiving Health Check

| | |
|---|---|
| **Time** | 20 minutes |
| **What you'll practice** | Diagnosing WAL archiving health, using pg_stat_archiver, forcing WAL switches, checking for archive backlogs |
| **Prerequisites** | Completed BUILD guides 01-04 (pgBackRest installed, stanza created, WAL archiving enabled, at least one backup taken) |

---

## The Scenario

Your monitoring system fires an alert:

> "WAL archiving has not succeeded in 10 minutes."

This is a serious alert. If WAL archiving stops, PostgreSQL will eventually fill up the `pg_wal` directory, run out of disk space, and crash. You need to investigate immediately.

---

## Exercise 1: Check pg_stat_archiver

PostgreSQL tracks all archiving activity in a system view called `pg_stat_archiver`. This is your first stop when investigating archiving issues.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

Connect to PostgreSQL:

```bash
psql
```

Query the archiver stats:

```sql
SELECT * FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
-[ RECORD 1 ]------+-------------------------------
archived_count      | 15
last_archived_wal   | 00000001000000000000000F
last_archived_time  | 2026-04-20 15:42:18.293847+00
failed_count        | 0
last_failed_wal     |
last_failed_time    |
stats_reset         | 2026-04-20 09:00:00.123456+00
```

Here is what each field means:

- **archived_count** - Total number of WAL files successfully archived since the last stats reset.
- **last_archived_wal** - The name of the most recently archived WAL file.
- **last_archived_time** - When that WAL file was archived. This is the critical field - if this timestamp is old, archiving is behind.
- **failed_count** - Number of failed archive attempts. Any number above 0 needs investigation.
- **last_failed_wal** - The WAL file that failed to archive. If this has a value, something went wrong.
- **last_failed_time** - When the failure happened.
- **stats_reset** - When these stats were last reset. Useful for knowing the time window.

> **Concept: pg_stat_archiver Is Your First Stop**
> Whenever you suspect archiving problems, check this view first. The `last_archived_time` tells you instantly whether archiving is current. The `failed_count` tells you if there have been any errors.

---

## Exercise 2: Is Archiving Currently Working?

Look at the `last_archived_time` from Exercise 1.

**Question A:** How many minutes ago was the last successful archive?

Calculate: current time minus `last_archived_time`. If this is more than a few minutes, archiving might be stalled.

**Question B:** Is the `failed_count` zero or non-zero?

If `failed_count` is 0, archiving has never failed (good). If it is non-zero, there was at least one failure. Check `last_failed_wal` and `last_failed_time` for details.

**Question C:** In a healthy system, how often should WAL files be archived?

It depends on how busy the database is. A busy database might archive a new WAL file every few seconds. A quiet database might go minutes between archives. The key is that `last_archived_time` should not fall too far behind.

> **Concept: Archive Lag vs. Activity Level**
> A 10-minute gap between archived WAL files might be normal on a quiet development server. The same gap on a busy production server means something is wrong. Always consider the database's activity level when evaluating archiving health.

---

## Exercise 3: Force a WAL Switch

If the database is quiet, PostgreSQL might not have filled a WAL segment recently - so there is nothing to archive. You can force a WAL switch to test archiving.

First, note the current `last_archived_wal` value (you should still be in psql from Exercise 1):

```sql
SELECT last_archived_wal, last_archived_time FROM pg_stat_archiver;
```

Now force PostgreSQL to switch to a new WAL file:

```sql
SELECT pg_switch_wal();
```

Expected output (yours will differ):

```
 pg_switch_wal
---------------
 0/10000100
(1 row)
```

This function closes the current WAL file and starts a new one. The closed file gets handed to the archive_command for archiving.

Wait a few seconds for archiving to complete, then check again:

```sql
SELECT last_archived_wal, last_archived_time FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
     last_archived_wal      |       last_archived_time
----------------------------+-------------------------------
 000000010000000000000010   | 2026-04-20 16:05:03.847291+00
(1 row)
```

**Question:** Did the `last_archived_wal` change? Did the `last_archived_time` update to just now?

If yes - archiving is working. The original alert might have been triggered because the database was simply idle.

If no - archiving is truly broken. Continue to the next exercises to investigate why.

> **Concept: pg_switch_wal() Is a Diagnostic Tool**
> This function is safe to run. It does not lose data. It simply tells PostgreSQL to finish the current WAL segment early. In production, use it to test archiving or to force a WAL file to be archived before taking a backup.

---

## Exercise 4: Check for WAL Backlog

If archiving falls behind, unarchived WAL files pile up in the `pg_wal` directory. This is dangerous because it can fill up your disk.

Exit psql first:

```sql
\q
```

Count the WAL files waiting in pg_wal:

```bash
ls /opt/pgsql/data/pg_wal/ | grep -c "^0000"
```

Expected output (yours will differ):

```
3
```

A healthy system typically has only a few WAL files in this directory (the current one being written plus a small number of recycled files). If you see dozens or hundreds, archiving is behind.

Check the total size of the pg_wal directory:

```bash
du -sh /opt/pgsql/data/pg_wal/
```

Expected output (yours will differ):

```
49M     /opt/pgsql/data/pg_wal/
```

Each WAL file is 16 MB. A few files (48-80 MB) is normal. Gigabytes means you have a serious backlog.

> **Concept: pg_wal Backlog = Disk Space Emergency**
> PostgreSQL will not delete WAL files from pg_wal until they are archived. If archiving stops, WAL files accumulate. When the disk fills up, PostgreSQL will PANIC and shut down. This is why monitoring archiving lag is critical.

---

## Exercise 5: Verify the archive_command

The `archive_command` is the shell command PostgreSQL runs to archive each WAL file. If this command is wrong, archiving fails.

Connect to PostgreSQL:

```bash
psql
```

Check the current archive_command:

```sql
SHOW archive_command;
```

Expected output (yours will differ):

```
                    archive_command
-------------------------------------------------------
 pgbackrest --stanza=main archive-push %p
(1 row)
```

The `%p` is a placeholder that PostgreSQL replaces with the full path to the WAL file being archived. pgBackRest then compresses and copies that file to the backup repository.

Also check that archiving is enabled:

```sql
SHOW archive_mode;
```

Expected output:

```
 archive_mode
--------------
 on
(1 row)
```

And check the WAL level:

```sql
SHOW wal_level;
```

Expected output:

```
 wal_level
-----------
 replica
(1 row)
```

Exit psql:

```sql
\q
```

**Question:** If `archive_mode` were `off`, would changing it to `on` take effect immediately?

No. Changing `archive_mode` requires a PostgreSQL restart. This is one of the few settings that cannot be reloaded.

> **Concept: Three Settings Must Be Correct**
> WAL archiving requires three settings: `wal_level` must be `replica` or `logical` (not `minimal`), `archive_mode` must be `on`, and `archive_command` must be set to a valid command. If any of these is wrong, archiving will not work.

---

## Exercise 6: Run pgBackRest Check

pgBackRest has a built-in health check that validates the entire archiving pipeline.

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
2026-04-20 16:10:00.123 P00   INFO: check command begin 2.54: ...
2026-04-20 16:10:01.456 P00   INFO: check repo1 configuration (primary)
2026-04-20 16:10:02.789 P00   INFO: check repo1 archive for WAL (primary)
2026-04-20 16:10:03.012 P00   INFO: WAL segment 000000010000000000000011 successfully archived ...
2026-04-20 16:10:03.345 P00   INFO: check command end: completed successfully
```

This command does several things:
1. Verifies the pgBackRest configuration is valid
2. Checks that it can connect to PostgreSQL
3. Forces a WAL switch and confirms the WAL file gets archived
4. Reports success or failure

If this command succeeds, your entire archiving pipeline is healthy.

If it fails, the error message will tell you exactly what is wrong - configuration problem, permission issue, repository access failure, etc.

---

## Exercise 7: Where Do Archived WAL Files Go?

List the WAL archive directory to see the archived files:

```bash
ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/0000000100000000/
```

Expected output (yours will differ):

```
000000010000000000000001-abc123def456.gz
000000010000000000000002-789abc012def.gz
000000010000000000000003-345678901abc.gz
...
```

Notice the `.gz` extension - pgBackRest compresses WAL files before storing them. The hex string after the dash is a checksum that pgBackRest uses to verify file integrity.

---

## Exercise 8: What Happens If Archiving Stops?

This is a thought exercise - do NOT actually break archiving.

**Question A:** If archiving stops, what happens to the pg_wal directory?

It fills up. PostgreSQL keeps generating WAL files but cannot delete old ones because they have not been archived yet.

**Question B:** What happens when the disk containing pg_wal is full?

PostgreSQL panics and shuts down. It cannot write new WAL entries, which means it cannot process any transactions. This is a full database outage.

**Question C:** What happens to your recovery window?

Any WAL files that were not archived create a gap. You lose the ability to do point-in-time recovery to any moment covered by those missing WAL files. You can only recover to the exact point of your last backup.

**Question D:** How would you fix it?

1. Identify why archiving stopped (permissions, disk space on repository, network issue)
2. Fix the root cause
3. Archiving will automatically resume - PostgreSQL retries the archive_command
4. Monitor until the backlog clears

> **Concept: Archiving Failure = Data Loss Risk**
> WAL archiving is not optional in a production environment. Without it, you can only recover to the moment of your last backup. With continuous archiving, you can recover to any point in time. Always monitor archiving health.

Exit back to ec2-user:

```bash
exit
```

---

## What You Learned

- How to use `pg_stat_archiver` to check archiving health
- How to interpret archiving timestamps and failure counts
- How to use `pg_switch_wal()` to test archiving on demand
- How to detect WAL backlogs in the pg_wal directory
- How to verify archive_command, archive_mode, and wal_level settings
- How to use `pgbackrest --stanza=main check` for end-to-end validation
- Why archiving failures are emergency-level events in production
