# Build 06: Point-in-Time Recovery (PITR)

The most critical skill in a DBA's toolkit. You will restore a database to an
exact moment in time - proving you can recover from accidental data loss, bad
deployments, and corruption.

Steps 1-5 run on NODE1 (primary). Steps 6-10 run on NODE2 (backup server).

---

## 1. Note the current time and LSN

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Record the current time and WAL position. This is your "before" marker. The `now()` function returns the current date and time, and `pg_current_wal_lsn()` returns the current position in the write-ahead log.

```bash
psql -c "SELECT now() AS current_time, pg_current_wal_lsn() AS current_lsn;"
```

Write down these values.

```
Expected output (yours will differ):
         current_time         | current_lsn
------------------------------+-------------
 2026-04-19 01:25:52.05165+00 | 1/26000060
(1 row)
```

## 2. Insert known data (this SHOULD survive PITR)

**Run on NODE1 (pg-primary):**

Still as postgres, insert test rows into appdb. These represent "good" data that existed before the mistake:

```bash
psql -d appdb -c "
INSERT INTO employees (name, department)
VALUES ('pitr_survivor_1', 'recovery'),
       ('pitr_survivor_2', 'recovery'),
       ('pitr_survivor_3', 'recovery');
"
```

```
Expected output:
INSERT 0 3
```

Verify the rows were inserted. The `-d appdb` flag connects to the `appdb` database. The `WHERE` clause filters to only the rows we just inserted.

```bash
psql -d appdb -c "SELECT * FROM employees WHERE department = 'recovery';"
```

Expected: 3 rows.

```
Expected output (yours will differ):
   id   |      name       | department |           hired_at
--------+-----------------+------------+-------------------------------
 100001 | pitr_survivor_1 | recovery   | 2026-04-19 01:25:52.111266+00
 100002 | pitr_survivor_2 | recovery   | 2026-04-19 01:25:52.111266+00
 100003 | pitr_survivor_3 | recovery   | 2026-04-19 01:25:52.111266+00
(3 rows)
```

## 3. Record the recovery target time

**Run on NODE1 (pg-primary):**

This is the moment you want to recover TO. Everything up to this point should
be preserved:

```bash
psql -c "SELECT now() AS recovery_target_time;"
```

```
Expected output (yours will differ):
     recovery_target_time
------------------------------
 2026-04-19 01:26:00.23778+00
(1 row)
```

**Write this timestamp down exactly.** You will use it in step 7.

Example: `2026-04-17 14:30:00.000000+00`

The `+00` at the end means UTC timezone. The `.000000` is microseconds (you can omit this). Use the exact timestamp you recorded above - do not copy this example value.

## 4. Insert MORE data (this should NOT survive PITR)

**Run on NODE1 (pg-primary):**

Wait a few seconds, then insert data that represents "the mistake":

```bash
sleep 3
```

```bash
psql -d appdb -c "
INSERT INTO employees (name, department)
VALUES ('pitr_should_be_gone_1', 'mistake'),
       ('pitr_should_be_gone_2', 'mistake'),
       ('pitr_should_be_gone_3', 'mistake');
"
```

```
Expected output:
INSERT 0 3
```

Simulate a destructive accident - delete the entire marketing department:

```bash
psql -d appdb -c "DELETE FROM employees WHERE department = 'marketing';"
```

```
Expected output (yours will differ):
DELETE 20000
```

Check the damage. This query groups all employees by department and counts how many are in each one.

```bash
psql -d appdb -c "
SELECT department, count(*) FROM employees GROUP BY department ORDER BY department;
"
```

Expected: `marketing` department is gone, `mistake` department exists.

## 5. Force WAL archiving and take a fresh base backup

**Run on NODE1 (pg-primary):**

Force a WAL switch so all changes are archived. This function closes the current WAL file and starts a new one, which triggers the archive_command to copy the completed file.

