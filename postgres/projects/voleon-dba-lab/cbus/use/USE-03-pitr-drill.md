# USE Exercise 03: PITR Drill (Point-in-Time Recovery)

| | |
|---|---|
| **Time** | 45 minutes |
| **Server** | pg-primary (3.90.199.62), pg-replica (3.91.32.84) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice
- Taking a pgBackRest full backup manually
- Recording current time and LSN position before a change
- Inserting test data to simulate work that should be recovered
- Recording the timestamp after insert (the recovery target)
- Simulating a "bad" delete that needs to be undone
- Performing a PITR restore to just before the delete
- Verifying the restored data is correct
- Cleaning up and returning the server to normal
- Verifying the pgBackRest backup chain

---

## Before You Start

PITR (Point-in-Time Recovery) lets you restore a database to any moment in the past, as long as you have a base backup and the WAL files that cover that time window. This exercise walks you through the full cycle: backup, make a change, make a mistake, restore to just after the good change but before the mistake.

This drill uses the replica as the restore target so the primary stays running throughout. In a real incident you would restore to a separate recovery server or promote the replica after restoring.

---

## Exercise 1: SSH into the primary

On your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

---

## Exercise 2: Verify pgBackRest is configured

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres /usr/pgsql-17/bin/pgbackrest --stanza=voleon-lab info
```

Expected output (yours will differ):
```
stanza: voleon-lab
    status: ok
    cipher: none

    db (current)
        wal archive min/max (17): 000000010000000000000001/000000010000000800000001

    full backup: 20260601-020000F
        ...
```

If the stanza shows `status: ok`, you are ready to proceed.

---

## Exercise 3: Take a fresh full backup

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/pgbackrest --stanza=voleon-lab --type=full backup
```

Expected output (yours will differ):
```
P00   INFO: backup command begin 2.49: ...
P00   INFO: execute non-exclusive backup begin: backup begins after the requested immediate checkpoint completes
P00   INFO: backup start archive = 000000010000000800000002, lsn = 8/2000028
...
P00   INFO: full backup size = 1.4GB
P00   INFO: backup command end: completed successfully
```

This may take several minutes depending on database size.

---

## Exercise 4: Record the current time and LSN before any changes

As **postgres** on **pg-primary** - connect to quantdb:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Record the current timestamp and LSN. Write these down - you will need them later:

```sql
SELECT NOW() AS current_time, pg_current_wal_lsn() AS current_lsn;
```

Expected output (yours will differ):
```
         current_time          | current_lsn
-------------------------------+-------------
 2026-06-15 14:45:00.123456+00 | 8/30000B8
(1 row)
```

Write down the `current_time` value. This is your "before anything changed" marker.

---

## Exercise 5: Count existing instruments with the PITR-TEST prefix

Still as **postgres** in the psql session on **pg-primary**:

Confirm there are no existing PITR-TEST rows:

```sql
SELECT COUNT(*) FROM quant.instruments WHERE symbol LIKE 'PITR-TEST-%';
```

Expected output:
```
 count
-------
     0
(1 row)
```

---

## Exercise 6: Insert 500 test rows

Still as **postgres** in the psql session on **pg-primary**:

```sql
INSERT INTO quant.instruments (symbol, name, asset_class)
SELECT
  'PITR-TEST-' || LPAD(gs::text, 4, '0'),
  'PITR Test Instrument ' || gs,
  'equity'
FROM generate_series(1, 500) gs;
```

Expected output:
```
INSERT 0 500
```

Confirm the rows are there:

```sql
SELECT COUNT(*) FROM quant.instruments WHERE symbol LIKE 'PITR-TEST-%';
```

Expected output:
```
 count
-------
   500
(1 row)
```

---

## Exercise 7: Record the timestamp AFTER the insert (your recovery target)

Still as **postgres** in the psql session on **pg-primary**:

This timestamp is the moment you want to recover TO - after the good insert but before the bad delete:

```sql
SELECT NOW() AS recovery_target_time, pg_current_wal_lsn() AS lsn_after_insert;
```

Expected output (yours will differ):
```
      recovery_target_time       |  lsn_after_insert
---------------------------------+-------------------
 2026-06-15 14:47:32.456789+00   | 8/31A00C0
(1 row)
```

Write down the `recovery_target_time` value exactly. You will use this as the `--target` for PITR.

---

## Exercise 8: Simulate a bad delete

Still as **postgres** in the psql session on **pg-primary**:

Wait at least 5 seconds after recording the recovery_target_time, then run the "accidental" delete:

```sql
DELETE FROM quant.instruments WHERE symbol LIKE 'PITR-TEST-%';
```

Expected output:
```
DELETE 500
```

Confirm the data is gone:

```sql
SELECT COUNT(*) FROM quant.instruments WHERE symbol LIKE 'PITR-TEST-%';
```

Expected output:
```
 count
-------
     0
(1 row)
```

Exit psql:

```sql
\q
```

---

## Exercise 9: Force a WAL switch to ensure the delete is archived

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT pg_switch_wal();"
```

Expected output (yours will differ):
```
 pg_switch_wal
---------------
 8/32000000
(1 row)
```

This ensures the WAL segment containing the delete is archived before you attempt recovery.

Exit the postgres shell:

```bash
exit
```

---

## Exercise 10: SSH into the replica for the restore

On your local machine, open a second terminal:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

On **pg-replica**, as **ec2-user**:

Stop the replica PostgreSQL instance before restoring:

```bash
sudo systemctl stop postgresql-17
```

Verify it is stopped:

```bash
sudo systemctl status postgresql-17
```

Expected output (yours will differ):
```
● postgresql-17.service - ...
     Loaded: loaded ...
     Active: inactive (dead) ...
