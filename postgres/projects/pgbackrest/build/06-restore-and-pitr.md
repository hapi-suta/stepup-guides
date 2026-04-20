# Restore and Point-in-Time Recovery

**Estimated time:** 35 minutes

**What you'll learn:**
- How to restore a full backup after a disaster
- How to perform point-in-time recovery (PITR)
- What WAL timelines are
- Why you need a new full backup after PITR

**Prerequisites:**
- Completed guides 01-05 (pgBackRest installed, configured, backups taken)
- PostgreSQL 16 is running

---

This guide has two parts. Part A teaches you a basic full restore. Part B teaches you PITR - restoring to a specific moment in time. Both are critical skills.

---

# Part A: Full Restore

## Step 1: Connect to your server

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Insert a marker row

We'll insert a special row so we can verify it survives the restore. Switch to the postgres user.

```bash
sudo -i -u postgres
```

First, create a database called `appdb` for our PITR exercises.

```bash
createdb appdb
```

Now open psql connected to the `appdb` database.

```bash
psql -d appdb
```

Create an `employees` table with an auto-incrementing ID and a name column.

```sql
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);
```

```
Expected output (yours will differ):
CREATE TABLE
```

Insert some sample data so the table isn't empty.

```sql
INSERT INTO employees (name)
SELECT 'Employee ' || generate_series(1, 10000);
```

```
Expected output (yours will differ):
INSERT 0 10000
```

Now insert a marker row into the employees table.

```sql
INSERT INTO employees (name) VALUES ('RESTORE_TEST_MARKER');
```

```
Expected output (yours will differ):
INSERT 0 1
```

Verify it's there.

```sql
SELECT * FROM employees WHERE name = 'RESTORE_TEST_MARKER';
```

```
Expected output (yours will differ):
 id |        name
----+---------------------
 42 | RESTORE_TEST_MARKER
(1 row)
```

Now force a WAL switch so this change gets archived.

```sql
SELECT pg_switch_wal();
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 0/B000100
(1 row)
```

Exit psql.

```
\q
```

Now take a fresh backup so our marker row is included.

```bash
pgbackrest --stanza=main --type=full backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin 2.54: ...
...
P00   INFO: backup command end: completed successfully
...
```

---

## Step 3: Simulate a disaster

We'll simulate a catastrophic failure by stopping PostgreSQL and renaming the data directory. This is what it looks like when a disk dies or someone accidentally deletes your data.

Stop PostgreSQL. You need to exit the postgres user first because `systemctl` requires root-level access.

```bash
exit
```

Stop the PostgreSQL service.

```bash
sudo systemctl stop postgresql-16
```

Verify it's stopped.

```bash
sudo systemctl status postgresql-16
```

```
Expected output (yours will differ):
● postgresql-16.service - PostgreSQL 16 database server
     Active: inactive (dead)
...
```

Now rename the data directory to simulate data loss.

```bash
sudo mv /opt/pgsql/data /opt/pgsql/data.broken
```

`mv` renames the directory. Your data is still there (under `data.broken`), but PostgreSQL can't find it anymore.

---

## Step 4: Restore from backup

Switch to the postgres user to run the restore.

```bash
sudo -i -u postgres
```

Run the restore command.

```bash
pgbackrest --stanza=main restore
```

```
Expected output (yours will differ):
P00   INFO: restore command begin 2.54: ...
P00   INFO: repo1: restore backup set 20260420-115000F
P00   INFO: write updated /opt/pgsql/data/postgresql.auto.conf
P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
P00   INFO: restore size = 823.8MB, file total = 1247
P00   INFO: restore command end: completed successfully
...
```

pgBackRest created a brand new `/opt/pgsql/data` directory and restored all files from the backup.

---

## Step 5: Start PostgreSQL

Exit the postgres user first.

```bash
exit
```

Start the PostgreSQL service.

```bash
sudo systemctl start postgresql-16
```

Verify it's running.

```bash
sudo systemctl status postgresql-16
```

```
Expected output (yours will differ):
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
...
```

---

## Step 6: Verify the restore

Switch back to the postgres user.

