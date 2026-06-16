# Runbook 05: WAL Disk Full

## Alert
> CRITICAL: PostgreSQL primary cannot write WAL - disk full on pg_wal directory. All writes are blocked.
> Log message: `PANIC: could not write to file "pg_wal/000000010000000X": No space left on device`
> All application writes to quantdb are failing. Replication to pg-replica has stalled.

---

## Lab Environment

| Node | Public IP | Private IP | Role |
|------|-----------|------------|------|
| pg-primary | 3.90.199.62 | 172.31.19.86 | Primary |
| pg-replica | 3.91.32.84 | 172.31.22.69 | Replica |
| pg-ops | 54.209.143.137 | 172.31.26.19 | Ops/Monitoring |

SSH command: `ssh -i ~/.ssh/id_ed25519 ec2-user@<IP>`

Database: `quantdb` - schemas: `quant`, `ops`

---

## Layer 1 - Junior DBA: Assess and Contain

Your job at this layer is to confirm what is happening, document what you see, and stop the bleeding. Do not try to fix the root cause yet.

### Step 1 - SSH into the primary

From your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

### Step 2 - Check overall disk usage on the primary

On **pg-primary**, as **ec2-user**:

```bash
df -h
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
devtmpfs        4.0M     0  4.0M   0% /dev
/dev/xvda1       20G   19G  100M  99% /
tmpfs           7.7G     0  7.7G   0% /dev/shm
...
```

You are looking for any filesystem at 99% or 100% usage. The `/` or a dedicated mount like `/var/lib/pgsql` is the likely culprit.

### Step 3 - Check the size of the WAL directory specifically

On **pg-primary**, as **ec2-user**:

```bash
sudo du -sh /var/lib/pgsql/17/data/pg_wal/
```

Expected output (yours will differ):

```
4.2G    /var/lib/pgsql/17/data/pg_wal/
```

A healthy WAL directory is typically 1-2x the value of `wal_segment_size * max_wal_size`. If it is several gigabytes larger than expected, WAL is accumulating.

### Step 4 - Count how many WAL files are present

On **pg-primary**, as **ec2-user**:

```bash
sudo ls -la /var/lib/pgsql/17/data/pg_wal/ | wc -l
```

Expected output (yours will differ):

```
312
```

A normal count is roughly 10-100 files. Hundreds of files means WAL is not being recycled.

### Step 5 - Check PostgreSQL is still running (or has crashed)

On **pg-primary**, as **ec2-user**:

```bash
systemctl status postgresql-17
```

Expected output (yours will differ):

```
* postgresql-17.service - PostgreSQL 17 Database Server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled)
     Active: active (running) since ...
```

If PostgreSQL has crashed (Active: failed), note this and escalate to Layer 2 immediately. Do not attempt to restart without understanding why it crashed.

### Step 6 - Check the PostgreSQL logs for the exact error

On **pg-primary**, as **ec2-user**:

```bash
sudo ls -lt /var/lib/pgsql/17/data/log/
```

This lists log files newest first. Note the most recent filename, then read it:

```bash
sudo tail -50 /var/lib/pgsql/17/data/log/postgresql-<date>.log
```

Expected output (yours will differ):

```
2024-01-15 14:32:01 UTC [1234]: PANIC:  could not write to file "pg_wal/000000010000000A00000001": No space left on device
2024-01-15 14:32:01 UTC [1234]: LOG:  database system is shut down
```

Copy the exact error message. You will need it for the Layer 2 investigator.

### Step 7 - Do NOT delete any WAL files manually

WAL files are sacred. Deleting the wrong one will corrupt the database. Your job is to document, not delete. Hand off to Layer 2.

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

You have confirmed the disk is full and WAL is accumulating. Now find out why WAL is not being recycled and fix it.

### Step 1 - SSH into the primary

From your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

### Step 2 - Switch to the postgres user

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

### Step 3 - Connect to quantdb

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

### Step 4 - Check for inactive replication slots

On **pg-primary**, inside psql:

```sql
SELECT slot_name, slot_type, active, restart_lsn, pg_current_wal_lsn(),
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained
FROM pg_replication_slots;
```

