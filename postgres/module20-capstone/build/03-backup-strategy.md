# Build 03: Backup Strategy

Set up a comprehensive backup strategy using pgBackRest with full, incremental, and differential backups. Configure WAL archiving, test point-in-time recovery (PITR), and set up backup monitoring.

Run all steps on the **primary** server unless noted otherwise.

---

## Prerequisites

- Completed Build 01 (production PostgreSQL running)
- Completed Build 02 (replication working)
- `/opt/pgsql/backup` directory exists with postgres ownership

---

## 1. Install pgBackRest

### 1.1 Install the package

Run as root:

```bash
dnf install -y pgbackrest
```

Expected output (yours will differ):
```
...
Installed:
  pgbackrest-2.x...
Complete!
```

### 1.2 Verify the installation

```bash
pgbackrest version
```

Expected output:
```
pgBackRest 2.x
```

---

## 2. Configure pgBackRest

### 2.1 Create the configuration file

```bash
mkdir -p /etc/pgbackrest
```

```bash
vi /etc/pgbackrest/pgbackrest.conf
```

Add:

```ini
[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=3
repo1-retention-diff=6
repo1-retention-archive=3
repo1-retention-archive-type=full
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=Bkp_Encrypt_K3y_2026

process-max=2
compress-type=zst
compress-level=3

log-level-console=info
log-level-file=detail
log-path=/opt/pgsql/log/pgbackrest

start-fast=y
stop-auto=y
delta=y

archive-async=y
spool-path=/opt/pgsql/backup/pgbackrest-spool

[prod]
pg1-path=/opt/pgsql/data
pg1-port=5432
pg1-user=postgres
```

Save and exit (`:wq`).

Key settings:
- `repo1-path` - Where backups are stored locally.
- `repo1-retention-full=3` - Keep 3 full backups. Older ones are expired automatically.
- `repo1-retention-diff=6` - Keep 6 differential backups per full backup.
- `repo1-retention-archive=3` - Keep WAL archives for 3 full backup sets. Older WAL is cleaned up.
- `repo1-cipher-type=aes-256-cbc` - Encrypt all backups at rest. In production, use a key from a secrets manager.
- `compress-type=zst` - Use zstandard compression. Faster and better compression than gzip.
- `start-fast=y` - Issue a fast checkpoint before backup. Reduces backup time at the cost of a brief I/O spike.
- `delta=y` - Only copy files that have changed since the last backup. Speeds up incremental/differential backups significantly.
- `archive-async=y` - Archive WAL asynchronously. The archiver pushes WAL without blocking PostgreSQL.

### 2.2 Create required directories

```bash
mkdir -p /opt/pgsql/backup/pgbackrest
```

```bash
mkdir -p /opt/pgsql/backup/pgbackrest-spool
```

```bash
mkdir -p /opt/pgsql/log/pgbackrest
```

```bash
chown -R postgres:postgres /opt/pgsql/backup
```

```bash
chown -R postgres:postgres /opt/pgsql/log/pgbackrest
```

### 2.3 Set config file permissions

```bash
chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
```

```bash
chmod 640 /etc/pgbackrest/pgbackrest.conf
```

The config contains the encryption key, so restrict access.

---

## 3. Configure WAL Archiving

### 3.1 Update postgresql.conf

```bash
su - postgres
```

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find the `archive_command` line and update it:

```
archive_mode = on
archive_command = 'pgbackrest --stanza=prod archive-push %p'
```

Save and exit (`:wq`).

- `archive_command` - PostgreSQL calls this command for every completed WAL segment. pgBackRest compresses, encrypts, and stores it in the backup repository.
- `%p` - PostgreSQL substitutes the full path to the WAL file.

### 3.2 Restart PostgreSQL

```bash
exit
```

Run as root:

```bash
systemctl restart postgresql-16
```

A restart is required because `archive_mode` cannot be changed with a reload.

### 3.3 Verify PostgreSQL restarted

```bash
systemctl status postgresql-16
```

Expected output (yours will differ):
```
     Active: active (running) ...
```

---

## 4. Initialize the pgBackRest Stanza

### 4.1 Create the stanza

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod stanza-create
```

Expected output:
```
INFO: stanza-create command end: completed successfully
```

A stanza is a named backup configuration. It links the pgBackRest config to a specific PostgreSQL cluster.

### 4.2 Verify the stanza

```bash
pgbackrest --stanza=prod check
```

Expected output:
```
INFO: check command end: completed successfully
```

This verifies that:
- pgBackRest can connect to PostgreSQL
- WAL archiving is working
- The backup repository is accessible

If the check fails, review the log:

```bash
cat /opt/pgsql/log/pgbackrest/prod-check.log
```

### 4.3 Verify WAL archiving is active

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_switch_wal();"
```

