# Video Script: BUILD 06 - Restore and Point-in-Time Recovery

**Video file:** `pgbackrest-build-06-restore-pitr.mp4`
**Estimated length:** 15 minutes
**Guide:** [Link to guide](../../build/06-restore-and-pitr.md)
**Server state required:** Guides 01-05 complete. Multiple backups exist (full, diff, incr). PostgreSQL 16 running. WAL archiving working.

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 6: Restore and Point-in-Time Recovery."
[SAY] "This is the most important video in the entire series. If you can't restore, your backups are worthless. You could have the most sophisticated backup system in the world - if you've never tested a restore, you have nothing."
[SAY] "We're going to do two things today. First, we'll simulate a complete disaster - a dead data directory - and recover from it. Second, we'll do something even more impressive: restore the database to an exact moment in time. Time travel."
[SAY] "Make sure you have completed guides 01 through 05 before starting."

---

# PART A: FULL RESTORE

---

## STEP 1: Connect and switch to postgres [0:45]

[SAY] "Let's connect to the server."
[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`
[WAIT for login]
[SAY] "Switching to the postgres user."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]

---

## STEP 2: Create a marker row [1:15]

[SAY] "Before we simulate a disaster, we need proof that the restore actually works. We're going to insert a special marker row into the database. After the restore, if that row is still there, we know the restore worked."
[SAY] "First, let's create a database called appdb for our exercises."
[TYPE] `createdb appdb`
[WAIT for output]
[SAY] "Now let's connect to appdb."
[TYPE] `psql -d appdb`
[WAIT for psql prompt]
[SAY] "Let's create an employees table."
[TYPE] `CREATE TABLE employees (id SERIAL PRIMARY KEY, name TEXT NOT NULL);`
[WAIT for CREATE TABLE]
[SAY] "And insert 10,000 rows of sample data so the table has some substance."
[TYPE] `INSERT INTO employees (name) SELECT 'Employee ' || generate_series(1, 10000);`
[WAIT for INSERT 0 10000]
[SAY] "Now here's our marker row."
[TYPE] `INSERT INTO employees (name) VALUES ('RESTORE_TEST_MARKER');`
[WAIT for INSERT 0 1]
[SAY] "Let's verify it's there."
[TYPE] `SELECT * FROM employees WHERE name = 'RESTORE_TEST_MARKER';`
[WAIT for output]
[SHOW] the RESTORE_TEST_MARKER row
[SAY] "There it is. Remember this row. We're about to destroy the database and bring it back."
[PAUSE]
[SAY] "Let's force a WAL switch so this data gets archived."
[TYPE] `SELECT pg_switch_wal();`
[WAIT for output]
[SAY] "Now exit psql."
[TYPE] `\q`
[WAIT for shell prompt]
[SAY] "And take a fresh full backup so our marker row is included."
[TYPE] `pgbackrest --stanza=main --type=full backup`
[WAIT for backup to complete]
[SAY] "Backup complete. Our marker row is safely in the backup repository."
[PAUSE]

---

## STEP 3: Simulate a disaster [3:30]

[SAY] "Now for the dramatic part. We're going to simulate a catastrophic failure. Imagine your disk just died. Your data directory is gone."
[PAUSE]
[SAY] "First, I need to exit the postgres user because systemctl requires root access."
[TYPE] `exit`
[WAIT for prompt change]
[SAY] "Stop PostgreSQL."
[TYPE] `sudo systemctl stop postgresql-16`
[WAIT]
[SAY] "Let's verify it's stopped."
[TYPE] `sudo systemctl status postgresql-16`
[WAIT for output]
[SHOW] "Active: inactive (dead)"
[SAY] "PostgreSQL is down."
[PAUSE]
[SAY] "Now I'm going to rename the data directory. This simulates your disk dying. The data is technically still there under data.broken, but PostgreSQL can't find it."
[TYPE] `sudo mv /opt/pgsql/data /opt/pgsql/data.broken`
[WAIT]
[SAY] "The data directory is gone. If we tried to start PostgreSQL right now, it would fail. There's nothing there."
[PAUSE]

---

## STEP 4: Restore from backup [4:45]

[SAY] "This is the moment of truth. Let's restore."
[SAY] "Switch to the postgres user."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]
[SAY] "And here's the restore command."
[TYPE] `pgbackrest --stanza=main restore`
[SAY] "pgbackrest restore. That's it. One command."
[WAIT for restore to complete]
[SHOW] the restore output - file count, size
[SAY] "Look at that. pgBackRest created a brand new data directory and restored everything from the backup. All the files, all the data, all the configuration."
[PAUSE]

---

## STEP 5: Start PostgreSQL and verify [5:45]

[SAY] "Let's start PostgreSQL back up. I need to exit the postgres user first."
[TYPE] `exit`
[WAIT for prompt change]
[TYPE] `sudo systemctl start postgresql-16`
[WAIT]
[TYPE] `sudo systemctl status postgresql-16`
[WAIT for output]
[SHOW] "Active: active (running)"
[SAY] "PostgreSQL is running again."
[PAUSE]

---

## STEP 6: Verify the marker row [6:15]

[SAY] "The moment of truth. Did our marker row survive?"
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]
[TYPE] `psql -d appdb`
[WAIT for psql prompt]
[TYPE] `SELECT * FROM employees WHERE name = 'RESTORE_TEST_MARKER';`
[WAIT for output]
[SHOW] the RESTORE_TEST_MARKER row
[PAUSE]
[SAY] "There it is. RESTORE_TEST_MARKER. The restore worked. We destroyed the data directory and brought everything back from a backup."
[SAY] "Let's also check that labdb survived."
[TYPE] `\q`
[WAIT]
[TYPE] `psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"`
[WAIT for output]
[SAY] "Five million rows, exactly what we had before. Everything is intact."
[PAUSE]

---

## STEP 7: Clean up [7:00]

[SAY] "Let's remove the old broken data directory. We don't need it anymore."
[TYPE] `exit`
[WAIT for prompt change]
[TYPE] `sudo rm -rf /opt/pgsql/data.broken`
[WAIT]
[SAY] "That's Part A complete. Full restore after a disaster. Now let's do something even more powerful."
[PAUSE]

---

# PART B: POINT-IN-TIME RECOVERY

---

## STEP 8: Set up for PITR [7:30]

[SAY] "Now for time travel."
[PAUSE]
[CONCEPT] "Point-in-time recovery lets you restore your database to any specific moment in time - not just when a backup was taken. This works because pgBackRest archives every single WAL file. It restores the closest backup, then replays WAL files forward to your target timestamp and stops."
[PAUSE]
[SAY] "Let's switch to the postgres user."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]
[SAY] "Let's make sure archiving is healthy."
[TYPE] `pgbackrest --stanza=main check`
[WAIT for output]
[SAY] "Good. Everything checks out."
[SAY] "Now let's open psql connected to appdb."
[TYPE] `psql -d appdb`
[WAIT for psql prompt]
[SAY] "I'm going to insert a row called BEFORE_PITR. This row was inserted before our target time, so it should survive the recovery."
[TYPE] `INSERT INTO employees (name) VALUES ('BEFORE_PITR');`
[WAIT for INSERT 0 1]
[PAUSE]