```bash
sudo -i -u postgres
```

Check that the marker row survived.

```bash
psql -d appdb
```

```sql
SELECT * FROM employees WHERE name = 'RESTORE_TEST_MARKER';
```

```
Expected output (yours will differ):
 id |        name
----+---------------------
 42 | RESTORE_TEST_MARKER
(1 row)
```

The marker row is there. The restore worked.

Let's also verify `labdb` is intact.

```
\q
```

```bash
psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"
```

```
Expected output (yours will differ):
  count
---------
 5000000
(1 row)
```

Your count should match what was in the database before the disaster. If you used scale factor 50 in earlier guides, this will be 5,000,000.

---

## Step 7: Clean up the broken data directory

Now remove the old data directory we renamed earlier.

```bash
exit
```

```bash
sudo rm -rf /opt/pgsql/data.broken
```

`rm -rf` removes a directory and everything inside it. The `-r` flag means recursive (delete subdirectories too) and `-f` means force (don't ask for confirmation).

---

# Part B: Point-in-Time Recovery (PITR)

> **Concept: PITR = time travel for your database**
> Point-in-time recovery lets you restore your database to any specific moment in time - not just the moment a backup was taken. This is possible because pgBackRest archives every WAL file. It restores the backup and then replays WAL files up to your chosen timestamp.

---

## Step 8: Prepare for PITR demonstration

Switch to the postgres user.

```bash
sudo -i -u postgres
```

First, make sure we have a good full backup and archiving is working.

```bash
pgbackrest --stanza=main check
```

```
Expected output (yours will differ):
...
P00   INFO: check command end: completed successfully
```

Now open psql connected to appdb.

```bash
psql -d appdb
```

Insert a row that should SURVIVE the PITR.

```sql
INSERT INTO employees (name) VALUES ('BEFORE_PITR');
```

```
Expected output (yours will differ):
INSERT 0 1
```

Now record the exact current timestamp. This is the moment we'll restore TO.

```sql
SELECT now();
```

```
Expected output (yours will differ):
              now
-------------------------------
 2026-04-20 12:00:15.123456+00
(1 row)
```

**Write down this timestamp exactly.** You'll need it in Step 11. For example: `2026-04-20 12:00:15.123456+00`

---

## Step 9: Wait and insert another row

Wait about 10 seconds. This creates a clear gap in time between our two inserts.

Now insert a row that should NOT survive the PITR.

```sql
INSERT INTO employees (name) VALUES ('AFTER_PITR');
```

```
Expected output (yours will differ):
INSERT 0 1
```

Verify both rows exist right now.

```sql
SELECT * FROM employees WHERE name IN ('BEFORE_PITR', 'AFTER_PITR');
```

```
Expected output (yours will differ):
 id |    name
----+-------------
 43 | BEFORE_PITR
 44 | AFTER_PITR
(2 rows)
```

Both rows are there. After PITR, only `BEFORE_PITR` should exist.

Now force a WAL switch to make sure everything is archived.

```sql
SELECT pg_switch_wal();
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 0/D000100
(1 row)
```

Exit psql.

```
\q
```

---

## Step 10: Stop PostgreSQL and prepare for PITR

Exit the postgres user.

```bash
exit
```

Stop PostgreSQL.

```bash
sudo systemctl stop postgresql-16
```

Switch back to the postgres user for the restore.

```bash
sudo -i -u postgres
```

---

## Step 11: Restore with a PITR target

Now run the restore with a time target. **Replace the timestamp below with the one you wrote down in Step 8.**

```bash
pgbackrest --stanza=main --delta --type=time --target="2026-04-20 12:00:15.123456+00" --target-action=promote restore
```

Let's explain each flag:
- `--delta` - only restores files that are different from what's already on disk (faster than removing everything and starting over)
- `--type=time` - tells pgBackRest we're doing a point-in-time recovery using a timestamp
- `--target="..."` - the timestamp to recover to. PostgreSQL will replay WAL files up to this exact moment and then stop
- `--target-action=promote` - after reaching the target time, promote the server to accept new writes

> **Concept: --delta**
> Without `--delta`, you'd need to delete PGDATA first and restore everything from scratch. With `--delta`, pgBackRest compares each file on disk to the backup and only restores files that differ. This is much faster for large databases.

> **Concept: --target-action=promote**
> After reaching the recovery target, PostgreSQL needs to know what to do. `promote` means "stop replaying WAL, start accepting new writes." Without this, the server would stay in recovery mode and refuse all write operations.

```
Expected output (yours will differ):
P00   INFO: restore command begin 2.54: ...
P00   INFO: repo1: restore backup set 20260420-115000F, recovery will start at ...
P00   INFO: remove invalid files/links/paths from /opt/pgsql/data
P00   INFO: write updated /opt/pgsql/data/postgresql.auto.conf
P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
P00   INFO: restore command end: completed successfully
...
```

---

## Step 12: Start PostgreSQL

Exit the postgres user.

```bash
exit
```

Start PostgreSQL.

```bash
sudo systemctl start postgresql-16
```

PostgreSQL will start up and replay WAL files up to the target timestamp. This may take a few seconds.

Verify it's running.

```bash
sudo systemctl status postgresql-16
```

```
Expected output (yours will differ):
● postgresql-16.service - PostgreSQL 16 database server
     Active: active (running) since ...
...
```

---

## Step 13: Verify the PITR

Switch to the postgres user.

```bash
sudo -i -u postgres
```

Open psql connected to appdb.

```bash
psql -d appdb
```

Check for the rows.

```sql
SELECT * FROM employees WHERE name IN ('BEFORE_PITR', 'AFTER_PITR');
```

```
Expected output (yours will differ):
 id |    name
----+-------------
 43 | BEFORE_PITR
(1 row)
```

`BEFORE_PITR` exists - it was inserted before our target timestamp.
`AFTER_PITR` is gone - it was inserted after our target timestamp and was never replayed.

This is PITR in action. You just traveled back in time.

> **Concept: WAL timeline**
> Every time you do a PITR, PostgreSQL creates a new "timeline." Think of it like forking a road. The original timeline (where `AFTER_PITR` existed) is still in the WAL archives, but your database is now on a new timeline that branched off at your target timestamp. Old backups were taken on the old timeline and can't be used for future restores on this new timeline.

Exit psql.

```
\q
```

---

## Step 14: Take a new full backup

After a PITR, your old backups are on a different timeline. You MUST take a new full backup to establish a baseline for future backups on this new timeline.

> **Concept: Always take a new full backup after PITR**
> After PITR, your database is on a new WAL timeline. Your previous backups and their WAL chains belong to the old timeline. If you tried to do a differential or incremental backup without a new full, the chain would be broken. Always start fresh with a new full backup after any PITR.

```bash
pgbackrest --stanza=main --type=full backup
```

```
Expected output (yours will differ):
P00   INFO: backup command begin 2.54: ...
...
P00   INFO: backup command end: completed successfully
...
```

Verify the new backup.

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): ...

        full backup: 20260420-121000F
            timestamp start/stop: ...
            ...
```

You should see a new full backup listed. The stanza status should be `ok`.

Now exit the postgres user.

```bash
exit
```

---

## What you built

- Performed a full restore after simulating a disaster
- Performed point-in-time recovery to a specific timestamp
- Verified that PITR correctly includes "before" data and excludes "after" data
- Took a new full backup after PITR to establish a new baseline

## Verification

Switch to the postgres user.

```bash
sudo -i -u postgres
```

Run the check command to make sure everything is healthy.

```bash
pgbackrest --stanza=main check
```

```
Expected output (yours will differ):
...
P00   INFO: check command end: completed successfully
```

Confirm the PITR results.

```bash
psql -d appdb -c "SELECT * FROM employees WHERE name IN ('BEFORE_PITR', 'AFTER_PITR', 'RESTORE_TEST_MARKER');"
```

You should see `BEFORE_PITR` and `RESTORE_TEST_MARKER` but NOT `AFTER_PITR`.

```bash
exit
```

## What's next

In the next guide, you'll set up retention policies to automatically manage old backups and schedule automated backups with cron.
