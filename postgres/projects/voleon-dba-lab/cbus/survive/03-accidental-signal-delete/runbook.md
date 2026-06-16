# Runbook 03: Accidental Signal DELETE

## Alert
> "Data pipeline team reports 500K+ trading signals are missing from quant.signals. A DELETE
> statement was run without a WHERE clause on the 2024-06 partition."

Someone ran a DELETE with no WHERE clause (or a DELETE on the wrong table/partition). The
`quant.signals` table has lost a full month of trading signal data. The 2024-06 partition is now
empty. Downstream models that depend on this data are returning errors or producing incorrect
results.

This is a data integrity incident. Every minute spent delaying the restore widens the window of
writes that may conflict with the recovery.

---

## Layer 1 - Junior DBA: Assess and Contain

**Goal:** Confirm the scope of the damage, stop any new writes to the affected partition to
preserve the backup recovery window, and document what happened.

### Step 1: SSH into the primary server

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

### Step 2: Count the rows in the affected partition

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT count(*) FROM quant.signals WHERE generated_at >= '2024-06-01' AND generated_at < '2024-07-01';"
```

Expected output after a full delete:

```
 count
-------
     0
(1 row)
```

Compare against historical counts. If the June partition normally has 500K+ rows and is now 0,
the delete is confirmed.

### Step 3: Check the other partitions to scope the damage

Make sure the delete was limited to the June partition and did not cascade to other months.

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT date_trunc('month', generated_at) AS month, count(*) FROM quant.signals GROUP BY 1 ORDER BY 1 DESC LIMIT 12;"
```

Expected output (June shows 0, others intact):

```
        month         |  count
----------------------+---------
 2024-08-01 00:00:00  | 612043
 2024-07-01 00:00:00  | 589211
 2024-06-01 00:00:00  |       0
 2024-05-01 00:00:00  | 601887
...
```

Note the exact months affected and their counts. Exit:

```bash
exit
```

### Step 4: Check for any replication delay - the replica may have it too

Once a DELETE commits on the primary, it replicates to the replica almost immediately. Do not
assume the replica still has the data.

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

On **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT count(*) FROM quant.signals WHERE generated_at >= '2024-06-01' AND generated_at < '2024-07-01';"
```

If the replica also shows 0, you cannot recover from the replica. Recovery must come from pgBackRest.

Exit:

```bash
exit
```

### Step 5: Stop writes to the signals table immediately

To prevent new rows from being written into the June partition during recovery planning, temporarily
revoke INSERT on the signals table. This is a short-term hold, not permanent.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "REVOKE INSERT ON quant.signals FROM quant_pipeline;"
```

Confirm the revoke:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT grantee, privilege_type FROM information_schema.role_table_grants WHERE table_schema = 'quant' AND table_name = 'signals' AND grantee = 'quant_pipeline';"
```

INSERT should no longer appear in the output.

Exit:

```bash
exit
```

### Step 6: Notify the team

Post to the incident channel:
- Affected data: quant.signals, 2024-06 partition, approximately 500K rows missing
- Replica is also affected (DELETE already replicated)
- New writes to signals have been paused pending recovery
- Recovery will require pgBackRest PITR restore
- Estimated recovery time: 30-90 minutes

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

**Goal:** Use pgBackRest to perform a Point-in-Time Recovery to just before the DELETE occurred,
extract the missing rows, and re-insert them into the live database.

### Step 7: Find the approximate time of the DELETE

Check the PostgreSQL logs for the DELETE statement.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo grep -i "DELETE" /var/lib/pgsql/17/data/log/postgresql-$(date +%a).log | grep "quant.signals" | tail -20
```

Also search yesterday's log if the delete happened overnight:

```bash
sudo grep -i "DELETE" /var/lib/pgsql/17/data/log/postgresql-$(date -d yesterday +%a).log | grep "quant.signals" | tail -20
```

Expected output (example):

```
2024-08-14 09:23:11 UTC [18432]: quant_pipeline@quantdb LOG: statement: DELETE FROM quant.signals_2024_06;
```

Note the exact timestamp: `2024-08-14 09:23:11 UTC`. Your PITR target will be 1 minute before
this: `2024-08-14 09:22:00 UTC`.

### Step 8: Check available pgBackRest backups

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/bin/pgbackrest --stanza=voleon-lab info
```

Expected output (truncated):

```
stanza: voleon-lab
    status: ok
    cipher: none

    db (current)
        wal archive min/max (17): 000000010000000000000001/0000000100000003000000FF

        full backup: 20240814-020000F
            timestamp start/stop: 2024-08-14 02:00:00 / 2024-08-14 02:18:43
            wal start/stop: 000000010000000200000041 / 000000010000000200000082
            ...
