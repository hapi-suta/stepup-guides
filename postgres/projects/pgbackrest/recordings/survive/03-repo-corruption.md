# Video Script: SURVIVE 03 - Backup Repository Corruption

**Video file:** `pgbackrest-survive-03-repo-corruption.mp4`
**Estimated length:** 8 minutes
**Severity:** CRITICAL
**Runbook:** [Link](../../survive/03-repo-corruption/runbook.md)
**Inject first:** `bash survive/03-repo-corruption/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Something is broken. Your monitoring says pgBackRest cannot list backups. The backup repository might be corrupted. Let me show you what you would see."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main info`

[WAIT for error output]

[SHOW] the ERROR line mentioning `unable to load info file` and `backup.info`

[SAY] "See that? pgBackRest cannot read backup.info. That is the master catalog that tracks every backup in the repository. Without it, pgBackRest cannot list, verify, or restore any backups - even if the actual backup data files are sitting right there on disk."

[PAUSE]

[SAY] "This is critical. If the database fails right now, we might not be able to restore. Let's diagnose and fix this."

---

## DIAGNOSE [0:50]

[SAY] "Step 1: Let's confirm with a stanza check."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for error output]

[SAY] "Same error. The repository metadata is broken."

[PAUSE]

[SAY] "Step 2: Let's look at the actual repo directory to understand the damage."

[TYPE] `ls -la /opt/pgsql/backup/pgbackrest/backup/main/`

[WAIT for output]

[SHOW] the tiny backup.info files (10 bytes) and the backup directory

[SAY] "Look at backup.info - it is only 10 bytes. A valid backup.info is much larger. It has been corrupted. The backup directory itself is still here though. Let's check if the backup data is usable."

[TYPE] `ls -la /opt/pgsql/backup/pgbackrest/backup/main/20260420-120000F/`

[WAIT for output]

[SAY] "The pg_data directory is there, but the backup.manifest file is missing. The manifest lists every file in the backup with its checksum and permissions. Without it, pgBackRest has no way to verify or restore from this backup. The data files might be fine, but they are effectively orphaned."

[PAUSE]

[SAY] "So we have two problems: corrupted backup.info AND a missing backup.manifest. The existing backup is unusable. We need to rebuild the stanza and take a fresh backup."

---

## FIX [2:30]

[SAY] "Here is the plan. Remove the corrupted backup entry, delete the broken stanza, recreate it, and take a new full backup."

[PAUSE]

[SAY] "First, remove the orphaned backup directory. Without a manifest, this data is useless."

[TYPE] `rm -rf /opt/pgsql/backup/pgbackrest/backup/main/20260420-120000F`

[SAY] "Now remove the corrupted backup.info files."

[TYPE] `rm -f /opt/pgsql/backup/pgbackrest/backup/main/backup.info`

[TYPE] `rm -f /opt/pgsql/backup/pgbackrest/backup/main/backup.info.copy`

[PAUSE]

[SAY] "Now we rebuild the stanza. In pgBackRest 2.58 and later, the approach is: stop the stanza, delete it with force, then recreate."

[TYPE] `pgbackrest --stanza=main stop`

[WAIT for output]

[TYPE] `pgbackrest --stanza=main stanza-delete --force`

[WAIT for output]

[SAY] "The force flag lets us delete even though the metadata is damaged."

[TYPE] `pgbackrest --stanza=main stanza-create`

[WAIT for output]

[SAY] "Fresh stanza created. Now we need a backup - the repo is empty right now."

[TYPE] `pgbackrest --stanza=main --type=full backup`

[WAIT for output - this takes 1-3 minutes]

[SAY] "This is a full backup, so it takes a few minutes. On a large production database, this could take much longer."

[SHOW] "completed successfully" in the output

---

## VERIFY [5:30]

[SAY] "Let's verify everything is healthy."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Check passes."

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] the stanza info with one full backup listed

[SAY] "One full backup, status ok. The repository is rebuilt and functional."

[PAUSE]

[SAY] "Let's confirm WAL archiving is still working."

[TYPE] `psql`

[TYPE] `SELECT pg_switch_wal();`

[WAIT 5 seconds]

[TYPE] `SELECT archived_count, failed_count, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SAY] "last_archived_time is recent, failed_count is not climbing. We are back in business."

[TYPE] `\q`

[TYPE] `exit`

---

## CONCEPTS [6:45]

[SAY] "Why did this happen? Repo corruption can come from many sources - disk failures, accidental file deletion, interrupted writes, even ransomware. The key lesson is that a corrupted backup is worse than no backup. With no backups, you know you are unprotected. With corrupted backups, you think you are safe but discover the truth at the worst possible moment - during a disaster."

[PAUSE]

[SAY] "In production, you prevent this with three strategies. First, run pgbackrest verify on a schedule - weekly at minimum. It checks every backup manifest, verifies file checksums, and confirms WAL continuity. Second, use pgBackRest's multi-repo feature. Configure repo1 on local disk and repo2 on S3 or a remote server. Even if repo1 is corrupted, repo2 has a complete independent copy. Third, consider immutable storage like S3 Object Lock to prevent accidental deletion or tampering."

[PAUSE]

[SAY] "And always - always - test your restores regularly. A backup you have never restored is a backup you cannot trust."

[SAY] "That is SURVIVE 03 complete."
