# USE Exercise 03 - Backup Restore Drill

| | |
|---|---|
| **Time** | 25 minutes |
| **What you'll practice** | Restoring a pgBackRest backup to a separate location, starting a second PostgreSQL instance, and verifying data integrity |
| **Prerequisites** | Completed BUILD guides 01-06 (pgBackRest installed, backups taken, familiar with restore process) |

---

## The Scenario

Your compliance team requires a quarterly backup restore test. They want written proof that your backups actually work - that you can restore from a backup and the data is intact.

> "Anyone can take backups. The question is: can you restore them?" - Every DBA who has been burned

You will restore your latest backup to a separate directory and run it as a second PostgreSQL instance to verify everything works. This does NOT affect your running production database.

---

## Exercise 1: Check Your Current Backup

Switch to the postgres user:

```bash
sudo -i -u postgres
```

Check what backups are available:

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000012

        full backup: 20260420-100000F
            timestamp start/stop: 2026-04-20 10:00:00+00 / 2026-04-20 10:02:30+00
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 838.2MB, database backup size: 838.2MB
            repo1: backup set size: 112.5MB, backup size: 112.5MB
...
```

Note the label of the latest backup (the last one listed). You will use it in the restore command if needed. For this exercise, we will let pgBackRest automatically pick the latest backup.

---

## Exercise 2: Record Current Data for Verification

Before restoring, you need to know what the data should look like. Connect to PostgreSQL and record some key numbers.

```bash
psql -d appdb
```

Count the rows in the employees table:

```sql
SELECT COUNT(*) FROM employees;
```

Expected output (yours will differ):

```
 count
-------
   107
(1 row)
```

Write this number down. You will compare it after the restore.

Get a few sample rows to verify later:

```sql
SELECT * FROM employees ORDER BY id LIMIT 5;
```

Expected output (yours will differ):

```
 id |   name    | department_id |   hire_date
----+-----------+---------------+---------------
  1 | Alice     |             1 | 2024-01-15
  2 | Bob       |             2 | 2024-02-20
  3 | Charlie   |             1 | 2024-03-10
  4 | Diana     |             3 | 2024-04-05
  5 | Eve       |             2 | 2024-05-12
(5 rows)
```

Also check the departments table:

```sql
SELECT COUNT(*) FROM departments;
```

Write down this count too.

Exit psql:

```sql
\q
```

> **Concept: Baseline Before Restore**
> Always record key metrics from the live database before doing a restore test. Row counts, checksums, and sample data give you concrete evidence that the restored copy matches the original.

---

## Exercise 3: Create the Restore Directory

You will restore to a completely separate directory. This keeps the restore isolated from your running database.

```bash
mkdir -p /opt/pgsql/restore_test
```

Verify the directory exists and is empty:

```bash
ls -la /opt/pgsql/restore_test/
```

Expected output:

```
total 0
drwxr-xr-x 2 postgres postgres  6 Apr 20 16:20 .
drwxr-xr-x 6 postgres postgres 72 Apr 20 16:20 ..
```

The directory must be empty. pgBackRest will not restore into a directory that already has data.

---

## Exercise 4: Restore the Backup

This is the main event. Restore the latest backup to the test directory.

```bash
pgbackrest --stanza=main --pg1-path=/opt/pgsql/restore_test --type=immediate --target-action=promote restore
```

Let's break down each flag:

- `--stanza=main` - Which backup stanza to restore from.
- `--pg1-path=/opt/pgsql/restore_test` - Where to put the restored files. This overrides the default data directory.
- `--type=immediate` - Stop recovery as soon as the backup is consistent (do not replay WAL files beyond what is needed).
- `--target-action=promote` - After reaching the recovery target, promote the server to accept writes instead of staying in recovery.

Expected output (yours will differ):

```
2026-04-20 16:21:00.123 P00   INFO: restore command begin 2.54: ...
2026-04-20 16:21:00.456 P00   INFO: repo1: restore backup set 20260420-100000F
2026-04-20 16:21:30.789 P00   INFO: write updated /opt/pgsql/restore_test/postgresql.auto.conf
2026-04-20 16:21:31.012 P00   INFO: restore command end: completed successfully
...
```

> **Concept: Restoring Does Not Affect Production**
> Because you specified a different `--pg1-path`, the restore goes to a separate directory. Your running database in `/opt/pgsql/data` is completely untouched.

---

## Exercise 5: Prepare the Restored Instance

Before starting the restored instance, you need to change the port. Two PostgreSQL instances cannot listen on the same port.

Edit the postgresql.conf in the restored directory:

```bash
vi /opt/pgsql/restore_test/postgresql.conf
```

Find the `port` setting and change it:

Press `/` then type `port` and press Enter to search. Change the line to:

```
port = 5433
```

Also find and update the log directory so logs do not conflict:

```
log_directory = '/opt/pgsql/log/restore_test'
```

Save and exit vi (press Esc, then type `:wq` and press Enter).

Create the log directory:

```bash
mkdir -p /opt/pgsql/log/restore_test
```

You also need to update `archive_command` so the restored instance does not try to archive WAL files to the same repository. This would cause conflicts.

```bash
vi /opt/pgsql/restore_test/postgresql.conf
```

Find `archive_command` and change it to:

```
archive_command = '/bin/true'
```

This makes archiving a no-op. The restored test instance does not need to archive WAL.

Save and exit vi (press Esc, then type `:wq` and press Enter).

> **Concept: Port Conflicts**
> Every PostgreSQL instance on the same server must use a different port. The default is 5432. For test restores, use 5433, 5434, etc. If you forget to change the port, the second instance will fail to start with an "Address already in use" error.

---

## Exercise 6: Start the Restored Instance

Start PostgreSQL using the restored data directory:

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/restore_test -l /opt/pgsql/log/restore_test/startup.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

If it does not start, check the log file:

```bash
cat /opt/pgsql/log/restore_test/startup.log
```

Verify the instance is running:

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/restore_test status
```