```

Confirm there is a backup that predates your DELETE timestamp. If the most recent full backup is
from `2024-08-14 02:00:00` and the DELETE was at `09:23:11`, you can recover to `09:22:00`.

Exit:

```bash
exit
```

### Step 9: Restore to a separate directory for surgical row extraction

Rather than restoring the entire primary (which would cause extended downtime), restore to a
temporary directory and extract only the missing rows.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

First, create a temporary restore directory:

```bash
sudo mkdir -p /var/lib/pgsql/pitr_restore
sudo chown postgres:postgres /var/lib/pgsql/pitr_restore
```

Switch to the postgres user:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**, run the PITR restore into the temporary directory:

```bash
/usr/bin/pgbackrest --stanza=voleon-lab \
  --type=time \
  --target="2024-08-14 09:22:00+00" \
  --target-action=promote \
  --pg1-path=/var/lib/pgsql/pitr_restore \
  restore
```

This restore can take 10-30 minutes depending on backup size. Expected output at the end:

```
INFO: restore command end: completed successfully
```

Exit:

```bash
exit
```

### Step 10: Start a temporary PostgreSQL instance on the restored data

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**, start a temporary instance on a different port (5433):

```bash
/usr/pgsql-17/bin/pg_ctl start -D /var/lib/pgsql/pitr_restore -o "-p 5433"
```

Expected output:

```
waiting for server to start....
server started
```

Verify the temporary instance is accepting connections:

```bash
/usr/pgsql-17/bin/pg_isready -h 127.0.0.1 -p 5433
```

Expected output:

```
127.0.0.1:5433 - accepting connections
```

### Step 11: Extract the deleted rows from the PITR instance

As **postgres** on **pg-primary**, dump the missing June signals from the temporary instance:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 5433 -d quantdb \
  -c "\COPY (SELECT * FROM quant.signals WHERE generated_at >= '2024-06-01' AND generated_at < '2024-07-01') TO '/var/lib/pgsql/signals_june_recovery.csv' WITH CSV HEADER"
```

Expected output:

```
COPY 512847
```

Confirm the file exists and has data:

```bash
wc -l /var/lib/pgsql/signals_june_recovery.csv
```

Expected output:

```
512848 /var/lib/pgsql/signals_june_recovery.csv
```

(512847 rows + 1 header line)

### Step 12: Stop the temporary instance

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/pg_ctl stop -D /var/lib/pgsql/pitr_restore
```

Exit:

```bash
exit
```

### Step 13: Re-insert the recovered rows into the live database

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**, first restore the INSERT privilege:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "GRANT INSERT ON quant.signals TO quant_pipeline;"
```

Load the recovered rows. Use a staging table to avoid primary key conflicts:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "CREATE TEMP TABLE signals_recovery (LIKE quant.signals);"
```

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "\COPY signals_recovery FROM '/var/lib/pgsql/signals_june_recovery.csv' WITH CSV HEADER"
```

Insert into quant.signals, skipping any rows that may have been re-inserted by the application
since the incident began:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "INSERT INTO quant.signals SELECT * FROM signals_recovery ON CONFLICT (id) DO NOTHING;"
```

Expected output:

```
INSERT 0 512847
```

Verify the count:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT count(*) FROM quant.signals WHERE generated_at >= '2024-06-01' AND generated_at < '2024-07-01';"
```

Expected output:

```
 count
--------
 512847
(1 row)
```

Exit:

```bash
exit
```

### Step 14: Clean up the temporary restore directory

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo rm -rf /var/lib/pgsql/pitr_restore
sudo rm -f /var/lib/pgsql/signals_june_recovery.csv
```

---

## Layer 3 - Senior DBA: Root Cause and Prevent

**Goal:** Identify who ran the DELETE, close the permission gap that allowed it, and add structural
safeguards to prevent mass deletes in the future.

### Step 15: Identify who ran the DELETE from PostgreSQL logs

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo grep -B5 "DELETE FROM quant.signals" /var/lib/pgsql/17/data/log/postgresql-$(date +%a).log
```

The log lines before the DELETE will show the client IP, database role, and connection context.
Example:

```
2024-08-14 09:23:09 UTC [18432]: [1-1] user=quant_pipeline,db=quantdb,app=psql,client=172.31.21.45
2024-08-14 09:23:11 UTC [18432]: LOG: statement: DELETE FROM quant.signals_2024_06;
```

