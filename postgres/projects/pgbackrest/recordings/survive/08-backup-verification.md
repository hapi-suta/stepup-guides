# Video Script: SURVIVE 08 - Backup Verification Failure

**Video file:** `pgbackrest-survive-08-backup-verification.mp4`
**Estimated length:** 6 minutes
**Severity:** MEDIUM
**Runbook:** [Link](../../survive/08-backup-verification-failure/runbook.md)
**Inject first:** `bash survive/08-backup-verification-failure/inject.sh`

---

## SCENE SET [0:00]

[SAY] "Your automated backup verification is failing. pgbackrest check and pgbackrest info are both returning errors. Let me show you what you would see."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main check`

[WAIT for error output]

[SHOW] the ERROR mentioning `/tmp/pgbackrest-decoy` in the path

[SAY] "pgBackRest is looking for backups in /tmp/pgbackrest-decoy. That is not where our backup repository lives. Something is misconfigured."

[PAUSE]

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] "missing stanza path" error

[SAY] "No backups visible. status says missing stanza path. We know backups exist - they were working yesterday. This is a configuration problem. Let's dig in."

---

## DIAGNOSE [0:50]

[SAY] "Step 1: Read the actual config file."

[TYPE] `cat /etc/pgbackrest.conf`

[WAIT for output]

[SHOW] the line `repo1-path=/tmp/pgbackrest-decoy`

[SAY] "Found it. repo1-path is set to /tmp/pgbackrest-decoy instead of /opt/pgsql/backup/pgbackrest. That is problem number one - pgBackRest is looking for its backup repository in the wrong location."

[PAUSE]

[SAY] "Step 2: Check archive_command. Sometimes there is more than one thing broken."

[TYPE] `/usr/pgsql-16/bin/psql -p 5432`

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] `pgbackrest --stanza=wrong_stanza archive-push %p`

[SAY] "Problem number two. The archive_command references stanza wrong_stanza instead of main. So we have two independent misconfigurations - the repo path in pgbackrest.conf and the stanza name in archive_command. Fixing only one will not fully resolve this."

[TYPE] `\q`

[TYPE] `exit`

---

## FIX [2:15]

[SAY] "Fix both problems. First, the repo path."

[TYPE] `sudo vi /etc/pgbackrest.conf`

[SAY] "Change repo1-path from /tmp/pgbackrest-decoy to /opt/pgsql/backup/pgbackrest."

[SHOW] editing the line to `repo1-path=/opt/pgsql/backup/pgbackrest`

[SAY] "Save and exit vi."

[PAUSE]

[SAY] "Verify the change."

[TYPE] `grep repo1-path /etc/pgbackrest.conf`

[WAIT for output]

[SHOW] the correct path

[SAY] "Good. Let's confirm pgBackRest can see backups now."

[TYPE] `sudo -i -u postgres`

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[SHOW] backup info with status ok

[SAY] "Backups are visible again. Repo path is fixed."

[PAUSE]

[SAY] "Now fix the archive_command."

[TYPE] `/usr/pgsql-16/bin/psql -p 5432`

[TYPE] `ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';`

[WAIT for output]

[TYPE] `SELECT pg_reload_conf();`

[WAIT for output]

[SAY] "Verify the change."

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] the correct pgbackrest command with stanza=main

[SAY] "Both fixes are in place."

[TYPE] `\q`

---

## VERIFY [3:45]

[SAY] "Run the full end-to-end check."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Check passes. That validates the config file, repo access, PostgreSQL connectivity, and WAL archiving all in one command."

[PAUSE]

[SAY] "Let's confirm archiving works with a manual WAL switch."

[TYPE] `/usr/pgsql-16/bin/psql -p 5432`

[TYPE] `SELECT pg_switch_wal();`

[WAIT 5 seconds]

[TYPE] `SELECT last_archived_wal, failed_count, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] recent `last_archived_time`

[SAY] "last_archived_time is within the last minute. Archiving is working. The failed_count may have some old failures from before the fix - that is fine as long as it is not increasing."

[TYPE] `\q`

[TYPE] `exit`

---

## CONCEPTS [5:00]

[SAY] "This scenario had two independent misconfigurations. That is common in practice - one change cascades or someone makes multiple edits at once. When troubleshooting pgBackRest, follow this diagnostic flow."

[PAUSE]

[SAY] "Start with pgbackrest check - the end-to-end test. If it fails, run pgbackrest info to see if the repo is accessible. If info fails, the problem is the repo path or stanza config in pgbackrest.conf. If info works but check fails, the problem is archive_command in PostgreSQL. Also check pg_stat_archiver for the PostgreSQL-side archiving status."

[PAUSE]

[SAY] "Remember that pgbackrest.conf and archive_command are two separate configuration systems. pgbackrest.conf is pgBackRest's own config file. archive_command is a PostgreSQL parameter. They must agree on the stanza name. Changing one without the other is a very common source of failures."

[PAUSE]

[SAY] "In production, prevent configuration drift with three practices. First, version-control pgbackrest.conf and use a config management tool like Ansible. Second, run pgbackrest check every 15 minutes and alert on failures. Third, after any system update or config change, run pgbackrest check before walking away."

[SAY] "That is SURVIVE 08 complete."
