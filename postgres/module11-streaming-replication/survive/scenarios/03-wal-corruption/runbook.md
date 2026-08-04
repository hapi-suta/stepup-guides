# Runbook 03 - WAL Corruption on Standby

**Severity:** High - Standby replication is broken, no HA protection
**Time to resolve:** 5-15 minutes

---

## Fix Path

### Step 1: Check standby status

SSH to [NODE2] and check if PostgreSQL is running:

```bash
sudo systemctl status postgresql-16
```

Check if PostgreSQL is accepting connections. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pg_isready -p 5432
```

```bash
exit
```

It may be crashed or running but stuck (not replaying WAL).

### Step 2: Check the standby logs

```bash
sudo tail -100 /opt/pgsql/data/log/postgresql-*.log
```

Look for messages like:
- `FATAL: could not open file "pg_wal/00000001000000XX000000YY": No such file or directory`
- `LOG: invalid record length`

This confirms a WAL segment is missing or corrupt.

Expected output (yours will differ):
```
FATAL:  could not open file "pg_wal/000000010000000000000005": No such file or directory
LOG:  startup process (PID 1234) exited with exit code 1
...
```

### Step 3: Check replication status from the primary

On [NODE1]:

```sql
SELECT * FROM pg_stat_replication;
```

If the standby is disconnected, this will return zero rows or show the connection as `startup` rather than `streaming`.

### Step 4 (Option A): Restore the renamed file

If you know the file was renamed (not truly corrupted), restore it:

On [NODE2], switch to the postgres user:

```bash
sudo -iu postgres
```

Check for .corrupt files:

```bash
ls -la /opt/pgsql/data/pg_wal/*.corrupt
```

Rename it back (replace FILENAME with the actual filename from the listing above):

```bash
mv /opt/pgsql/data/pg_wal/FILENAME.corrupt /opt/pgsql/data/pg_wal/FILENAME
```

```bash
exit
```

Then restart PostgreSQL:

```bash
sudo systemctl restart postgresql-16
```

### Step 4 (Option B): Let the standby re-fetch from primary

If the WAL segment still exists on the primary (thanks to the replication slot), simply restart the standby:

```bash
sudo systemctl restart postgresql-16
```

The standby's walreceiver will reconnect and request the missing WAL from the primary. The replication slot `standby_slot` ensures the primary has not recycled it.

### Step 4 (Option C): Full rebuild with pg_basebackup

If the slot cannot recover the missing WAL (e.g., the gap is too large or the primary's WAL was recycled):

On [NODE2], stop PostgreSQL:

```bash
sudo systemctl stop postgresql-16
```

Switch to the postgres user and wipe the data directory:

```bash
sudo -iu postgres
```

```bash
rm -rf /opt/pgsql/data/*
```

Rebuild from primary. `-R` writes standby.signal and primary_conninfo. `-Xs` streams WAL during backup. `-P` shows progress:

```bash
pg_basebackup \
  -h [NODE1] -p 5432 -U replicator \
  -D /opt/pgsql/data \
  -S standby_slot -R -Xs -P
```

```bash
exit
```

Start PostgreSQL:

```bash
sudo systemctl start postgresql-16
```

The `-R` flag writes standby.signal and primary_conninfo automatically.

### Step 5: Verify replication resumed

On the primary:

```sql
SELECT state, sent_lsn, replay_lsn
FROM pg_stat_replication;
```

Confirm `state = 'streaming'` and the lag is dropping.

Expected output (yours will differ):
```
   state   |  sent_lsn   | replay_lsn
-----------+-------------+-------------
 streaming | 0/7000148   | 0/7000148
```

### Step 6: Clean up corrupt file artifacts

On [NODE2], remove any leftover `.corrupt` files:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
rm -f /opt/pgsql/data/pg_wal/*.corrupt
```

```bash
exit
```

### Step 7: Verify data consistency

```sql
-- On primary
SELECT count(*) FROM employees;

-- On standby
SELECT count(*) FROM employees;
```

Counts should match once replication catches up.

---

## Key Concepts for Revision

- **WAL (Write-Ahead Log)** is PostgreSQL's crash-recovery and replication mechanism. Every change is written to WAL before being applied to data files. If a WAL segment is missing, the standby cannot advance.
- **Replication slots** are the safety net here. The slot `standby_slot` tells the primary "do not recycle WAL until I have consumed it." This is why Option B (restart and re-fetch) works - the primary still has the WAL.
- **pg_basebackup** is the nuclear option. It copies the entire data directory from the primary. Use it when the WAL gap is too large or the data directory is corrupted beyond WAL replay.
- **data_checksums**: If enabled at initdb time, PostgreSQL can detect on-disk corruption (bit rot) during reads. Without checksums, corrupt data pages may go unnoticed until a query hits them.
- **WAL archiving** (archive_mode/archive_command) provides a second copy of every WAL segment. If the primary's pg_wal and the standby both lose a segment, the archive is your last resort.
- **standby.signal** file in the data directory tells PostgreSQL to start in standby mode. Without it, the server starts as a primary. pg_basebackup with `-R` creates this automatically.

---

## Interview Discussion Points

1. **Detection speed**: How would you detect WAL corruption in production before it causes an outage? Discuss log monitoring, replication lag alerts, and pg_stat_wal_receiver on the standby.

2. **Checksums vs no checksums**: What is the performance cost of data checksums? Why do most production deployments enable them at initdb? Can you enable them after the fact (pg_checksums)?

3. **WAL archiving as insurance**: How does continuous WAL archiving (to S3, GCS, or a local NFS mount) protect against this scenario? Compare archive_command vs pg_receivewal.

4. **Slot overflow risk**: The replication slot prevents WAL recycling, but what if the standby is down for days? The primary's pg_wal directory fills up. How do you balance slot safety with disk space (max_slot_wal_keep_size)?

5. **pg_rewind vs pg_basebackup**: If only a few WAL segments diverged, pg_rewind is faster than a full base backup. When is pg_rewind appropriate and when is it not?

6. **Corruption root causes**: In production, what causes real WAL corruption? Discuss disk failures, filesystem bugs, incomplete writes during power loss, and storage controller issues.

7. **Testing corruption recovery**: How do you validate your recovery procedures before an incident? Discuss chaos engineering, DR drills, and automated failover testing in non-production environments.