The DELETE came from `quant_pipeline` role, connecting from the container server (172.31.21.45),
using `psql` as the application name. This indicates a human ran this manually, not an automated
job.

### Step 16: Revoke DELETE privilege from quant_pipeline

The `quant_pipeline` role has no business deleting signal history. Signals are write-once.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "REVOKE DELETE ON quant.signals FROM quant_pipeline;"
```

Also revoke from any future partitions by altering the default privileges:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "ALTER DEFAULT PRIVILEGES IN SCHEMA quant REVOKE DELETE ON TABLES FROM quant_pipeline;"
```

Confirm:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT grantee, privilege_type FROM information_schema.role_table_grants WHERE table_schema = 'quant' AND table_name = 'signals';"
```

`DELETE` should not appear for `quant_pipeline`. Exit:

```bash
exit
```

### Step 17: Add a trigger to block mass deletes as a defense-in-depth measure

Even for roles that do have DELETE, block any DELETE that would remove more than 1000 rows at once
without an explicit override.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Inside psql, create the safeguard trigger function:

```sql
CREATE OR REPLACE FUNCTION quant.prevent_mass_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT count(*) FROM quant.signals WHERE ctid = ANY(ARRAY(
      SELECT ctid FROM quant.signals LIMIT 1001))) > 1000 THEN
    RAISE EXCEPTION 'Mass DELETE blocked: use quant.allow_mass_delete() to override';
  END IF;
  RETURN OLD;
END;
$$;
```

Note: A simpler and more reliable approach for partitioned tables is a statement-level trigger.
Use this instead:

```sql
CREATE OR REPLACE FUNCTION quant.prevent_mass_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Bulk DELETE on quant.signals is not permitted. Contact the DBA team.';
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER prevent_mass_signal_delete
  AFTER DELETE ON quant.signals
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION quant.prevent_mass_delete();
```

Exit psql:

```sql
\q
```

Exit the postgres user:

```bash
exit
```

### Step 18: Review backup RPO - is daily backup sufficient?

With a daily backup taken at 02:00 UTC and the DELETE at 09:23 UTC, the PITR window covered 7+
hours of WAL. This worked because WAL archiving was continuous.

Confirm WAL archiving is active and the archive is not lagging:

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -c "SELECT name, setting FROM pg_settings WHERE name IN ('archive_mode', 'archive_command', 'wal_level');"
```

Expected output:

```
      name       |                     setting
-----------------+--------------------------------------------------
 archive_command | pgbackrest --stanza=voleon-lab archive-push %p
 archive_mode    | on
 wal_level       | replica
```

Exit:

```bash
exit
```

If archive_mode is off, you cannot do PITR at all - only restore to the last backup. In that case,
enable archiving immediately.

### Step 19: Implement table-level audit logging for DDL and DML on signals

Add `log_statement` level detail for connections from the `quant_pipeline` role so any future
mass operations are immediately visible in the logs.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "ALTER ROLE quant_pipeline SET log_statement = 'mod';"
```

This causes all INSERT, UPDATE, DELETE, and TRUNCATE from `quant_pipeline` to be logged regardless
of the global `log_statement` setting. Exit:

```bash
exit
```

---

## Summary

### Root Cause
A `quant_pipeline` database role user (connecting via psql from the container server 172.31.21.45)
ran `DELETE FROM quant.signals_2024_06` without a WHERE clause, removing all 512,847 rows from the
June 2024 partition. The DELETE replicated to the replica within seconds.

### Resolution
1. Confirmed scope: June partition emptied, other partitions intact
2. Paused writes to signals to preserve recovery window
3. Used pgBackRest PITR restore to a temporary directory to recover data to just before the DELETE
4. Extracted the deleted rows via COPY to CSV
5. Re-inserted 512,847 rows into the live database with ON CONFLICT DO NOTHING
6. Confirmed row counts match pre-incident baseline

### Prevention
- Revoked DELETE on `quant.signals` from `quant_pipeline` (signals are write-once)
- Added ALTER DEFAULT PRIVILEGES to cover future partitions
- Added a constraint trigger to block bulk deletes as a defense-in-depth layer
- Enabled `log_statement = 'mod'` for the `quant_pipeline` role for audit visibility
- Confirmed WAL archiving is active (required for PITR to work)
- Recommended quarterly PITR drills to validate recovery procedures before a real incident
