# Video Script: SURVIVE 02 - Archive Command Broken

**Video file:** `pgbackrest-survive-02-archive-broken.mp4`
**Estimated length:** 8 minutes
**Severity:** CRITICAL
**Runbook:** [Link](../../survive/02-archive-command-broken/runbook.md)
**Inject first:** `bash survive/02-archive-command-broken/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Something is broken. Your monitoring says WAL archiving has failed dozens of times and the backup gap is growing. Let me show you what that looks like."

[TYPE] `sudo -i -u postgres`

[TYPE] `psql`

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_failed_wal, last_failed_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] the `failed_count` column - should be high (50+)

[SAY] "Look at failed_count. Over 50 failures. And last_failed_time is very recent - archiving keeps trying and keeps failing."

[PAUSE]

[SAY] "Let's check how bad the WAL accumulation is."

[TYPE] `\q`

[TYPE] `ls /opt/pgsql/data/pg_wal/ | head -20`

[WAIT for output]

[SAY] "WAL files are piling up. These files cannot be recycled because they have not been archived yet. On a busy production database, this directory fills the disk and PostgreSQL crashes. Let's diagnose and fix this."

---

## DIAGNOSE [1:15]

[SAY] "Step 1: Check what archive_command is set to. This is the command PostgreSQL runs every time it needs to archive a WAL file."

[TYPE] `psql`

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] `/bin/false` in the output

[SAY] "There is your problem. archive_command is set to /bin/false. That is a Linux program that does absolutely nothing except return exit code 1 - failure. Every time PostgreSQL finishes writing a WAL file and tries to archive it, it runs /bin/false, which fails. PostgreSQL sees the failure and retries. The WAL file stays in pg_wal. This repeats forever."

[PAUSE]

[SAY] "Meanwhile, WAL files keep piling up because PostgreSQL cannot recycle a WAL file until it has been successfully archived."

---

## FIX [2:30]

[SAY] "The fix is to restore the correct archive_command. For pgBackRest, that command is pgbackrest archive-push with the stanza name."

[TYPE] `ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';`

[WAIT for output]

[SAY] "The percent-p is a placeholder. PostgreSQL replaces it with the full path to the WAL file being archived."

[PAUSE]

[SAY] "ALTER SYSTEM wrote this to postgresql.auto.conf, but PostgreSQL is still using the old setting. We need to reload the configuration."

[TYPE] `SELECT pg_reload_conf();`

[WAIT for output]

[SAY] "Configuration reloaded. Now let's force a WAL switch to test that archiving actually works."

[TYPE] `SELECT pg_switch_wal();`

[WAIT for output]

[SAY] "That forces PostgreSQL to finish the current WAL segment. The finished segment will be passed to our new archive_command."

---

## VERIFY [4:00]

[SAY] "Let's wait a few seconds and check if archiving resumed."

[WAIT 5 seconds]

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] `last_archived_time` - should be very recent

[SAY] "Look at last_archived_time - it is within the last minute. And archived_count has gone up. Archiving is working again. The failed_count is still showing the old failures, but it has stopped climbing."

[PAUSE]

[SAY] "Let's also run a pgBackRest check to make sure everything is end-to-end healthy."

[TYPE] `\q`

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Completed successfully. The backup pipeline is fully operational."

[PAUSE]

[SAY] "Let's confirm the setting persisted."

[TYPE] `psql`

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] the correct pgbackrest archive-push command

[SAY] "archive_command is correct. We are done."

[TYPE] `\q`

[TYPE] `exit`

---

## CONCEPTS [6:00]

[SAY] "Why is this so dangerous? When archive_command fails, PostgreSQL retains every WAL file because it cannot recycle a file until it has been archived. Each WAL segment is 16 megabytes. On a busy database writing hundreds of WAL files per hour, the pg_wal directory can fill the disk in hours."

[PAUSE]

[SAY] "When pg_wal fills the disk, PostgreSQL enters a PANIC state. It cannot write new WAL, so all transactions halt. The server crashes. You must free space or fix archiving before PostgreSQL can restart. That is a full outage."

[PAUSE]

[SAY] "In production, you would monitor this with pg_stat_archiver. Alert if failed_count increases between checks. Alert if last_archived_time is older than your threshold - say, 5 minutes. Some teams also monitor the file count in pg_wal directly."

[PAUSE]

[SAY] "One more thing - the difference between archive_mode and archive_command. archive_mode tells PostgreSQL to call the archive_command. Changing archive_mode requires a restart. Changing archive_command only needs a reload. That is why we could fix this without any downtime."

[SAY] "That is SURVIVE 02 complete."
