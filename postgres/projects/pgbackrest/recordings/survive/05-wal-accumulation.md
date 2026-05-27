# Video Script: SURVIVE 05 - WAL Accumulation

**Video file:** `pgbackrest-survive-05-wal-accumulation.mp4`
**Estimated length:** 8 minutes
**Severity:** CRITICAL
**Runbook:** [Link](../../survive/05-wal-accumulation/runbook.md)
**Inject first:** `bash survive/05-wal-accumulation/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Something is broken. You got a critical alert - pg_wal has 50-plus WAL files and disk is at 85 percent. Let me show you what that looks like."

[TYPE] `df -h /`

[WAIT for output]

[SHOW] the `Use%` column at 85% or higher

[SAY] "Disk is 85 percent full. That is in the danger zone."

[TYPE] `du -sh /opt/pgsql/data/pg_wal/`

[WAIT for output]

[SAY] "Over a gigabyte in WAL files alone."

[TYPE] `ls /opt/pgsql/data/pg_wal/ | wc -l`

[WAIT for output]

[SAY] "Over 60 WAL files. A healthy system has 5 to 15. This is way too many. If this keeps growing, the disk fills up and PostgreSQL crashes. Let's diagnose."

---

## DIAGNOSE [0:50]

[SAY] "Step 1: Check the archiver status. WAL files pile up when archiving is broken."

[TYPE] `sudo -i -u postgres`

[TYPE] `/usr/pgsql-16/bin/psql -p 5432`

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_failed_wal, last_failed_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] the high `failed_count` and recent `last_failed_time`

[SAY] "failed_count is high and last_failed_time is very recent. Archiving is actively failing. Every time PostgreSQL tries to archive a WAL file, it fails. The file stays in pg_wal. PostgreSQL retries. Fails again. Meanwhile, new WAL files keep being created."

[PAUSE]

[SAY] "Step 2: Check what archive_command is set to."

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] `/bin/false`

[SAY] "archive_command is /bin/false. Same problem as scenario 02 - a command that always returns failure. Every archive attempt fails, so WAL files accumulate forever."

---

## FIX [2:15]

[SAY] "Fix the archive_command, reload, and let PostgreSQL work through the backlog."

[TYPE] `ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';`

[WAIT for output]

[TYPE] `SELECT pg_reload_conf();`

[WAIT for output]

[SAY] "Good. Now let's verify the change took effect."

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] the correct pgbackrest archive-push command

[SAY] "Correct. Now force a checkpoint. This tells PostgreSQL to flush everything to disk and allows WAL files to be recycled once they are archived."

[TYPE] `CHECKPOINT;`

[WAIT for output]

[SAY] "Now the archiver will start working through the backlog. It processes one WAL file at a time, in order. With 60-plus files, this takes a minute or two."

[PAUSE]

[SAY] "Let's watch it catch up."

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SAY] "Run this a few more times over the next 30 seconds. You should see archived_count climbing and last_archived_wal advancing."

[WAIT 15 seconds]

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SAY] "archived_count is increasing. The archiver is catching up."

[PAUSE]

[SAY] "Let's also clean up the temp table that the inject script created."

[TYPE] `\c labdb`

[TYPE] `DROP TABLE IF EXISTS chaos_wal_bloat;`

[WAIT for output]

[TYPE] `\q`

[TYPE] `exit`

---

## VERIFY [4:30]

[SAY] "Let's check if disk pressure is dropping."

[TYPE] `du -sh /opt/pgsql/data/pg_wal/`

[WAIT for output]

[SAY] "Down from over a gig to around 128 megabytes. WAL files are being recycled as they get archived."

[TYPE] `ls /opt/pgsql/data/pg_wal/ | wc -l`

[WAIT for output]

[SAY] "File count is back to a healthy number - under 20."

[TYPE] `df -h /`

[WAIT for output]

[SAY] "Disk usage is well below 85 percent. The pressure is relieved."

[PAUSE]

[SAY] "Final check - pgBackRest end-to-end."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Everything is healthy."

[TYPE] `exit`

---

## CONCEPTS [6:00]

[SAY] "This scenario is about understanding the WAL lifecycle. A WAL file goes through five stages: active, complete, archive pending, archived, and recyclable. When archiving breaks, files get stuck at stage three - archive pending - and pile up. They can never reach stage five - recyclable - so the disk fills."

[PAUSE]

[SAY] "When pg_wal fills the entire disk, PostgreSQL enters a PANIC state. It cannot write new WAL, so all transactions halt. The server crashes. To restart, you need to either free disk space or fix archiving first."

[PAUSE]

[SAY] "In production, you would put pg_wal on a separate mount point from the rest of the filesystem. That way, WAL accumulation does not affect the OS or the data files. Monitor four things: pg_wal directory size, WAL file count, pg_stat_archiver failed_count, and time since last_archived_time."

[PAUSE]

[SAY] "One critical warning - if disk is about to fill and you cannot wait for archiving, you can use pg_archivecleanup to remove old WAL files. But this breaks the WAL chain and makes point-in-time recovery impossible for the removed range. Only do it if the alternative is a full crash."

[SAY] "That is SURVIVE 05 complete."
