# Video Script: BUILD 03 - Enable WAL Archiving

**Video file:** `pgbackrest-build-03-wal-archiving.mp4`
**Estimated length:** 10 minutes
**Guide:** [Link to guide](../../build/03-wal-archiving.md)
**Server state required:** PostgreSQL 16 running. pgBackRest installed and stanza created (BUILD 01-02 complete). archive_command still set to /bin/false.

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 3: Enable WAL Archiving."

[SAY] "archive_command is still set to /bin/false. Every WAL file PostgreSQL tries to archive fails. That failure count has been climbing since the moment this server started."

[SAY] "In this video, we fix it. And we're going to watch the first successful archive happen live."

[SAY] "Make sure you've completed BUILD 1 and BUILD 2. Let's go."

---

## STEP 1: SSH into the server [0:25]

[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`

[WAIT for login]

---

## STEP 2: Check the damage [0:35]

[SAY] "Let's see how bad it's gotten since last time. Switch to the postgres user."

[TYPE] `sudo -i -u postgres`

[TYPE] `psql`

[WAIT for psql prompt]

[TYPE] `SELECT archived_count, failed_count, last_failed_time FROM pg_stat_archiver;`

[WAIT for output]

[SHOW] the failed_count number

[SAY] "Look at that failed_count. It's even higher than last time. Every few seconds, PostgreSQL tries to archive a WAL file, and every single time it fails because /bin/false returns an error."

[SHOW] the archived_count of 0

[SAY] "And archived_count is still zero. Not a single WAL file has been safely archived. Let's fix this right now."

---

## STEP 3: Fix the archive_command [1:30]

[SAY] "We're going to use ALTER SYSTEM to change the archive_command. This is the safest way to change PostgreSQL settings."

[CONCEPT] "ALTER SYSTEM writes your change to a file called postgresql.auto.conf - a separate file that PostgreSQL reads after the main postgresql.conf. This is safer than editing postgresql.conf directly because you can't accidentally break the main config file with a typo."

[SAY] "Here's the command. Type this carefully."

[TYPE] `ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=main archive-push %p';`

[WAIT for "ALTER SYSTEM" confirmation]

[PAUSE]

[CONCEPT] "Let me explain what this command does. When PostgreSQL finishes writing a WAL file, it runs the archive_command. We're telling it to run pgbackrest archive-push. The archive-push command takes a single WAL file and copies it from PostgreSQL's pg_wal directory into the pgBackRest repository, compressing it along the way."

[SAY] "And that %p at the end - that's a placeholder. When PostgreSQL runs this command, it replaces %p with the full file path of the WAL file that needs to be archived. So it might become something like /opt/pgsql/data/pg_wal/000000010000000000000001."

---

## STEP 4: Reload the configuration [3:00]

[SAY] "We've written the new setting to disk, but PostgreSQL hasn't read it yet. We need to tell PostgreSQL to reload its configuration."

[TYPE] `SELECT pg_reload_conf();`

[WAIT for output]

[SHOW] the "t" result

[SAY] "t means true - the reload was successful."

[CONCEPT] "This is a reload, not a restart. A reload tells PostgreSQL to re-read its configuration files without interrupting any connections or transactions. Your database stays fully available. You only need a restart for certain settings like shared_buffers, but archive_command is not one of them."

---

## STEP 5: Verify the new archive_command [3:40]

[SAY] "Let's confirm PostgreSQL picked up the change."

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] the pgbackrest archive-push command in the output

[PAUSE]

[SAY] "There it is. pgbackrest --stanza=main archive-push %p. No more /bin/false. This is the moment the fix takes effect."

---

## STEP 6: Force a WAL switch [4:15]

[SAY] "Now, PostgreSQL only archives a WAL file when it's full - that's usually 16 megabytes of changes. We don't want to sit here and wait for that, so we're going to force PostgreSQL to switch to a new WAL file right now."

[TYPE] `SELECT pg_switch_wal();`

[WAIT for output]

[SAY] "The output is a WAL position - yours will be different. What just happened is PostgreSQL closed the current WAL file and started a new one. That closed WAL file is now eligible for archiving."

[SAY] "The archiver process runs in the background. Give it a few seconds."

[PAUSE]

---

## STEP 7: The moment of truth [5:00]

[SAY] "Let's check the archiver statistics."

[TYPE] `SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;`

[WAIT for output]

[PAUSE]

[SHOW] archived_count - should be greater than 0

[SAY] "Look at archived_count."

[PAUSE]

[SAY] "It's no longer zero. Your first WAL file was successfully archived."

[SHOW] last_archived_wal column

[SAY] "And there's the name of the WAL file that was just archived. You can see the timestamp too."

[SHOW] failed_count

[SAY] "The failed_count is still high - that's all the failures from before we fixed it. But it should stop increasing now. From this point forward, every archive attempt should succeed."

[SAY] "If your archived_count is still zero, wait about 10 seconds and run the query again. The archiver runs in the background and might need a moment."

[PAUSE]

[SAY] "Let's exit psql."

[TYPE] `\q`

---

## STEP 8: See the archived WAL file [6:15]

[SAY] "Let's go look at the actual archived file in the pgBackRest repository."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/archive/main/`

[WAIT for output]

[SHOW] the 16-1 directory

[SAY] "16-1 - that's named after the PostgreSQL version 16 and timeline 1."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/`

[WAIT for output]

[TYPE] `ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/0000000100000000/`

[WAIT for output]

[SHOW] the .lz4 compressed WAL file

[SAY] "There it is. Your archived WAL file. Notice the .lz4 extension - pgBackRest compressed it automatically using lz4, just like we configured. A 16-megabyte WAL file gets compressed down to a fraction of its size."

---

## STEP 9: Full stanza check [7:15]

[SAY] "Let's run the pgBackRest check one more time. Remember, last time this gave us an error about archive_command."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully" line

[SAY] "Completed successfully. No more errors. pgBackRest can see the database, the repository is healthy, and WAL archiving is working end to end."

[PAUSE]

[SAY] "Let's exit the postgres user."

[TYPE] `exit`

---

## OUTRO [8:30]

[SAY] "That's BUILD 3 complete."

[SAY] "We fixed the archive_command. We changed it from /bin/false - which always fails - to pgbackrest archive-push, which compresses and stores WAL files safely in the repository."

[SAY] "We forced a WAL switch and watched the first successful archive happen. We saw the compressed file in the repository. And the stanza check passed with no errors."

[SAY] "Your database is now continuously archiving every WAL file. Every transaction, every change - it's all being safely stored."

[SAY] "In the next video, BUILD 4, we take your first full backup. See you there."