This forces PostgreSQL to switch to a new WAL segment and archive the current one.

Wait a few seconds, then check:

```bash
pgbackrest --stanza=prod info
```

Expected output (yours will differ):
```
stanza: prod
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000003
```

The `wal archive min/max` line shows WAL segments are being archived.

```bash
exit
```

---

## 5. Take Backups

### 5.1 Take the first full backup

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod --type=full backup
```

This takes a full backup of the entire cluster. The first backup must always be a full backup.

Expected output (yours will differ):
```
INFO: backup command begin ...
INFO: full backup size = 50.3MB, file total = 1234
INFO: backup command end: completed successfully
```

### 5.2 Verify the full backup

```bash
pgbackrest --stanza=prod info
```

Expected output (yours will differ):
```
stanza: prod
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000005

        full backup: 20260419-120000F
            timestamp start/stop: 2026-04-19 12:00:00+00 / 2026-04-19 12:00:30+00
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 50.3MB, database backup size: 50.3MB
            repo1: backup set size: 8.1MB, backup size: 8.1MB
```

Notice `repo1: backup set size: 8.1MB` vs `database size: 50.3MB`. The compression and deduplication reduced the backup to ~16% of the original size.

### 5.3 Add some data, then take a differential backup

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) SELECT 'diff' || n || '@example.com', 'Diff User ' || n FROM generate_series(1, 500) AS n;"
```

```bash
pgbackrest --stanza=prod --type=diff backup
```

A differential backup copies only the files that changed since the last full backup. It is faster and smaller than a full backup.

Expected output (yours will differ):
```
INFO: diff backup size = 50.5MB, file total = 1234
INFO: new/changed files: 12
INFO: backup command end: completed successfully
```

### 5.4 Add more data, then take an incremental backup

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) SELECT 'incr' || n || '@example.com', 'Incr User ' || n FROM generate_series(1, 200) AS n;"
```

```bash
pgbackrest --stanza=prod --type=incr backup
```

An incremental backup copies only the files that changed since the last backup (full or differential). It is the smallest and fastest backup type.

### 5.5 View all backups

```bash
pgbackrest --stanza=prod info
```

Expected output (yours will differ):
```
        full backup: 20260419-120000F
            ...
        diff backup: 20260419-120000F_20260419-121000D
            ...
        incr backup: 20260419-120000F_20260419-121000D_20260419-122000I
            ...
```

The naming convention shows the dependency chain:
- `F` = full
- `D` = differential (depends on the full)
- `I` = incremental (depends on the differential)

```bash
exit
```

---

## 6. Test Point-in-Time Recovery (PITR)

### 6.1 Record the current time and insert a marker row

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT now();"
```

Write down this timestamp. This is the time "before the disaster."

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('before-disaster@example.com', 'Before Disaster');"
```

Wait 10 seconds, then record the time again:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT now() AS disaster_time;"
```

Write down this timestamp. This is our PITR target.

Now simulate a disaster - drop a table:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DROP TABLE app.order_items;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('after-disaster@example.com', 'After Disaster');"
```

We want to recover to the timestamp just before the DROP TABLE, preserving `before-disaster@example.com` but losing `after-disaster@example.com`.

### 6.2 Force a WAL archive

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_switch_wal();"
```

This ensures the WAL containing our DROP TABLE is archived so the restore can replay up to the target time.

```bash
exit
```

### 6.3 Stop PostgreSQL

Run as root:

```bash
systemctl stop postgresql-16
```

### 6.4 Perform PITR

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod --type=time "--target=2026-04-19 12:05:00+00" --target-action=promote --delta restore
```

Replace the target time with the timestamp you recorded (between the marker insert and the DROP TABLE).

- `--type=time` - Recover to a specific point in time.
- `--target` - The timestamp to recover to.
- `--target-action=promote` - After reaching the target, promote to a normal primary (not paused in recovery).
- `--delta` - Only restore files that differ from what is on disk. Faster than restoring everything.

Expected output (yours will differ):
```
INFO: restore command begin ...
INFO: restore file ... (checked/restored)
INFO: restore command end: completed successfully
```

```bash
exit
```

### 6.5 Start PostgreSQL and verify

Run as root:

```bash
systemctl start postgresql-16
```

```bash
su - postgres
```

Verify the order_items table is back:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.order_items;"
```

