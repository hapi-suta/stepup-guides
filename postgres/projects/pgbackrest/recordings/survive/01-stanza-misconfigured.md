# Video Script: SURVIVE 01 - Stanza Misconfigured

**Video file:** `pgbackrest-survive-01-stanza-misconfigured.mp4`
**Estimated length:** 8 minutes
**Severity:** CRITICAL
**Runbook:** [Link](../../survive/01-stanza-misconfigured/runbook.md)
**Inject first:** `bash survive/01-stanza-misconfigured/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Something is broken. You got an alert that pgBackRest stanza check is failing. Let me show you what you would see."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main check`

[WAIT for error output]

[SHOW] the ERROR line mentioning `/opt/pgsql/WRONG_DATA/PG_VERSION`

[SAY] "See that error? pgBackRest is looking for PostgreSQL data in /opt/pgsql/WRONG_DATA. That directory does not exist. Backups are broken, WAL archiving is broken, and your recovery window is getting worse every minute."

[PAUSE 3 seconds]

[SAY] "Let's figure out what happened and fix it."

---

## DIAGNOSE [0:45]

[SAY] "Step 1: The error message already tells us a lot. pgBackRest is looking for PG_VERSION in a directory called WRONG_DATA. That is the pg1-path setting in the config file. Let's look at the config."

[TYPE] `exit`

[TYPE] `sudo cat /etc/pgbackrest.conf`

[WAIT for output]

[SHOW] the line `pg1-path=/opt/pgsql/WRONG_DATA`

[SAY] "There it is. pg1-path is set to /opt/pgsql/WRONG_DATA. That is the setting that tells pgBackRest where your PostgreSQL data directory lives. If this is wrong, pgBackRest cannot read your database files, cannot take backups, and cannot verify that archiving works."

[PAUSE]

[SAY] "Step 2: Let's find out where PostgreSQL actually keeps its data."

[TYPE] `sudo -i -u postgres`

[TYPE] `psql`

[TYPE] `SHOW data_directory;`

[WAIT for output]

[SHOW] `/opt/pgsql/data` in the output

[SAY] "The correct path is /opt/pgsql/data - not WRONG_DATA. Someone changed the config file and got the path wrong."

[TYPE] `\q`

[TYPE] `exit`

---

## FIX [2:30]

[SAY] "Now I know what is wrong. The fix is straightforward - correct the pg1-path in the config file."

[TYPE] `sudo vi /etc/pgbackrest.conf`

[SAY] "Find the line that says pg1-path=/opt/pgsql/WRONG_DATA. Change WRONG_DATA to data."

[SHOW] editing the line to `pg1-path=/opt/pgsql/data`

[SAY] "Save and exit vi - Escape, colon, w, q, Enter."

[PAUSE]

[SAY] "One important thing - pgBackRest reads its config file fresh every time it runs. There is no service to restart. The next pgbackrest command will use the updated config."

---

## VERIFY [3:30]

[SAY] "Let's verify the fix works."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully" in the output

[SAY] "The check passed. pgBackRest can see the data directory now."

[PAUSE]

[SAY] "Let's also confirm backup info is accessible."

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] the stanza status showing "ok" and backup details

[SAY] "Status is ok, we can see our backups. Good."

[PAUSE]

[SAY] "One more thing - let's make sure WAL archiving is working too."

[TYPE] `psql`

[TYPE] `SELECT pg_switch_wal();`

[WAIT 5 seconds]

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] the `last_archived_time` column - should be very recent

[SAY] "last_archived_time is within the last minute and failed_count is not increasing. Archiving is healthy again."

[TYPE] `\q`

[TYPE] `exit`

---

## CONCEPTS [6:00]

[SAY] "Why did this happen? The pg1-path setting is the single most important line in pgbackrest.conf. It connects pgBackRest to your database. When it is wrong, pgBackRest silently stops working. The dangerous part - PostgreSQL keeps running fine. You will not notice anything is broken until you try to take a backup or, worse, until you need to restore."

[PAUSE]

[SAY] "In production, you would prevent this with three things. First, use configuration management like Ansible to template pgbackrest.conf from a single source of truth. Never hand-edit production configs. Second, run pgbackrest check on a schedule - every 5 to 15 minutes - and alert if it fails. Third, monitor pg_stat_archiver for climbing failed_count. If archiving stops, you want to know in minutes, not days."

[PAUSE]

[SAY] "Remember - a backup system that fails silently is worse than no backup system at all. At least with no backups, you know you are unprotected."

[SAY] "That is SURVIVE 01 complete."
