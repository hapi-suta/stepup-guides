# Video Script: SURVIVE 04 - Backup Expiry Crisis

**Video file:** `pgbackrest-survive-04-backup-expiry.mp4`
**Estimated length:** 6 minutes
**Severity:** HIGH
**Runbook:** [Link](../../survive/04-backup-expiry-crisis/runbook.md)
**Inject first:** `bash survive/04-backup-expiry-crisis/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Something is wrong. Your backup retention is dangerously thin. You might be one bad backup away from zero protection. Let me show you."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] only one full backup listed

[SAY] "See that? Only one full backup. If this single backup is corrupted, or if the disk it lives on fails, you have nothing. Zero backups. Total data loss risk. Let's find out why and fix it."

---

## DIAGNOSE [0:45]

[SAY] "Step 1: Check the retention setting. Retention controls how many backups pgBackRest keeps."

[TYPE] `exit`

[TYPE] `sudo cat /etc/pgbackrest.conf`

[WAIT for output]

[SHOW] the line `repo1-retention-full=1`

[SAY] "There it is. repo1-retention-full equals 1. That means pgBackRest keeps only one full backup. Every time a new full backup completes, the previous one is deleted. You are always running with exactly one backup - no fallback, no safety net."

[PAUSE]

[SAY] "Think about what happens when you take your next scheduled full backup. The new backup finishes. pgBackRest deletes the old one. If the new backup is corrupted? You have nothing."

---

## FIX [1:45]

[SAY] "The fix is two parts. First, change the retention setting. Second, take a new full backup immediately so we have two."

[TYPE] `sudo vi /etc/pgbackrest.conf`

[SAY] "Find the line repo1-retention-full=1 and change the 1 to 2."

[SHOW] editing the line to `repo1-retention-full=2`

[SAY] "Save and exit vi."

[PAUSE]

[SAY] "Let's verify the change."

[TYPE] `sudo grep repo1-retention-full /etc/pgbackrest.conf`

[WAIT for output]

[SHOW] `repo1-retention-full=2`

[SAY] "Good. Now we need a second backup. Right now we still only have one."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main --type=full backup`

[WAIT for output - takes a few minutes]

[SAY] "Taking a full backup. This is urgent - until this completes, we still have only one backup. On a production system, you would kick this off immediately and monitor it."

[SHOW] "completed successfully"

---

## VERIFY [3:30]

[SAY] "Let's verify we now have two backups."

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] two full backups listed

[SAY] "Two full backups. If either one is bad, we have the other as a fallback. That is the minimum safe configuration."

[PAUSE]

[SAY] "Let's also check that WAL archiving is continuous."

[TYPE] `psql`

[TYPE] `SELECT pg_switch_wal();`

[WAIT 5 seconds]

[TYPE] `SELECT archived_count, failed_count, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SAY] "last_archived_time is recent, failed_count is stable. Archiving is healthy."

[TYPE] `\q`

[SAY] "Let's do one final check."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Everything checks out."

[TYPE] `exit`

---

## CONCEPTS [5:00]

[SAY] "Why does this matter so much? With retention set to 1, one corrupted backup equals total data loss. The cost of storing one extra backup - a few hundred gigabytes - is nothing compared to losing your entire database."

[PAUSE]

[SAY] "In production, the typical retention depends on your recovery requirements. Minimum safe is 2 full backups. A common production setup is 4 full backups with weekly fulls - that gives you a month of coverage. For regulated industries, use time-based retention instead of count-based. Set repo1-retention-full-type to time and repo1-retention-full to 30 - that keeps all backups from the last 30 days, regardless of how many there are."

[PAUSE]

[SAY] "Monitor three things: the number of full backups in the repo - alert if it drops below 2. The age of the newest backup - alert if it is older than your backup schedule. And WAL archive continuity - use pgbackrest verify to detect gaps."

[SAY] "That is SURVIVE 04 complete."