Expected output (yours will differ):

```
pg_ctl: server is running (PID: 12345)
/usr/pgsql-16/bin/postgres "-D" "/opt/pgsql/restore_test"
```

> **Concept: pg_ctl vs systemctl**
> For test instances, use `pg_ctl` directly instead of `systemctl`. The systemd service (`postgresql-16`) is tied to the production data directory. Using `pg_ctl` gives you full control over which data directory and which port to use.

---

## Exercise 7: Verify the Data

Now connect to the restored instance. Notice the `-p 5433` flag - this tells psql to connect to port 5433 instead of the default 5432.

```bash
psql -p 5433 -d appdb
```

Check the employee count:

```sql
SELECT COUNT(*) FROM employees;
```

**Question:** Does this count match the number you wrote down in Exercise 2?

Check the sample rows:

```sql
SELECT * FROM employees ORDER BY id LIMIT 5;
```

**Question:** Do these rows match what you saw in Exercise 2?

Check the departments count:

```sql
SELECT COUNT(*) FROM departments;
```

**Question:** Does this count match?

Verify you can also connect to the labdb database:

```sql
\c labdb
```

Check the pgbench tables exist:

```sql
\dt
```

Expected output (yours will differ):

```
              List of relations
 Schema |       Name       | Type  |  Owner
--------+------------------+-------+----------
 public | pgbench_accounts | table | postgres
 public | pgbench_branches | table | postgres
 public | pgbench_history  | table | postgres
 public | pgbench_tellers  | table | postgres
(4 rows)
```

Exit psql:

```sql
\q
```

If all counts match and all tables are present, your backup restore test is a SUCCESS.

> **Concept: Verify, Don't Assume**
> A backup that restores without errors is a good sign, but not proof. Always verify the actual data - row counts, sample rows, table structure. A backup could be corrupted in a way that restores "successfully" but has wrong data.

---

## Exercise 8: Stop and Clean Up

You have verified the backup works. Now stop the test instance and clean up.

Stop the restored instance:

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/restore_test stop
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Remove the restore test directory:

```bash
rm -rf /opt/pgsql/restore_test
```

Remove the test log directory:

```bash
rm -rf /opt/pgsql/log/restore_test
```

Verify cleanup is complete:

```bash
ls /opt/pgsql/restore_test
```

Expected output:

```
ls: cannot access '/opt/pgsql/restore_test': No such file or directory
```

Verify your production instance is still running:

```bash
psql -c "SELECT 'Production is running' AS status;"
```

Expected output:

```
        status
----------------------
 Production is running
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

---

## Exercise 9: Document Your Results

For the compliance auditor, write a brief restore test report. It should include:

1. **Date of test:** Today's date
2. **Backup used:** The backup label from Exercise 1
3. **Restore method:** pgBackRest restore to alternate directory
4. **Verification steps performed:**
   - Employee count: [match / no match]
   - Department count: [match / no match]
   - Sample rows: [match / no match]
   - All databases present: [yes / no]
   - All tables present: [yes / no]
5. **Result:** PASS or FAIL
6. **Next scheduled test:** 3 months from today

> **Concept: Untested Backups Are Not Backups**
> A backup you have never restored is a hope, not a backup. Schedule regular restore tests - quarterly at minimum. Document each test. Many compliance frameworks (SOC 2, PCI DSS, HIPAA) require proof of backup testing.

---

## What You Learned

- How to restore a pgBackRest backup to a separate directory
- How to start a second PostgreSQL instance on a different port
- How to avoid port conflicts and archive_command conflicts
- How to verify restored data matches the original
- How to properly stop a test instance and clean up
- How to use `pg_ctl` for managing non-production instances
- Why regular restore testing is required, not optional