---

## STEP 9: Record the target timestamp [8:45]

[SAY] "Now we record the exact timestamp. This is the moment we're going to restore to. Write this down."
[TYPE] `SELECT now();`
[WAIT for output]
[SHOW] the timestamp
[SAY] "Write down this timestamp exactly as shown. You'll need it in a minute. Copy every digit, including the timezone offset."
[PAUSE]
[SAY] "Now we wait about 10 seconds. We need a clear gap in time between our two inserts."
[PAUSE] - wait 10 seconds
[SAY] "Now I'm inserting a row called AFTER_PITR. This row is being inserted after our target time. When we do the recovery, this row should not survive. It should be gone."
[TYPE] `INSERT INTO employees (name) VALUES ('AFTER_PITR');`
[WAIT for INSERT 0 1]
[SAY] "Let's verify both rows exist right now."
[TYPE] `SELECT * FROM employees WHERE name IN ('BEFORE_PITR', 'AFTER_PITR');`
[WAIT for output]
[SHOW] both rows
[SAY] "Both rows are here right now. BEFORE_PITR and AFTER_PITR. After the recovery, only BEFORE_PITR should remain."
[SAY] "Let's force a WAL switch to archive everything."
[TYPE] `SELECT pg_switch_wal();`
[WAIT for output]
[TYPE] `\q`
[WAIT for shell prompt]
[PAUSE]