```bash
psql -c "SELECT pg_switch_wal();"
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 1/27000078
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Wait for archiving:

```bash
sleep 5
```

Verify WAL files are on NODE2. The `-lt` flags list files in long format sorted by newest first, and `head -5` shows only the first 5 results.

```bash
ssh postgres@pg-backup "ls -lt /opt/pgsql/backup/archive/ | head -5"
```

> **Concept - WAL is the timeline**: Every INSERT, UPDATE, DELETE, and DDL
> statement generates WAL records. Each record has a timestamp and LSN (Log
> Sequence Number). PITR works by replaying these records from the base backup's
> starting point and stopping at your target time. The WAL is a complete,
> ordered history of every change.

## 6. Prepare the recovery environment on NODE2

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup) as ec2-user.**

Install the PostgreSQL server package. The `-y` flag answers "yes" to all prompts automatically. We only had the client tools until now:

```bash
sudo dnf install -y postgresql16-server
```

Do NOT run initdb. We will restore from the base backup instead.

Create the data directory. The `-p` flag creates parent directories if they do not exist:

```bash
sudo mkdir -p /opt/pgsql/data
```

Create the log directory:

```bash
sudo mkdir -p /opt/pgsql/log
```

Create the WAL directory:

```bash
sudo mkdir -p /opt/pgsql/wal
```

Set ownership so postgres owns everything. The `-R` flag applies the ownership change recursively to all files and subdirectories:

```bash
sudo chown -R postgres:postgres /opt/pgsql
```

Lock down the data directory permissions. `700` means only the owner (postgres) can read, write, or enter this directory:

```bash
sudo chmod 700 /opt/pgsql/data
```

Override the systemd service to use our custom data directory. This command opens an editor where you can add a drop-in configuration:

```bash
sudo systemctl edit postgresql-16
```

This opens an editor. Add these two lines:

```
[Service]
Environment=PGDATA=/opt/pgsql/data
```

Save and exit, then reload systemd so it picks up the change:

```bash
sudo systemctl daemon-reload
```

> **Concept - Scratch instance**: We install the PG server on NODE2 solely to
> run recovery. In production, you would spin up a fresh VM for this. Never
> restore onto a running production server. The pattern is: restore to a scratch
> instance, verify the data, then extract what you need.

## 7. Restore the base backup and configure recovery

**Run on NODE2 (pg-backup):**

Copy the plain base backup into the PG data directory. The `-a` flag preserves file permissions, timestamps, and ownership:

```bash
sudo cp -a /opt/pgsql/backup/basebackup/plain_backup/* /opt/pgsql/data/
```

Set ownership on the restored data directory:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data/
```

Remove any existing WAL from the backup. We want PostgreSQL to replay from the archive instead.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Remove existing WAL files. This clears out the WAL files that came with the base backup so PostgreSQL will fetch the archived copies instead:

```bash
rm -rf /opt/pgsql/data/pg_wal/*
```

Ensure the pg_wal directory exists:

```bash
mkdir -p /opt/pgsql/data/pg_wal
```

Create the recovery configuration. In PG 12+, recovery settings go in
`postgresql.auto.conf` and you create a signal file.

Open the configuration file with vim:

```bash
vim /opt/pgsql/data/postgresql.auto.conf
```

Press `G` to go to the last line of the file, then press `o` to open a new line below and enter insert mode. Type the following three lines:

```
# PITR Recovery Settings
restore_command = 'cp /opt/pgsql/backup/archive/%f %p'
recovery_target_time = '2026-04-17 14:30:00.000000+00'
recovery_target_action = 'pause'
```

**Replace the `recovery_target_time` value with the exact timestamp you recorded in step 3.**

The `+00` at the end means UTC timezone. The `.000000` is microseconds (you can omit this). Use the exact timestamp you recorded in step 3 - do not copy this example value.

Press `Esc` to exit insert mode, then type `:wq` and press Enter to save and quit.

Create the recovery signal file:

```bash
touch /opt/pgsql/data/recovery.signal
```

Creating this empty file tells PostgreSQL to start in recovery mode when it next starts up. PostgreSQL will read the recovery settings from `postgresql.auto.conf` and replay WAL files until it reaches the target time. Once recovery is complete and PostgreSQL promotes to normal mode, it automatically deletes this file.

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user on NODE2.**

> **Concept - recovery.signal**: This file tells PostgreSQL to start in recovery
> mode. PG reads `restore_command` and `recovery_target_*` from postgresql.conf
> (or postgresql.auto.conf). Once recovery reaches the target, the signal file
> is removed automatically (if action is `promote`) or left in place (if action
> is `pause`).

> **Concept - restore_command**: The inverse of archive_command. During recovery,
> PostgreSQL calls this command to fetch each WAL file it needs. The `%f` is the
> WAL filename and `%p` is where PostgreSQL wants it placed. Since our WAL
> archive is on the same machine (NODE2), a simple `cp` works. In production
> with remote archives, you would use `rsync`, `aws s3 cp`, or pgBackRest.

> **Concept - recovery_target_action**: Three options:
> - `pause`: Recovery reaches the target and waits. You can inspect the data,
>   then manually promote. This is the safest choice.
> - `promote`: Automatically promotes to a writable primary after reaching target.
> - `shutdown`: Shuts down after reaching target. Useful for automated pipelines.

## 8. Start PostgreSQL in recovery mode

**Run on NODE2 (pg-backup):**

Start PostgreSQL. It will detect recovery.signal and enter recovery mode:

```bash
sudo systemctl start postgresql-16
```

Watch the recovery progress in the log file. The `-f` flag follows the file in real time, showing new lines as they are written:

```bash
sudo tail -f /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected log messages:

```
LOG:  starting point-in-time recovery to ...
LOG:  restored log file "000000010000000000000001" from archive
...
LOG:  recovery stopping before commit of transaction ...
LOG:  pausing at the end of recovery
```

Press `Ctrl+C` to stop tailing the log.

Switch to the postgres user to check recovery status:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Check whether PostgreSQL is in recovery mode:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

This returns `t` (true) if PostgreSQL is still in recovery mode, or `f` (false) if it is running normally.

Expected: `t` (true - the server is paused in recovery).

```
Expected output:
 pg_is_in_recovery
-------------------
 t
(1 row)
```

## 9. Verify the recovery - the moment of truth

**Run on NODE2 (pg-backup):**

Still as postgres, check that the "survivor" data exists:

```bash
psql -d appdb -c "SELECT * FROM employees WHERE department = 'recovery';"
```

Expected: 3 rows (pitr_survivor_1, pitr_survivor_2, pitr_survivor_3).

```
Expected output (yours will differ):
   id   |      name       | department |           hired_at
--------+-----------------+------------+-------------------------------
 100001 | pitr_survivor_1 | recovery   | 2026-04-19 01:25:52.111266+00
 100002 | pitr_survivor_2 | recovery   | 2026-04-19 01:25:52.111266+00
 100003 | pitr_survivor_3 | recovery   | 2026-04-19 01:25:52.111266+00
(3 rows)
```

Check that the "mistake" data does NOT exist:

```bash
psql -d appdb -c "SELECT * FROM employees WHERE department = 'mistake';"
```

Expected: 0 rows.

```
Expected output:
 id | name | department | hired_at
----+------+------------+----------
(0 rows)
```

Check that the deleted marketing department is STILL THERE:

```bash
psql -d appdb -c "SELECT count(*) FROM employees WHERE department = 'marketing';"
```

Expected: approximately 20000 rows (the DELETE from step 4 has been undone).

Get a full count by department:

```bash
psql -d appdb -c "
SELECT department, count(*) FROM employees GROUP BY department ORDER BY department;
"
```

Expected: all five original departments present, no `mistake` department.

> **Concept - PITR proved**: You just recovered the database to exactly the state
> it was in at your target time. Data inserted before that time exists. Data
> inserted after that time is gone. A destructive DELETE that happened after the
> target time has been reversed. This is the power of PITR.

## 10. Promote the recovered instance

**Run on NODE2 (pg-backup):**

Still as postgres. Once you are satisfied with the recovery, resume WAL replay to promote. This function tells PostgreSQL to finish recovery and become a writable server:

```bash
psql -c "SELECT pg_wal_replay_resume();"
```

```
Expected output:
 pg_wal_replay_resume
----------------------

(1 row)
```

Or promote directly using pg_ctl. The `promote` subcommand tells PostgreSQL to exit recovery mode. The `-D` flag specifies the data directory:

```bash
pg_ctl promote -D /opt/pgsql/data
```

```
Expected output:
waiting for server to promote.... done
server promoted
```

Verify it is no longer in recovery:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

This returns `t` (true) if PostgreSQL is still in recovery mode, or `f` (false) if it is running normally.

Expected: `f` (false - now a standalone writable primary).

```
Expected output:
 pg_is_in_recovery
-------------------
 f
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user on NODE2.**

> **Concept - Post-promotion timeline**: After promotion, PostgreSQL creates a
> new timeline (you can see the timeline ID increment in `pg_control`). This
> prevents confusion between WAL from the original primary and WAL from the
> recovered instance. If you need to keep the original primary running, you
> now have two independent clusters.

## 11. PITR using LSN target

**Run on NODE1 (pg-primary):**

Instead of a time target, you can target a specific LSN (Log Sequence Number).

First, exit NODE2 if you are still connected:

```bash
exit
```

**You are now on NODE1 (pg-primary) as ec2-user.**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Get the current LSN before making changes. This function returns the current write position in the WAL stream:

```bash
psql -c "SELECT pg_current_wal_lsn() AS target_lsn;"
```

```
Expected output (yours will differ):
  target_lsn
--------------
 1/26000060
(1 row)
```

The recovery configuration would use:

```
recovery_target_lsn = '0/1A000060'
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user on NODE1.**

> **Concept - LSN vs time target**: LSN targets are more precise than time
> targets. A time target can be ambiguous if the server clock was adjusted.
> LSN is a monotonically increasing position in the WAL stream - it is never
> ambiguous. Use LSN when you need exact precision (e.g., recovering to just
> before a specific transaction).

## 12. Named restore points

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Create a named restore point before a deployment. This function writes a named marker into the WAL stream that you can target during recovery:

```bash
psql -c "SELECT pg_create_restore_point('pre_deployment_v2');"
```

```
Expected output (yours will differ):
 pg_create_restore_point
-------------------------
 1/26002358
(1 row)
```

The recovery configuration would use:

```
recovery_target_name = 'pre_deployment_v2'
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user on NODE1.**

> **Concept - Named restore points**: pg_create_restore_point() writes a named
> marker into the WAL stream. You can recover to that exact point using
> `recovery_target_name`. This is cleaner than remembering timestamps or LSNs.
> Best practice: create a restore point before every deployment, migration, or
> batch job. Name it meaningfully - `pre_deploy_v2.3.1`, `before_migration_042`.

## 13. The side-restore pattern

When you need to recover specific rows without affecting the current primary:

1. Restore to a scratch instance (as you just did)
2. Query the scratch instance for the lost data
3. Export the rows you need
4. Import them back into the production primary

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup) as ec2-user.**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Export the recovered marketing rows to a CSV file. The `\COPY` command is a psql-specific command (note the backslash). It copies data between a file and a table. This is different from the SQL `COPY` command which runs on the server.

```bash
psql -d appdb -c "\COPY (SELECT * FROM employees WHERE department = 'marketing' LIMIT 100) TO '/tmp/marketing_recovery.csv' CSV HEADER"
```

```
Expected output:
COPY 100
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user on NODE2.**

Copy the file to NODE1. The `scp` command securely copies files between hosts over SSH:

```bash
scp /tmp/marketing_recovery.csv postgres@pg-primary:/tmp/
```

Exit NODE2 back to NODE1:

```bash
exit
```

**You are now on NODE1 (pg-primary) as ec2-user.**

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Import the recovered rows back into production. The `\COPY` command is a psql-specific command (note the backslash). It copies data between a file and a table. This is different from the SQL `COPY` command which runs on the server. The `FROM` keyword means we are reading from the CSV file into the table.

```bash
psql -d appdb -c "\COPY employees (id, name, department, hired_at) FROM '/tmp/marketing_recovery.csv' CSV HEADER"
```

```
Expected output:
COPY 100
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user on NODE1.**

> **Concept - Side-restore**: This pattern avoids the downtime of a full PITR on
> production. You spin up a temporary instance, recover to the point before the
> data loss, extract the missing rows, and insert them back into production. The
> production database stays online throughout. This is the pattern you will use
> most often in real incidents.

## 14. Clean up NODE2

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup) as ec2-user.**

Stop PostgreSQL:

```bash
sudo systemctl stop postgresql-16
```

Clear the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Exit back to NODE1:

```bash
exit
```

**You are now on NODE1 (pg-primary) as ec2-user.**

---

## Checkpoint

- [x] Inserted known data with a recorded timestamp
- [x] Inserted "mistake" data after the target time
- [x] Restored base backup on NODE2 at /opt/pgsql/data
- [x] Configured restore_command and recovery_target_time
- [x] Started PG in recovery mode with recovery.signal
- [x] Verified: survivor data exists, mistake data does not
- [x] Verified: deleted marketing department was restored
- [x] Promoted the recovered instance
- [x] Understand LSN targets vs time targets
- [x] Understand named restore points (pg_create_restore_point)
- [x] Understand the side-restore pattern
- [x] Cleaned up NODE2

Proceed to `07-install-pgbackrest.md`.
