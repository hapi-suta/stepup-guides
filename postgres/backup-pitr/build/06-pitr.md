# Build 06: Point-in-Time Recovery (PITR)

The most critical skill in a DBA's toolkit. You will restore a database to an
exact moment in time - proving you can recover from accidental data loss, bad
deployments, and corruption.

Steps 1-5 run on NODE1 (primary). Steps 6-10 run on NODE2 (backup server).

---

## 1. Note the current time and LSN

Switch to the postgres user:

```bash
sudo -i -u postgres
```

Record the current time and WAL position. This is your "before" marker:

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

Still as postgres, insert test rows into appdb. These represent "good" data that existed before the mistake:

```bash
psql -d appdb -c "
INSERT INTO employees (name, department)
VALUES ('pitr_survivor_1', 'recovery'),
       ('pitr_survivor_2', 'recovery'),
       ('pitr_survivor_3', 'recovery');
"
```

Verify the rows were inserted:

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

## 4. Insert MORE data (this should NOT survive PITR)

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

Simulate a destructive accident - delete the entire marketing department:

```bash
psql -d appdb -c "DELETE FROM employees WHERE department = 'marketing';"
```

Check the damage:

```bash
psql -d appdb -c "
SELECT department, count(*) FROM employees GROUP BY department ORDER BY department;
"
```

Expected: `marketing` department is gone, `mistake` department exists.

## 5. Force WAL archiving and take a fresh base backup

Force a WAL switch so all changes are archived:

```bash
psql -c "SELECT pg_switch_wal();"
```

Exit back to ec2-user:

```bash
exit
```

Wait for archiving:

```bash
sleep 5
```

Verify WAL files are on NODE2:

```bash
ssh postgres@pg-backup "ls -lt /opt/pgsql/backup/archive/ | head -5"
```

> **Concept - WAL is the timeline**: Every INSERT, UPDATE, DELETE, and DDL
> statement generates WAL records. Each record has a timestamp and LSN (Log
> Sequence Number). PITR works by replaying these records from the base backup's
> starting point and stopping at your target time. The WAL is a complete,
> ordered history of every change.

## 6. Prepare the recovery environment on NODE2

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

Install the PostgreSQL server package. We only had the client tools until now:

```bash
sudo dnf install -y postgresql16-server
```

Do NOT run initdb. We will restore from the base backup instead.

Create the data directory:

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

Set ownership so postgres owns everything:

```bash
sudo chown -R postgres:postgres /opt/pgsql
```

Lock down the data directory permissions:

```bash
sudo chmod 700 /opt/pgsql/data
```

Override the systemd service to use our custom data directory:

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

Copy the plain base backup into the PG data directory:

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

Remove existing WAL files:

```bash
rm -rf /opt/pgsql/data/pg_wal/*
```

Ensure the pg_wal directory exists:

```bash
mkdir -p /opt/pgsql/data/pg_wal
```

Create the recovery configuration. In PG 12+, recovery settings go in
`postgresql.auto.conf` and you create a signal file:

```bash
cat >> /opt/pgsql/data/postgresql.auto.conf <<EOF

# PITR Recovery Settings
restore_command = 'cp /opt/pgsql/backup/archive/%f %p'
recovery_target_time = '2026-04-17 14:30:00.000000+00'
recovery_target_action = 'pause'
EOF
```

**Replace the `recovery_target_time` value with the exact timestamp you recorded in step 3.**

Create the recovery signal file. This tells PostgreSQL to start in recovery mode:

```bash
touch /opt/pgsql/data/recovery.signal
```

Exit back to ec2-user:

```bash
exit
```

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

Start PostgreSQL. It will detect recovery.signal and enter recovery mode:

```bash
sudo systemctl start postgresql-16
```

Watch the recovery progress in the log file:

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

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t` (true - the server is paused in recovery).

```
Expected output:
 pg_is_in_recovery
-------------------
 t
(1 row)
```

## 9. Verify the recovery - the moment of truth

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

Once you are satisfied with the recovery, resume WAL replay to promote:

```bash
psql -c "SELECT pg_wal_replay_resume();"
```

Or promote directly using pg_ctl:

```bash
pg_ctl promote -D /opt/pgsql/data
```

Verify it is no longer in recovery:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f` (false - now a standalone writable primary).

```
Expected output:
 pg_is_in_recovery
-------------------
 f
(1 row)
```

> **Concept - Post-promotion timeline**: After promotion, PostgreSQL creates a
> new timeline (you can see the timeline ID increment in `pg_control`). This
> prevents confusion between WAL from the original primary and WAL from the
> recovered instance. If you need to keep the original primary running, you
> now have two independent clusters.

## 11. PITR using LSN target

Instead of a time target, you can target a specific LSN (Log Sequence Number).

On NODE1, get the current LSN before making changes:

```bash
# On NODE1
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

> **Concept - LSN vs time target**: LSN targets are more precise than time
> targets. A time target can be ambiguous if the server clock was adjusted.
> LSN is a monotonically increasing position in the WAL stream - it is never
> ambiguous. Use LSN when you need exact precision (e.g., recovering to just
> before a specific transaction).

## 12. Named restore points

On NODE1, create a named restore point before a deployment:

```bash
# On NODE1
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

On NODE2, export the recovered marketing rows to a CSV file:

```bash
# Run on NODE2 as postgres
psql -d appdb -c "\COPY (SELECT * FROM employees WHERE department = 'marketing' LIMIT 100) TO '/tmp/marketing_recovery.csv' CSV HEADER"
```

Exit back to ec2-user:

```bash
exit
```

Copy the file to NODE1:

```bash
scp /tmp/marketing_recovery.csv postgres@pg-primary:/tmp/
```

On NODE1, import the recovered rows back into production:

```bash
# Run on NODE1
sudo -i -u postgres
```

```bash
psql -d appdb -c "\COPY employees (id, name, department, hired_at) FROM '/tmp/marketing_recovery.csv' CSV HEADER"
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Side-restore**: This pattern avoids the downtime of a full PITR on
> production. You spin up a temporary instance, recover to the point before the
> data loss, extract the missing rows, and insert them back into production. The
> production database stays online throughout. This is the pattern you will use
> most often in real incidents.

## 14. Clean up NODE2

Stop PostgreSQL and clear the data directory on NODE2:

```bash
# Run on NODE2
ssh ec2-user@pg-backup
```

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
