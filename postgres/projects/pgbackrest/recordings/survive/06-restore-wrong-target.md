# Video Script: SURVIVE 06 - Restore with Wrong PITR Target

**Video file:** `pgbackrest-survive-06-restore-wrong-target.mp4`
**Estimated length:** 10 minutes
**Severity:** HIGH
**Runbook:** [Link](../../survive/06-restore-wrong-target/runbook.md)
**Inject first:** `bash survive/06-restore-wrong-target/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Something is wrong. A point-in-time recovery was performed, but the data does not look right. Records are missing. The recovery target was too early. Let me show you."

[TYPE] `sudo -i -u postgres`

[TYPE] `/usr/pgsql-16/bin/psql -p 5432 -d appdb`

[TYPE] `SELECT * FROM pitr_markers ORDER BY id;`

[WAIT for output]

[SHOW] only MARKER_T1 - T2 and T3 are missing

[SAY] "We should see three markers - T1, T2, and T3. Only T1 is here. The recovery stopped too early and missed the other two."

[PAUSE]

[SAY] "Let's check the other tables."

[TYPE] `SELECT count(*) FROM employees;`

[WAIT for output]

[SHOW] count of 0

[SAY] "Employees table is empty."

[TYPE] `SELECT count(*) FROM departments;`

[WAIT for output]

[SHOW] the error - relation does not exist

[SAY] "Departments table does not even exist. The recovery landed at a point before the important data was inserted. We need to re-recover to the correct point in time."

[TYPE] `\q`

[TYPE] `exit`

---

## DIAGNOSE [1:15]

[SAY] "Step 1: Find the correct target timestamp. The inject script saved a state file with the timestamps of each marker."

[TYPE] `cat /tmp/chaos-06-state.env`

[WAIT for output]

[SHOW] the CORRECT_TARGET timestamp

[SAY] "There are three markers. T1 was inserted first, then T2, then T3. After all three markers were created, destructive commands deleted employees and dropped departments. The CORRECT_TARGET is one second after T3 - that captures all three markers and all the data, but stops before the destructive operations."

[PAUSE]

[SAY] "The first recovery used a target that was too early - it only captured T1. We need to re-recover to the CORRECT_TARGET timestamp."

---

## FIX [2:30]

[SAY] "Here is the process. Stop PostgreSQL, re-restore with the correct target using the delta flag, then start PostgreSQL."

[PAUSE]

[SAY] "Step 1: Stop PostgreSQL. pgBackRest modifies files in the data directory, so PostgreSQL must be stopped first."

[TYPE] `sudo systemctl stop postgresql-16`

[TYPE] `sudo systemctl status postgresql-16 | head -5`

[WAIT for output]

[SHOW] "inactive (dead)"

[SAY] "Stopped."

[PAUSE]

[SAY] "Step 2: Re-restore with the correct PITR target. The delta flag is critical here - it checksums existing files and only replaces those that differ from the backup. Without delta, pgBackRest requires the data directory to be empty. With delta, re-recovery on a 500 gig database might transfer 50 megabytes instead of the full 500 gig."

[TYPE] `sudo -i -u postgres`

[SAY] "Replace the timestamp here with the CORRECT_TARGET value from the state file."

[TYPE] `pgbackrest --stanza=main --delta --type=time --target="2026-04-20 10:00:21.345678+00" --target-action=promote restore`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Restore complete."

[TYPE] `exit`

[PAUSE]

[SAY] "Step 3: Start PostgreSQL. It will replay WAL up to our target timestamp."

[TYPE] `sudo systemctl start postgresql-16`

[WAIT a few seconds]

[TYPE] `sudo systemctl status postgresql-16 | head -5`

[WAIT for output]

[SHOW] "active (running)"

---

## VERIFY [5:30]

[SAY] "Let's verify we got the right data back."

[TYPE] `sudo -i -u postgres`

[TYPE] `/usr/pgsql-16/bin/psql -p 5432 -d appdb`

[TYPE] `SELECT * FROM pitr_markers ORDER BY id;`

[WAIT for output]

[SHOW] all three markers - T1, T2, T3

[SAY] "All three markers are present. T1, T2, and T3."

[TYPE] `SELECT count(*) FROM employees;`

[WAIT for output]

[SHOW] count of 50

[SAY] "50 employees. Data is back."

[TYPE] `SELECT count(*) FROM departments;`

[WAIT for output]

[SHOW] count of 5

[SAY] "5 departments. The table exists and has data. This is the correct recovery point."

[TYPE] `\q`

[PAUSE]

[SAY] "One more step - take a fresh full backup. After PITR, the database is on a new timeline. We want a clean backup chain."

[TYPE] `pgbackrest --stanza=main --type=full backup`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Fresh backup taken."

[TYPE] `exit`

---

## CONCEPTS [8:00]

[SAY] "The most common PITR mistake is picking the wrong target. Too early and you lose data. Too late and you include the destructive event you were trying to undo."

[PAUSE]

[SAY] "Every time PostgreSQL recovers, it creates a new timeline. If you recover twice - first to the wrong target, then to the correct one - you create two new timelines. pgBackRest tracks these and can restore across them. The timeline ID is the first 8 hex characters in WAL file names."

[PAUSE]

[SAY] "In production, here is the safer approach. Use target-action=pause instead of promote. This keeps the database in read-only recovery mode at the target point. You can query the data to verify it looks correct. If it does, run SELECT pg_wal_replay_resume() to promote. If it does not, you stop PostgreSQL and re-recover to a different target. This avoids the cycle of recover, check, oops wrong target, stop, re-recover."

[PAUSE]

[SAY] "To find the correct target timestamp, check application logs, PostgreSQL logs, and pg_stat_statements if you have it enabled. If you have pgAudit, check the audit log. Always subtract a small margin - a few seconds - from the destructive event time."

[SAY] "That is SURVIVE 06 complete."
