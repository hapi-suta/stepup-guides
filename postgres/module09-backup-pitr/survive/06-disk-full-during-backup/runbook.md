# Runbook 06 - Disk Full During Backup

**Severity:** High - Backup capability is offline, no new backups until space is freed
**Time to resolve:** 10-15 minutes

---

## Fix Path

### Step 1: Confirm the disk space situation

SSH to [NODE1] and check disk usage:

```bash
df -h
```

Look for the filesystem that holds `/opt/pgsql/backup/pgbackrest` (or wherever backups are stored). It should be at or near 100% usage.

Expected output (yours will differ):
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       20G   19G  512M  98% /
/dev/xvdb1       10G   10G     0 100% /opt/pgsql/backup
...
```

### Step 2: Identify what is consuming space

```bash
sudo du -sh /opt/pgsql/backup/pgbackrest/*
```

```bash
sudo du -sh /tmp/*
```

```bash
sudo du -sh /opt/pgsql/log/*
```

Look for:
- Large files in /tmp (the fill file from the injection)
- Old backup sets that can be expired
- Large log files

> **Concept - Disk Space Triage**: When a backup fails due to disk full, the immediate priority is freeing enough space for the backup to complete. Start with obvious targets: temp files, old logs, expired backups. Do not delete active backup sets or WAL archives.

### Step 3: Remove the space-consuming file

If you find a large fill file or temp file:

```bash
sudo rm -f ${CHAOS_STATE_DIR:-/tmp}/stepup-diskfill.dat
```

Verify space was recovered:

```bash
df -h
```

### Step 4: Check for additional space recovery opportunities

Review pgBackRest backup retention. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pgbackrest --stanza=main info
```

If there are old expired backups still on disk:

```bash
pgbackrest --stanza=main expire
```

Exit the postgres user:

```bash
exit
```

Clean up old PostgreSQL logs:

```bash
sudo find /opt/pgsql/log -name '*.log' -mtime +7 -delete
```

`-mtime +7` matches files older than 7 days. `-delete` removes them.

> **Concept - Backup Retention and Disk Planning**: Backup storage must be sized to hold retention-full number of full backups plus all differentials and WAL segments. A common mistake is sizing for current database size without accounting for growth, WAL volume, and retention depth.

### Step 5: Retry the backup

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pgbackrest --stanza=main --type=full backup
```

Monitor for success. Check the log if it fails again. Exit postgres first to read the system log:

```bash
exit
```

```bash
sudo tail -20 /var/log/pgbackrest/main-backup.log
```

### Step 6: Verify the backup completed successfully

Switch back to the postgres user:

```bash
sudo -iu postgres
```

```bash
pgbackrest --stanza=main info
```

Expected: A new full backup with a recent timestamp and valid size.

Expected output (yours will differ):
```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000008

        full backup: 20260419-143000F
            timestamp start/stop: 2026-04-19 14:30:00+00 / 2026-04-19 14:32:15+00
            wal start/stop: 000000010000000000000007 / 000000010000000000000008
            database size: 35.2MB, database backup size: 35.2MB
            ...
```

```bash
pgbackrest --stanza=main check
```

Expected: "check command end: completed successfully"

Exit the postgres user:

```bash
exit
```

### Step 7: Review disk space after backup

```bash
df -h
```

Ensure at least 20% free space remains for future backups, WAL accumulation, and operational headroom.

---

## Key Concepts for Revision

- **"No space left on device"** is one of the most common backup failures. It can also crash PostgreSQL if pg_wal runs out of space.
- **Backup storage sizing**: Plan for at least 2x your database size for full backups, plus WAL volume between backups. Account for compression ratios and retention depth.
- **pgBackRest expire** removes backups older than the configured retention policy. If retention-full=2 and you have 3 full backups, expire will remove the oldest.
- **Temporary files during backup**: pgBackRest creates temp files during backup. If the disk fills mid-backup, these orphaned temp files can consume space. Check for them in the repo directory.
- **WAL archiving under disk pressure**: If the archive destination is full, archive_command will fail. This causes WAL to accumulate on the primary, which can fill that disk too - a cascading failure.
- **Monitoring**: Set alerts for disk usage at 80% and 90%. By 95%, you should be paged. At 100%, you are in an outage.
- **Separate filesystems**: Best practice is to put pg_wal, data, and backups on separate filesystems so that one filling up does not crash the others.

---

## Interview Discussion Points

1. **Disk space monitoring**: What tools and thresholds do you use to monitor disk space on database servers? How do you predict when a disk will fill based on growth trends?

2. **Cascading failures**: If the backup disk fills up, how can this cascade to affect the primary database? Trace the failure path from backup to archive to pg_wal to PostgreSQL shutdown.

3. **Filesystem layout**: How do you lay out filesystems for a production PostgreSQL server? What goes on separate mount points and why?

4. **Emergency space recovery**: The primary's pg_wal disk is 99% full and PostgreSQL is about to shut down. What do you do in the next 60 seconds? (Hint: pg_switch_wal, remove old WAL, expand filesystem.)

5. **Cloud storage for backups**: How does using S3 or GCS for pgBackRest repos eliminate the disk-full problem? What new failure modes does it introduce?

6. **Compression tradeoffs**: pgBackRest supports lz4, zstd, and gzip compression. How does compression affect backup size, speed, and CPU usage? When would you change compression settings?

7. **Capacity planning**: You manage a database growing 10 GB per week. You keep 4 weekly full backups and daily differentials. How much backup storage do you need in 6 months?