Expected output:
```
 count
-------
 30000
```

Verify the marker rows:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT email FROM app.customers WHERE email LIKE '%disaster%';"
```

Expected output:
```
           email
---------------------------
 before-disaster@example.com
```

The `before-disaster` row is present. The `after-disaster` row is gone. The table drop was reversed. PITR works.

```bash
exit
```

> **Concept - PITR limitations**: PITR recovers the entire cluster, not individual tables. If you drop one table but want to keep changes to other tables after that point, you would need to do a PITR to a separate instance and then selectively copy the data back. This is why prevention (careful DDL, DDL audit logging) is better than recovery.

---

## 7. Set Up a Backup Schedule

### 7.1 Create backup scripts

Run as root:

```bash
vi /opt/pgsql/scripts/backup-full.sh
```

Add:

```bash
#!/bin/bash
# Full backup - runs weekly on Sundays
/usr/bin/pgbackrest --stanza=prod --type=full backup
RESULT=$?
if [ $RESULT -ne 0 ]; then
    echo "CRITICAL: Full backup failed with exit code $RESULT" | logger -t pgbackrest
fi
exit $RESULT
```

Save and exit (`:wq`).

```bash
vi /opt/pgsql/scripts/backup-diff.sh
```

Add:

```bash
#!/bin/bash
# Differential backup - runs daily except Sunday
/usr/bin/pgbackrest --stanza=prod --type=diff backup
RESULT=$?
if [ $RESULT -ne 0 ]; then
    echo "CRITICAL: Diff backup failed with exit code $RESULT" | logger -t pgbackrest
fi
exit $RESULT
```

Save and exit (`:wq`).

```bash
chown postgres:postgres /opt/pgsql/scripts/backup-full.sh
```

```bash
chown postgres:postgres /opt/pgsql/scripts/backup-diff.sh
```

```bash
chmod 750 /opt/pgsql/scripts/backup-full.sh
```

```bash
chmod 750 /opt/pgsql/scripts/backup-diff.sh
```

### 7.2 Create cron jobs

```bash
crontab -u postgres -e
```

Add these lines:

```
# Full backup every Sunday at 2 AM UTC
0 2 * * 0 /opt/pgsql/scripts/backup-full.sh >> /opt/pgsql/log/pgbackrest/cron-full.log 2>&1

# Differential backup Monday-Saturday at 2 AM UTC
0 2 * * 1-6 /opt/pgsql/scripts/backup-diff.sh >> /opt/pgsql/log/pgbackrest/cron-diff.log 2>&1
```

Save and exit (`:wq`).

### 7.3 Verify cron is set

```bash
crontab -u postgres -l
```

Expected output:
```
0 2 * * 0 /opt/pgsql/scripts/backup-full.sh >> /opt/pgsql/log/pgbackrest/cron-full.log 2>&1
0 2 * * 1-6 /opt/pgsql/scripts/backup-diff.sh >> /opt/pgsql/log/pgbackrest/cron-diff.log 2>&1
```

---

## 8. Backup Monitoring

### 8.1 Create a monitoring script

```bash
vi /opt/pgsql/scripts/check-backup-age.sh
```

Add:

```bash
#!/bin/bash
# Check if the most recent backup is older than 25 hours
# Exit 0 = OK, Exit 1 = WARNING, Exit 2 = CRITICAL

MAX_AGE_HOURS=25