Expected output (yours will differ):

```
    slot_name    | slot_type | active | restart_lsn | pg_current_wal_lsn | wal_retained
-----------------+-----------+--------+-------------+--------------------+--------------
 replica_slot    | physical  | f      | 0/A1000000  | 0/B8000000         | 4096 MB
(1 row)
```

If `active = f` (false), that slot is not being consumed. PostgreSQL must keep all WAL from `restart_lsn` forward. This is the most common cause of WAL accumulation.

### Step 5 - Check if archiving is backed up

On **pg-primary**, inside psql:

```sql
SELECT archived_count, failed_count, last_archived_wal, last_failed_wal, last_failed_time
FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 archived_count | failed_count | last_archived_wal | last_failed_wal | last_failed_time
----------------+--------------+-------------------+-----------------+------------------
          10234 |          847 | 0/A1000000        | 0/A1000001      | 2024-01-15 12:01
```

A high `failed_count` means your archive command is broken. PostgreSQL will not recycle WAL it cannot archive.

### Step 6 - Check current WAL settings

On **pg-primary**, inside psql:

```sql
SHOW wal_keep_size;
SHOW max_wal_size;
SHOW archive_mode;
SHOW archive_command;
```

Note the values. If `archive_mode = on` but `failed_count` is high, archiving is the root cause. If there is a slot with `active = f`, the slot is the root cause.

### Step 7 - Drop the inactive replication slot (if confirmed stale)

Only drop a slot if you are certain the consumer (replica or logical client) is permanently gone. Dropping a slot for an active replica will break replication.

Verify the replica is actually down or decommissioned:

```bash
exit
```

Exit psql first, then exit postgres:

```bash
exit
```

On **pg-primary**, as **ec2-user**, check if the replica is reachable:

```bash
ping -c 3 172.31.22.69
```

If the replica is unreachable and confirmed decommissioned, return to psql and drop the slot:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
SELECT pg_drop_replication_slot('replica_slot');
```

Expected output:

```
 pg_drop_replication_slot
--------------------------

(1 row)
```

### Step 8 - Force a checkpoint to recycle WAL

On **pg-primary**, inside psql:

```sql
CHECKPOINT;
```

Expected output:

```
CHECKPOINT
```

Wait 30 seconds, then check WAL directory size again:

```bash
exit
```

```bash
exit
```

On **pg-primary**, as **ec2-user**:

```bash
sudo du -sh /var/lib/pgsql/17/data/pg_wal/
```

The size should be decreasing as PostgreSQL recycles old WAL segments.

### Step 9 - If disk is still critically full, create temporary space

If PostgreSQL has crashed and cannot start due to no disk space, you need to free space immediately. Check for large temporary files first:

On **pg-primary**, as **ec2-user**:

```bash
sudo find /var/lib/pgsql/17/data/base -name "pgsql_tmp*" -size +100M
```

If any exist, those are safe to delete:

```bash
sudo rm /var/lib/pgsql/17/data/base/pgsql_tmp*
```

Then attempt to start PostgreSQL:

```bash
systemctl start postgresql-17
```

### Step 10 - Verify replication has reconnected after fix

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag
FROM pg_stat_replication;
```

Expected output (yours will differ):

```
  client_addr  | state  | sent_lsn  | write_lsn | flush_lsn | replay_lsn |  lag
---------------+--------+-----------+-----------+-----------+------------+-------
 172.31.22.69  | streaming | 0/B80000A0 | 0/B80000A0 | 0/B80000A0 | 0/B80000A0 | 0 bytes
(1 row)
```

Lag should be close to 0 bytes once replication reconnects.

```bash
exit
```

```bash
exit
```

---

## Layer 3 - Senior DBA: Root Cause and Prevent

You have stopped the bleeding. Now implement safeguards so this never happens again.

### Step 1 - Set max_slot_wal_keep_size to cap WAL held by slots

Without this setting, a single stale slot can hold unlimited WAL. This is the most impactful change.

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
ALTER SYSTEM SET max_slot_wal_keep_size = '2GB';
SELECT pg_reload_conf();
SHOW max_slot_wal_keep_size;
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)

 max_slot_wal_keep_size