```

---

## Exercise 11: Clear the replica data directory

On **pg-replica**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica** - back up the existing data directory first:

```bash
mv /opt/pgsql/data /opt/pgsql/data.bak.$(date +%Y%m%d%H%M%S)
```

Create a fresh empty data directory:

```bash
mkdir -p /opt/pgsql/data
chmod 700 /opt/pgsql/data
```

---

## Exercise 12: Run pgBackRest restore with PITR target

As **postgres** on **pg-replica** - substitute the recovery_target_time you recorded in Exercise 7:

```bash
/usr/pgsql-17/bin/pgbackrest --stanza=voleon-lab \
  --type=time \
  --target="2026-06-15 14:47:32.456789+00" \
  --target-action=promote \
  --pg1-path=/opt/pgsql/data \
  restore
```

Replace the `--target` value with YOUR exact timestamp from Exercise 7.

Expected output (yours will differ):
```
P00   INFO: restore command begin 2.49: ...
P00   INFO: restore backup set 20260615-144500F
P00   INFO: write updated /opt/pgsql/data/postgresql.auto.conf
P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
P00   INFO: restore command end: completed successfully
```

---

## Exercise 13: Start PostgreSQL and let it apply WAL to the target time

Exit the postgres shell:

```bash
exit
```

On **pg-replica**, as **ec2-user**:

```bash
sudo systemctl start postgresql-17
```

Watch the PostgreSQL log to see WAL recovery in progress:

```bash
sudo tail -f /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

You will see lines like:
```
LOG:  starting point-in-time recovery to 2026-06-15 14:47:32.456789+00
LOG:  restored log file "..." from archive
...
LOG:  recovery stopping before commit of transaction ...
LOG:  pausing at the end of recovery
```

Once you see "pausing at the end of recovery" or "database system is ready to accept read only connections", press Ctrl+C to stop the tail.

---

## Exercise 14: Verify the restored data

On **pg-replica**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Check that the 500 PITR-TEST rows are present (the insert happened before the target time):

```sql
SELECT COUNT(*) FROM quant.instruments WHERE symbol LIKE 'PITR-TEST-%';
```

Expected output:
```
 count
-------
   500
(1 row)
```

Check a sample of the rows:

```sql
SELECT symbol, name FROM quant.instruments
WHERE symbol LIKE 'PITR-TEST-%'
ORDER BY symbol
LIMIT 5;
```

Expected output (yours will differ):
```
     symbol     |          name
----------------+------------------------
 PITR-TEST-0001 | PITR Test Instrument 1
 PITR-TEST-0002 | PITR Test Instrument 2
 PITR-TEST-0003 | PITR Test Instrument 3
 PITR-TEST-0004 | PITR Test Instrument 4
 PITR-TEST-0005 | PITR Test Instrument 5
(5 rows)
```

The data that was deleted on the primary is present here because the recovery stopped before the delete.

---

## Exercise 15: Clean up test data and restore replica to standby

Exit psql:

```sql
\q
```

To clean up the PITR-TEST data and return the replica to normal standby mode, you need to delete the test rows on the primary (they are already gone there) and rebuild the replica from a fresh base backup.

As **postgres** on **pg-replica** - delete the test rows on the restored instance:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "DELETE FROM quant.instruments WHERE symbol LIKE 'PITR-TEST-%';"
```

Exit the postgres shell:

```bash
exit
```

On **pg-replica**, as **ec2-user** - stop the restored instance and rebuild the replica from primary:

```bash
sudo systemctl stop postgresql-17
```

```bash
sudo su - postgres
```

As **postgres** on **pg-replica** - remove the restored data directory and run a fresh pg_basebackup:

```bash
rm -rf /opt/pgsql/data
```

```bash
/usr/pgsql-17/bin/pg_basebackup \
  -h 172.31.19.86 \
  -U replicator \
  -D /opt/pgsql/data \
  -P \
  -R \
  --wal-method=stream
```

When prompted for password: `repl_voleon_2026`

Expected output (yours will differ):
```
24318/24318 kB (100%), 1/1 tablespace
```

Exit the postgres shell:

```bash
exit
```

Start the replica back up:

```bash
sudo systemctl start postgresql-17
```

---

## Exercise 16: Verify pgBackRest backup chain

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres /usr/pgsql-17/bin/pgbackrest --stanza=voleon-lab info
```

Expected output (yours will differ):
```
stanza: voleon-lab
    status: ok

    db (current)
        wal archive min/max (17): 000000010000000000000001/000000010000000800000062

    full backup: 20260615-144500F
        timestamp start/stop: 2026-06-15 14:45:00 / 2026-06-15 14:46:20
        wal start/stop: 000000010000000800000002 / 000000010000000800000003
        database size = 1.4GB, database backup size = 1.4GB
        ...
```

You should see the full backup you took in Exercise 3, along with a continuous WAL archive range that covers your recovery target time.

---

## Summary

In this exercise you:
- Took a pgBackRest full backup manually
- Recorded an LSN and timestamp before making any changes
- Inserted 500 PITR-TEST rows and recorded the post-insert timestamp as the recovery target
- Simulated a bad delete and confirmed the data was gone
- Forced a WAL switch to archive the change
- Stopped the replica, cleared its data directory, and ran a PITR restore to just after the insert
- Verified the 500 rows were recovered on the restored instance
- Rebuilt the replica from a fresh base backup and restored it to standby mode
- Confirmed the pgBackRest backup chain is intact