---

## STEP 10: Stop PostgreSQL [10:00]

[SAY] "Time to stop PostgreSQL and do the PITR."
[TYPE] `exit`
[WAIT for prompt change]
[TYPE] `sudo systemctl stop postgresql-16`
[WAIT]
[SAY] "Now switching back to postgres for the restore."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]

---

## STEP 11: Restore with PITR target [10:30]

[SAY] "Here's the restore command. I'm going to type it and then explain every flag."
[TYPE] `pgbackrest --stanza=main --delta --type=time --target="2026-04-20 12:00:15.123456+00" --target-action=promote restore`
[SAY] "Before I press Enter, let me explain each flag."
[CONCEPT] "Dash dash delta - instead of deleting the data directory and restoring everything from scratch, pgBackRest compares each file on disk to the backup and only restores files that are different. Much faster for large databases."
[PAUSE]
[SAY] "Dash dash type equals time - we're doing a point-in-time recovery using a timestamp."
[SAY] "Dash dash target equals the timestamp you wrote down. PostgreSQL will replay WAL files up to this exact moment and then stop. Anything that happened after this moment is thrown away."
[SAY] "Dash dash target-action equals promote - after reaching the target time, promote the server to accept new writes. Without this, PostgreSQL would stay in recovery mode and refuse all writes."
[PAUSE]
[SAY] "Now let's run it."
[WAIT for restore to complete]
[SHOW] the restore output
[SAY] "Restore complete. pgBackRest restored the backup and configured PostgreSQL to replay WAL up to our target timestamp."
[PAUSE]

---

## STEP 12: Start PostgreSQL [12:00]

[SAY] "Let's start PostgreSQL. It will replay WAL files up to our target time during startup."
[TYPE] `exit`
[WAIT for prompt change]
[TYPE] `sudo systemctl start postgresql-16`
[WAIT]
[TYPE] `sudo systemctl status postgresql-16`
[WAIT for output]
[SHOW] "Active: active (running)"
[SAY] "It's running. PostgreSQL replayed the WAL files, hit our target timestamp, and promoted itself."
[PAUSE]

---

## STEP 13: Verify the PITR [12:30]

[SAY] "This is the big moment. Did we actually travel back in time?"
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]
[TYPE] `psql -d appdb`
[WAIT for psql prompt]
[TYPE] `SELECT * FROM employees WHERE name IN ('BEFORE_PITR', 'AFTER_PITR');`
[WAIT for output]
[PAUSE]
[SHOW] only BEFORE_PITR in the results
[SAY] "Look at that. BEFORE_PITR is there - it was inserted before our target timestamp. But AFTER_PITR is gone. It was inserted after our target timestamp, so PostgreSQL never replayed that transaction."
[SAY] "We just traveled back in time. The database is in the exact state it was at that timestamp."
[PAUSE]
[TYPE] `\q`
[WAIT for shell prompt]

---

## STEP 14: Take a new full backup [13:30]

[CONCEPT] "One critical thing after PITR. Every time you do a point-in-time recovery, PostgreSQL creates a new WAL timeline. Think of it like forking a road. Your old backups are on the old timeline. They can't be used for future restores on this new timeline."
[SAY] "That means you must take a new full backup right now. This establishes a new baseline on the new timeline."
[TYPE] `pgbackrest --stanza=main --type=full backup`
[WAIT for backup to complete]
[SAY] "Let's verify."
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SHOW] the new full backup
[SAY] "Good. New full backup on the new timeline. You're protected again."
[TYPE] `exit`
[WAIT for prompt change]
[PAUSE]

---

## OUTRO [14:30]

[SAY] "That's BUILD 6 complete. You just did two of the most important things a DBA can do."
[SAY] "First, you restored a database from a backup after a complete disaster. The data directory was gone and you brought everything back with one command."
[SAY] "Second, you performed point-in-time recovery. You restored the database to an exact moment in time, proving that data inserted after that moment was correctly excluded."
[SAY] "These are not theoretical skills. This is what you do at 3 AM when someone calls you saying the database is down."
[SAY] "Next up is BUILD 7: Retention and Scheduling. We'll set up automatic cleanup of old backups and schedule everything with cron so you never have to run a backup manually again."
[SAY] "Pause this video and practice on your own server before moving on."