------------------------
 2GB
(1 row)
```

This causes PostgreSQL to invalidate a slot rather than fill the disk. The slot consumer will need to re-sync, but the primary stays alive.

### Step 2 - Set wal_keep_size to a reasonable value

On **pg-primary**, inside psql:

```sql
ALTER SYSTEM SET wal_keep_size = '512MB';
SELECT pg_reload_conf();
```

512MB is enough for a brief replica disconnect to catch up without keeping excessive WAL on disk.

### Step 3 - Add disk space monitoring to Prometheus

Exit psql and postgres:

```bash
exit
```

```bash
exit
```

SSH to pg-ops:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

Check that node_exporter is scraping disk metrics from the primary:

```bash
curl -s http://172.31.19.86:9100/metrics | grep node_filesystem_avail_bytes | grep xvda
```

Expected output (yours will differ):

```
node_filesystem_avail_bytes{device="/dev/xvda1",fstype="xfs",mountpoint="/"} 2.14748e+08
```

If you see output, Prometheus is collecting disk metrics. Now check that an alert rule exists:

```bash
sudo grep -r "disk" /etc/prometheus/rules/
```

If no disk alert rule exists, create one:

```bash
sudo vi /etc/prometheus/rules/disk_alerts.yml
```

Add the following content:

```yaml
groups:
  - name: disk_alerts
    rules:
      - alert: DiskSpaceWarning
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space below 20% on {{ $labels.instance }}"

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Disk space below 10% on {{ $labels.instance }} - WAL disk full risk"
```

Reload Prometheus:

```bash
systemctl reload prometheus
```

### Step 4 - Implement a dedicated mount point for pg_wal (best practice recommendation)

A separate EBS volume for pg_wal means a WAL accumulation event cannot fill the OS or data filesystem. This is a recommendation to document for the next maintenance window, not an emergency change.

Document the recommended architecture:

- `/dev/xvda` - OS and PostgreSQL binaries (20GB)
- `/dev/xvdb` - PostgreSQL data directory `/var/lib/pgsql/17/data` (100GB)
- `/dev/xvdc` - WAL directory `/var/lib/pgsql/17/data/pg_wal` (50GB)

To move pg_wal to a new mount during a maintenance window:
1. Stop PostgreSQL
2. Attach new EBS volume, format and mount to `/mnt/pgwal`
3. `mv /var/lib/pgsql/17/data/pg_wal /mnt/pgwal/pg_wal`
4. `ln -s /mnt/pgwal/pg_wal /var/lib/pgsql/17/data/pg_wal`
5. Start PostgreSQL

### Step 5 - Review and fix archive_command reliability

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SHOW archive_command;"
```

If the archive command is a script, test it manually with a known WAL file:

```bash
ls /var/lib/pgsql/17/data/pg_wal/ | head -1
```

Note that filename, then test the archive command manually replacing `%f` and `%p` with actual values. Confirm it exits 0.

```bash
exit
```

```bash
exit
```

---

## Summary

### Root Cause

An inactive replication slot (`replica_slot`) was retaining WAL from LSN `0/A1000000` while the primary advanced to `0/B8000000`, accumulating 4GB of WAL. The replica connected to that slot had been decommissioned without dropping the slot. Without `max_slot_wal_keep_size`, PostgreSQL had no safeguard against unlimited accumulation.

### Resolution

1. Confirmed inactive replication slot via `pg_replication_slots`
2. Verified the slot consumer (replica) was permanently gone
3. Dropped the stale slot with `pg_drop_replication_slot()`
4. Forced a checkpoint to recycle WAL
5. Confirmed disk space recovered and replication reconnected

### Prevention

- Set `max_slot_wal_keep_size = '2GB'` to cap WAL held by any single slot
- Set `wal_keep_size = '512MB'` to bound baseline WAL retention
- Add Prometheus disk alert rules firing at 20% and 10% free space
- Add a dedicated EBS volume for `pg_wal` during next maintenance window
- Audit replication slots after any replica decommission - always drop the slot explicitly
