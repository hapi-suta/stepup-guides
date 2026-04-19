# Runbook 03 - WAL Corruption on Standby

**Severity:** High - Standby replication is broken, no HA protection
**Time to resolve:** 5-15 minutes

---

## Fix Path

### Step 1: Check standby status

SSH to [NODE2] and check if PostgreSQL is running:

```bash
sudo systemctl status postgresql
sudo -u postgres pg_isready -p 5432
```

It may be crashed or running but stuck (not replaying WAL).

### Step 2: Check the standby logs

```bash
sudo tail -100 /var/log/postgresql/postgresql-16-main.log
```

Look for messages like:
- `FATAL: could not open file "pg_wal/00000001000000XX000000YY": No such file or directory`
- `LOG: invalid record length`

This confirms a WAL segment is missing or corrupt.

### Step 3: Check replication status from the primary

On [NODE1]:

```sql
SELECT * FROM pg_stat_replication;
```

If the standby is disconnected, this will return zero rows or show the connection as `startup` rather than `streaming`.

### Step 4 (Option A): Restore the renamed file

If you know the file was renamed (not truly corrupted), restore it:

```bash
# On [NODE2], check for .corrupt files
ls -la /var/lib/postgresql/16/main/pg_wal/*.corrupt

# Rename it back
sudo -u postgres mv /var/lib/postgresql/16/main/pg_wal/FILENAME.corrupt \
  /var/lib/postgresql/16/main/pg_wal/FILENAME
```

Then restart PostgreSQL:

```bash
sudo systemctl restart postgresql
```

### Step 4 (Option B): Let the standby re-fetch from primary

If the WAL segment still exists on the primary (thanks to the replication slot), simply restart the standby:

```bash
sudo systemctl restart postgresql
```

The standby's walreceiver will reconnect and request the missing WAL from the primary. The replication slot `standby_slot` ensures the primary has not recycled it.

### Step 4 (Option C): Full rebuild with pg_basebackup

If the slot cannot recover the missing WAL (e.g., the gap is too large or the primary's WAL was recycled):

```bash
# On [NODE2] - stop postgres and wipe the data directory
sudo systemctl stop postgresql
sudo -u postgres rm -rf /var/lib/postgresql/16/main/*

# Rebuild from primary
sudo -u postgres pg_basebackup \
  -h [NODE1] -p 5432 -U replicator \
  -D /var/lib/postgresql/16/main \
  -S standby_slot -R -Xs -P

sudo systemctl start postgresql
```

The `-R` flag writes standby.signal and primary_conninfo automatically.

### Step 5: Verify replication resumed

On the primary:

```sql
SELECT state, sent_lsn, replay_lsn
FROM pg_stat_replication;
```

Confirm `state = 'streaming'` and the lag is dropping.

### Step 6: Clean up corrupt file artifacts

On [NODE2], remove any leftover `.corrupt` files:

```bash
sudo -u postgres rm -f /var/lib/postgresql/16/main/pg_wal/*.corrupt
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
