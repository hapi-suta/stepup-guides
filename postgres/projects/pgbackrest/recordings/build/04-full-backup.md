# Video Script: BUILD 04 - Take Your First Full Backup

**Video file:** `pgbackrest-build-04-full-backup.mp4`
**Estimated length:** 8 minutes
**Guide:** [Link to guide](../../build/04-full-backup.md)
**Server state required:** PostgreSQL 16 running. pgBackRest installed, stanza created, WAL archiving working (BUILD 01-03 complete).

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 4: Take Your First Full Backup."

[SAY] "It's time. A full backup is a complete copy of everything in your database - every database, every table, every index. It's self-contained, meaning you can restore from it without needing any other backup."

[SAY] "Full backups are the foundation. Differential and incremental backups - which we'll cover later - depend on having a full backup to start from."

[SAY] "Make sure you've completed BUILD 1 through 3. WAL archiving must be working. Let's go."

---

## STEP 1: SSH into the server [0:30]

[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`

[WAIT for login]

---

## STEP 2: Switch to the postgres user [0:40]

[SAY] "pgBackRest runs as the postgres user because it needs to read the PostgreSQL data directory."

[TYPE] `sudo -i -u postgres`

---

## STEP 3: Take the full backup [0:50]

[SAY] "Here it is. The backup command."

[TYPE] `pgbackrest --stanza=main --type=full backup`

[SAY] "The --type=full flag tells pgBackRest to back up everything. This will take a minute or two depending on your database size."

[WAIT for output - let each INFO line appear]

[SAY] "Watch the output as it runs."

[PAUSE]

[SAY] "Let me walk through what just happened."

[SHOW] "backup start archive" line

[SAY] "backup start archive - this is the WAL position when the backup began. pgBackRest records this so it knows exactly where the backup starts in the transaction history."

[SHOW] "backup stop archive" line

[SAY] "backup stop archive - the WAL position when the backup ended."

[SHOW] "new backup label" line

[SAY] "The backup label. See that F at the end? F stands for Full. When we take differential backups later, you'll see a D. Incremental will be I. The numbers before the F are the date and time."

[SHOW] "full backup size" and "repo size" line

[PAUSE]

[SAY] "Now this is interesting. Look at the two sizes. Full backup size is the actual size of your database on disk. Repo size is how much space the backup takes after lz4 compression. Look at the difference."

[SHOW] "completed successfully" line

[SAY] "And there it is. Completed successfully. You have your first full backup."

---

## STEP 4: Check backup info [3:00]

[SAY] "pgBackRest keeps detailed records of every backup. Let's see the summary."

[TYPE] `pgbackrest --stanza=main info`

[WAIT for output]

[PAUSE]

[SAY] "Let me walk through every field here."

[SHOW] "status: ok"

[SAY] "Status: ok. Before we took this backup, the status was 'error - no valid backups'. Now it's ok. Your backup infrastructure is healthy."

[SHOW] "wal archive min/max" line

[SAY] "WAL archive min/max shows the range of WAL files stored in the archive. This proves WAL archiving is working alongside your backup."

[SHOW] "full backup" label line

[SAY] "The backup label matches what we saw during the backup."

[SHOW] "timestamp start/stop" line

[SAY] "When the backup started and finished. You can see exactly how long it took."

[SHOW] "database size" and "repo size"

[SAY] "Database size is the uncompressed data. Repo size is what's actually stored after compression."

[SHOW] "backup reference list" - empty

[SAY] "Backup reference list is empty because this is a full backup - it doesn't reference any other backup. When we take differential or incremental backups later, this field will show which full backup they depend on."

---

## STEP 5: Calculate the compression ratio [4:30]

[SAY] "Let's do some quick math. Look at your database size and your repo size."

[CONCEPT] "Take the database size and divide it by the repo size. For example, if your database is about 823 megabytes and the repo size is about 142 megabytes, that's 823 divided by 142 - roughly 5.8x compression. That means pgBackRest is storing your backup at about one-sixth of its original size."

[SAY] "Your numbers will be different, but you should see something in the 4x to 6x range. This adds up fast. If you're managing a 1 terabyte database, your backups might only use 170 gigs."

---

## STEP 6: Explore the backup in the repository [5:20]

[SAY] "Let's go look at what pgBackRest created in the backup directory."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/backup/main/`

[WAIT for output]

[SHOW] the backup directory named with the backup label

[SAY] "See the directory name? It matches the backup label from the info output. The backup.info files are the metadata files we saw in BUILD 2."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/backup/main/20260420-111500F/`

[WAIT for output]

[SAY] "Your directory name will be different - use the label from your own output."

[SHOW] backup.manifest and pg_data

[SAY] "backup.manifest is a detailed record of every single file in the backup - checksums, sizes, timestamps. pgBackRest uses this during restore to verify nothing is corrupted. The .copy file is a redundant copy for safety."

[SAY] "And pg_data - that's the actual backed-up database files."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/backup/main/20260420-111500F/pg_data/`

[WAIT for output]

[SHOW] the PostgreSQL directory structure

[SAY] "This should look familiar. It's the structure of your PostgreSQL data directory - base, global, pg_wal, postgresql.conf - but compressed and stored safely in the backup repository."

---

## STEP 7: Final check [6:45]

[SAY] "Let's run a check to make sure everything is healthy."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] "completed successfully"

[SAY] "Everything checks out."

[SAY] "Let's exit the postgres user."

[TYPE] `exit`

---

## OUTRO [7:15]

[SAY] "That's BUILD 4 complete. You have your first full backup."

[SAY] "Let's think about what we've built over these four videos. In BUILD 1, we found a broken database with no working backup. In BUILD 2, we configured pgBackRest and created the repository. In BUILD 3, we fixed WAL archiving so every transaction is being preserved. And now in BUILD 4, we have a full backup - a complete snapshot of your entire database."

[SAY] "Your database has a safety net now. If the server crashes, if someone drops a table, if something goes wrong - you can restore."

[SAY] "In the next video, BUILD 5, we take differential and incremental backups. These are faster and smaller because they only capture what changed since the last backup."

[SAY] "See you there."
