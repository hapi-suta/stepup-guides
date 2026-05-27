# Video Script: SURVIVE 07 - Full Cluster Recovery

**Video file:** `pgbackrest-survive-07-full-cluster-recovery.mp4`
**Estimated length:** 12 minutes
**Severity:** CRITICAL
**Runbook:** [Link](../../survive/07-full-cluster-recovery/runbook.md)
**Inject first:** `bash survive/07-full-cluster-recovery/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Disaster. The PostgreSQL data directory is gone. The entire cluster has been wiped. Let me show you."

[TYPE] `ls -la /opt/pgsql/data/`

[WAIT for output]

[SHOW] empty directory - only `.` and `..`

[SAY] "Empty. All database files, configuration files, everything - gone."

[PAUSE]

[TYPE] `sudo systemctl status postgresql-16 | head -5`

[WAIT for output]

[SHOW] "inactive (dead)" or "failed"

[SAY] "PostgreSQL will not start because there is nothing to start. No pg_control, no data files, no config files. This is a total loss scenario."

[PAUSE]

[SAY] "But we have pgBackRest. The backup repository is stored separately from the data directory. Let's check if our backups survived."

---

## DIAGNOSE [0:50]

[SAY] "Step 1: Check if the backup repository is intact."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] "status: error (no pg_control)" but backup information listed below

[SAY] "The status says error, no pg_control. That is expected - PGDATA is empty, so there is no pg_control file. But look below that. The backup information is right there. We have a full backup. The backup repository is on a separate path - /opt/pgsql/backup/pgbackrest - and it was not affected by whatever wiped PGDATA."

[PAUSE]

[SAY] "This is exactly why you store backups on separate storage. Same disk, different path at minimum. Different disk or remote storage in production."

[PAUSE]

[SAY] "We have everything we need to restore."

---

## FIX [2:00]

[SAY] "Since PGDATA is completely empty, we do a full restore. No delta flag needed - there are no existing files to compare against."

[TYPE] `pgbackrest --stanza=main restore`

[WAIT for output - this takes 1-3 minutes]

[SAY] "pgBackRest is restoring all data files, configuration files, pg_control, and setting up recovery. This can take anywhere from 30 seconds for a small database to hours for a multi-terabyte cluster."

[SHOW] progress lines as they appear

[SHOW] "completed successfully"

[SAY] "Restore complete. Notice the last line of the log says it restored pg_control last. That is a safety feature - if the restore is interrupted, PostgreSQL will refuse to start with a mismatched pg_control. This prevents accidentally starting a partially restored cluster."

[TYPE] `exit`

[PAUSE]

[SAY] "Now start PostgreSQL."

[TYPE] `sudo systemctl start postgresql-16`

[WAIT a few seconds]

[TYPE] `sudo systemctl status postgresql-16 | head -5`

[WAIT for output]

[SHOW] "active (running)"

[SAY] "PostgreSQL is running. It replayed the WAL from the backup and recovered to the latest available point."

---

## VERIFY [4:30]

[SAY] "Let's verify the data is intact."

[TYPE] `sudo -i -u postgres`

[TYPE] `/usr/pgsql-16/bin/psql -p 5432`

[SAY] "First, check that our databases exist."

[TYPE] `\l`

[WAIT for output]

[SHOW] labdb and appdb in the list

[SAY] "Both labdb and appdb are there."

[PAUSE]

[SAY] "Check data in labdb."

[TYPE] `\c labdb`

[TYPE] `SELECT count(*) FROM pgbench_accounts;`

[WAIT for output]

[SHOW] the row count

[SAY] "pgbench_accounts has data. Compare this against the pre-disaster count in the state file if you want to be thorough."

[PAUSE]

[SAY] "Check data in appdb."

[TYPE] `\c appdb`

[TYPE] `SELECT count(*) FROM employees;`

[WAIT for output]

[SHOW] count of 50

[TYPE] `SELECT count(*) FROM departments;`

[WAIT for output]

[SHOW] count of 5

[SAY] "Employees and departments are all there."

[PAUSE]

[SAY] "Check WAL archiving."

[TYPE] `\c postgres`

[TYPE] `SELECT last_archived_wal, last_failed_wal, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] a valid last_archived_wal with empty last_failed_wal

[SAY] "Archiving is working. Notice the WAL file name starts with 00000002 - that is timeline 2. After a restore, PostgreSQL starts a new timeline. The archive_command from the restored configuration is still set correctly, so archiving resumed automatically."

[TYPE] `\q`

[PAUSE]

[SAY] "Final step - take a new full backup to establish a fresh backup chain on the new timeline."

[TYPE] `pgbackrest --stanza=main --type=full backup`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "New backup taken. We are fully recovered and fully protected again."

[TYPE] `exit`

---

## CONCEPTS [9:00]

[SAY] "Let's talk about what just happened and what you would do differently in production."

[PAUSE]

[SAY] "First - full restore versus delta restore. When PGDATA is empty, you do a full restore. pgBackRest copies every file from the backup. When PGDATA has existing files - say, a corrupted cluster - you use the delta flag. Delta checksums each file and only replaces those that differ. On a 2 terabyte database, delta can turn a 2-hour restore into a 2-minute one."

[PAUSE]

[SAY] "Second - what pgBackRest restores. It restores all data files, postgresql.conf, pg_hba.conf, postgresql.auto.conf, and pg_control. It restores pg_control last as a safety measure. It does NOT restore the contents of pg_wal - WAL is replayed from the archive during recovery. It also does not restore external tools, cron jobs, or anything outside PGDATA."

[PAUSE]

[SAY] "Third - what if you lost both PGDATA and the backup repository? If they were on the same disk and it failed, you are looking at data loss. This is why production systems need the backup repo on entirely separate storage - a different physical disk, NFS, or cloud object storage like S3. Use pgBackRest's multi-repo feature for belt-and-suspenders protection."

[PAUSE]

[SAY] "Finally - after any full restore, follow a post-recovery checklist. Verify all databases exist. Check row counts against your baseline. Confirm application users can connect. Verify WAL archiving works. Run pgbackrest check. Take a new full backup. And notify your applications to reconnect."

[PAUSE]

[SAY] "The difference between a 10-minute recovery and a catastrophe is whether you had tested backups on separate storage."

[SAY] "That is SURVIVE 07 complete."