LAST_BACKUP_EPOCH=$(pgbackrest --stanza=prod info --output=json | python3 -c "
import sys, json
data = json.load(sys.stdin)
backups = data[0]['backup']
if not backups:
    print(0)
    sys.exit()
ts = backups[-1]['timestamp']['stop']
print(ts)
")

NOW_EPOCH=$(date +%s)
AGE_HOURS=$(( (NOW_EPOCH - LAST_BACKUP_EPOCH) / 3600 ))

if [ "$LAST_BACKUP_EPOCH" -eq 0 ]; then
    echo "CRITICAL: No backups found for stanza prod"
    exit 2
fi

if [ "$AGE_HOURS" -gt "$MAX_AGE_HOURS" ]; then
    echo "CRITICAL: Last backup is ${AGE_HOURS} hours old (threshold: ${MAX_AGE_HOURS}h)"
    exit 2
fi

echo "OK: Last backup is ${AGE_HOURS} hours old"
exit 0
```

Save and exit (`:wq`).

```bash
chown postgres:postgres /opt/pgsql/scripts/check-backup-age.sh
```

```bash
chmod 750 /opt/pgsql/scripts/check-backup-age.sh
```

### 8.2 Test the monitoring script

```bash
su - postgres
```

```bash
/opt/pgsql/scripts/check-backup-age.sh
```

Expected output:
```
OK: Last backup is 0 hours old
```

```bash
exit
```

### 8.3 Create a WAL archiving monitor

```bash
vi /opt/pgsql/scripts/check-wal-archive.sh
```

Add:

```bash
#!/bin/bash
# Check if WAL archiving is working
# Queries pg_stat_archiver for failed archive attempts

FAILED=$(su - postgres -c "/usr/pgsql-16/bin/psql -t -A -c \"SELECT failed_count FROM pg_stat_archiver;\"")

if [ "$FAILED" -gt 0 ]; then
    LAST_FAIL=$(su - postgres -c "/usr/pgsql-16/bin/psql -t -A -c \"SELECT last_failed_time FROM pg_stat_archiver;\"")
    echo "WARNING: $FAILED WAL archive failures. Last failure: $LAST_FAIL"
    exit 1
fi

echo "OK: WAL archiving healthy, 0 failures"
exit 0
```

Save and exit (`:wq`).

```bash
chown postgres:postgres /opt/pgsql/scripts/check-wal-archive.sh
```

```bash
chmod 750 /opt/pgsql/scripts/check-wal-archive.sh
```

---

## 9. Offsite Backup Copy

### 9.1 Add a second repository (S3 example)

In production, you should store a copy of backups offsite. Here is how to add an S3 repository.

```bash
vi /etc/pgbackrest/pgbackrest.conf
```

Add these lines to the `[global]` section:

```ini
repo2-type=s3
repo2-path=/pgbackrest-offsite
repo2-s3-bucket=[YOUR_BUCKET_NAME]
repo2-s3-endpoint=s3.amazonaws.com
repo2-s3-region=[YOUR_REGION]
repo2-s3-key=[YOUR_ACCESS_KEY]
repo2-s3-key-secret=[YOUR_SECRET_KEY]
repo2-retention-full=2
repo2-cipher-type=aes-256-cbc
repo2-cipher-pass=Off5ite_K3y_2026
```

Save and exit (`:wq`).

Replace the bracketed values with your actual S3 credentials and bucket name. In production, use IAM roles instead of static keys.

> **Note**: For this lab, the S3 configuration is optional. The local backup repository (repo1) is sufficient for learning. In production, ALWAYS have an offsite copy.

### 9.2 Copy a backup to the offsite repository

If you configured S3:

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod --type=full --repo=2 backup
```

```bash
exit
```

---

## 10. Verify the Full Backup Strategy

### 10.1 List all backups

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod info
```

You should see:
- At least 1 full backup
- At least 1 differential backup
- At least 1 incremental backup
- WAL archive spanning all backups

### 10.2 Test a restore to a temporary location

This is a non-destructive test - it restores to a separate directory without affecting the running server.

```bash
mkdir -p /tmp/pitr-test
```

```bash
pgbackrest --stanza=prod --pg1-path=/tmp/pitr-test --type=immediate --target-action=promote restore
```

- `--pg1-path=/tmp/pitr-test` - Restore to a temp directory, not the live data directory.
- `--type=immediate` - Recover to the end of the backup (consistent point) without replaying extra WAL.

Expected output (yours will differ):
```
INFO: restore command end: completed successfully
```

Verify the restore:

```bash
ls /tmp/pitr-test/
```

Expected output (yours will differ):
```
PG_VERSION  base  global  pg_commit_ts  pg_dynshmem  ...
```

Clean up:

```bash
rm -rf /tmp/pitr-test
```

```bash
exit
```

---

## Summary

You now have a complete backup strategy:

- pgBackRest configured with encryption and compression
- WAL archiving to the backup repository
- Full backup weekly (Sundays)
- Differential backup daily (Monday-Saturday)
- Retention: 3 full backups, 6 differentials, matching WAL archives
- PITR tested and verified
- Backup age monitoring
- WAL archive monitoring
- Offsite backup configuration (S3)

Next: [Build 04 - Monitoring and Alerting](04-monitoring-and-alerting.md)
