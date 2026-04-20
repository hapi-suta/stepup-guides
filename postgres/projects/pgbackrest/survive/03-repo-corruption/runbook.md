# Runbook 03 - Backup Repository Corruption

**Severity:** Critical - Backup repository metadata is damaged, existing backups may be unusable
**Time to resolve:** 15-25 minutes
**Symptoms:** `pgbackrest info` fails with errors, cannot list backups, cannot take new backups
**Impact:** Existing backups cannot be verified or restored. No new backups can be taken. Full data loss risk if the database fails while the repo is broken.

---

## Layer 1 - Quick Fix

### Step 1: SSH to the server

Log in to your server:

```bash
ssh -i /path/to/your-key.pem ec2-user@[YOUR_SERVER_IP]
```

### Step 2: Switch to the postgres user

```bash
sudo -i -u postgres
```

### Step 3: Check the current state of pgBackRest

Try to list backups:

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
ERROR: [029]: unable to load info file '/opt/pgsql/backup/pgbackrest/backup/main/backup.info'
       or '/opt/pgsql/backup/pgbackrest/backup/main/backup.info.copy':
       CryptoError: unable to parse info file checksum from file content
       CryptoError: unable to parse info file checksum from file content
       HINT: backup.info or backup.info.copy is damaged
```

The error tells you that backup.info (the master index of all backups) is damaged.

### Step 4: Run stanza check

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
ERROR: [029]: unable to load info file ...
```

This confirms the repository metadata is broken.

> **Concept - backup.info**: This file is the master catalog for the backup repository. It records every backup that has been taken - the label, timestamp, size, WAL range, and type (full/diff/incr). Without a valid backup.info, pgBackRest cannot list, verify, or restore any backups, even if the actual backup data files are perfectly fine on disk.

### Step 5: Examine the repo directory structure

Look at what is in the backup repository:

```bash
ls -la /opt/pgsql/backup/pgbackrest/backup/main/
```

Expected output (yours will differ):

```
total 12
drwxr-x--- 3 postgres postgres 4096 Apr 20 12:05 .
drwxr-x--- 3 postgres postgres 4096 Apr 20 12:00 ..
-rw-r----- 1 postgres postgres   10 Apr 20 14:00 backup.info
-rw-r----- 1 postgres postgres   10 Apr 20 14:00 backup.info.copy
drwxr-x--- 3 postgres postgres 4096 Apr 20 12:05 20260420-120000F
```

You can see:
- `backup.info` and `backup.info.copy` exist but are tiny (10 bytes - they are corrupted)
- A backup directory `20260420-120000F` exists (the actual backup data)

Check if the backup manifest is present:

```bash
ls -la /opt/pgsql/backup/pgbackrest/backup/main/20260420-120000F/
```

Expected output (yours will differ):

```
total 4
drwxr-x--- 3 postgres postgres 4096 Apr 20 12:05 .
drwxr-x--- 3 postgres postgres 4096 Apr 20 14:00 ..
drwxr-x--- 5 postgres postgres 4096 Apr 20 12:05 pg_data
```

The `backup.manifest` is missing from the backup directory. Without the manifest, pgBackRest cannot reconstruct the backup even if the data files are there.

> **Concept - backup.manifest**: Each backup directory contains a manifest file that lists every file in the backup, its size, checksum, and permissions. pgBackRest uses this during restore to verify file integrity. Without it, the backup data is effectively orphaned - the files might be fine, but pgBackRest has no way to verify or use them.

### Step 6: Decide on the recovery approach

Since both backup.info AND the backup manifest are corrupted/missing, the existing backup cannot be rebuilt. We need to:
1. Clean up the corrupted metadata
2. Rebuild the stanza
3. Take a fresh full backup

### Step 7: Remove the corrupted backup entry

The old backup is unusable without its manifest. Remove it:

```bash
rm -rf /opt/pgsql/backup/pgbackrest/backup/main/20260420-120000F
```

This removes the orphaned backup data. Replace `20260420-120000F` with whatever backup label you see in your directory listing from Step 5.

> **Concept - When to remove vs rebuild**: If only backup.info is corrupted but manifests are intact, you can delete and recreate the stanza (`stanza-delete --force` then `stanza-create`) to rebuild the metadata from the existing backups. But if manifests are also missing, the backup data is orphaned and must be removed before rebuilding. Note: in pgBackRest versions before 2.58, `stanza-create --force` could rebuild metadata in place, but this flag is no longer supported.

### Step 8: Remove the corrupted backup.info files

```bash
rm -f /opt/pgsql/backup/pgbackrest/backup/main/backup.info
```

```bash
rm -f /opt/pgsql/backup/pgbackrest/backup/main/backup.info.copy
```

### Step 9: Rebuild the stanza

In pgBackRest 2.58+, the `--force` flag on `stanza-create` is deprecated. Instead, delete the corrupted stanza first, then recreate it.

First, stop the stanza (if not already stopped):

```bash
pgbackrest --stanza=main stop
```

Expected output (yours will differ):

```
P00   INFO: stop command end: completed successfully (10ms)
```

Next, delete the corrupted stanza. The `--force` flag on `stanza-delete` removes the stanza even though the metadata is damaged:

```bash
pgbackrest --stanza=main stanza-delete --force
```

Expected output (yours will differ):

```
P00   INFO: stanza-delete command end: completed successfully (50ms)
```

Finally, recreate the stanza from scratch:

```bash
pgbackrest --stanza=main stanza-create
```

Expected output (yours will differ):

```
P00   INFO: stanza-create command end: completed successfully (100ms)
```

This creates a fresh empty backup catalog. Since the old backup data was corrupted and removed, the new stanza starts clean.

### Step 10: Verify the stanza is healthy

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00   INFO: check command end: completed successfully (200ms)
```

### Step 11: Take a fresh full backup

You need at least one full backup for the repo to be useful:

```bash
pgbackrest --stanza=main --type=full backup
```

Expected output (yours will differ):

```
P00   INFO: backup command begin 2.53: ...
P00   INFO: execute non-exclusive backup start: backup begins after ...
P00   INFO: backup stop: ...
P00   INFO: new backup label = 20260420-143500F
P00   INFO: full backup size = 800MB, file total = 1234
P00   INFO: backup command end: completed successfully (120500ms)
```

This takes a few minutes depending on database size.

> **Concept - Full vs differential vs incremental**: After a repository rebuild, you must start with a full backup. Differential backups compare against the last full, and incremental backups compare against the last backup of any type. Without a full backup as the base, neither diff nor incr can work.

### Step 12: Verify the new backup

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 00000001000000000000001F/000000010000000000000021

        full backup: 20260420-143500F
            timestamp start/stop: 2026-04-20 14:35:00 / 2026-04-20 14:37:05
            wal start/stop: 000000010000000000000020 / 000000010000000000000020
            database size: 800MB, database backup size: 800MB
            repo1: backup set size: 120MB, backup size: 120MB
```

You should see one full backup with status "ok".

### Step 13: Verify WAL archiving still works

Open psql.

```bash
psql
```

Run this query.

```sql
SELECT pg_switch_wal();
```

Exit psql.

```
\q
```

Wait a few seconds:

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00   INFO: check command end: completed successfully (205ms)
```

Return to ec2-user:

```bash
exit
```

---

## Layer 2 - Concepts

> **backup.info - the master catalog**
> backup.info is a structured text file that tracks every backup in the repository. It contains the backup label, type (full/diff/incr), timestamp, WAL range, database version, and system identifier. pgBackRest keeps a `.copy` as a redundant copy. If both are corrupted, the entire backup catalog is lost.

> **backup.manifest - per-backup inventory**
> Each backup directory contains a manifest file listing every database file, its size, checksum (SHA-256), and permissions. During restore, pgBackRest uses the manifest to verify every file is intact. A backup without a manifest cannot be restored - even if all the data files are present.

> **Why repo integrity matters**
> A corrupted backup is worse than no backup. You think you are protected, but when disaster strikes and you try to restore, you discover the backup is unusable. This is why you must regularly verify backups with `pgbackrest verify` and test restores on a schedule.

> **Defense: Protect your metadata**
> Store the backup repo on a separate disk or separate server. Use pgBackRest's built-in repo encryption to detect tampering. Run `pgbackrest verify` on a schedule to catch corruption early. Consider a second repo (repo2) for redundancy - pgBackRest supports multi-repo configurations.

> **Stanza recovery: delete and recreate**
> In pgBackRest 2.58+, `stanza-create --force` is deprecated. The supported approach is: `stanza-delete --force` (removes the corrupted stanza metadata) followed by `stanza-create` (rebuilds from scratch). The `--force` flag on `stanza-delete` allows deletion even when metadata is damaged. If valid backups with intact manifests exist in the repo directory, the new stanza-create will detect and catalog them.

---

## Layer 3 - Interview Discussion

1. **How do you detect backup repository corruption before you need a restore?** Run `pgbackrest verify` on a schedule (daily or weekly). This command checks every backup's manifest, verifies file checksums, and confirms WAL continuity. Alert on any errors. Do not wait until restore time to discover corruption.

2. **Your backup.info is corrupted but all backup directories and manifests are intact. What is the fastest recovery?** Stop the stanza (`pgbackrest --stanza=main stop`), delete it (`pgbackrest --stanza=main stanza-delete --force`), then recreate it (`pgbackrest --stanza=main stanza-create`). The recreate scans the repo directory, finds all backups with valid manifests, and rebuilds backup.info from them. No data is lost. You do not need to take a new backup. Note: in pgBackRest versions before 2.58, `stanza-create --force` could do this in one step, but that flag is now deprecated.

3. **How would you design a backup strategy that survives repo corruption?** Use pgBackRest's multi-repo feature - repo1 on local disk, repo2 on S3 or a remote server. Even if repo1 is corrupted, repo2 has a complete independent copy. Also consider immutable storage (S3 Object Lock) to prevent accidental deletion or ransomware.

4. **A junior DBA accidentally runs rm -rf on the backup repo. What is your recovery plan?** If you have a second repo, switch to it. If the repo is on a filesystem with snapshots (ZFS, LVM, EBS), restore from a snapshot. If neither, you must take a new full backup immediately - you have zero protection until it completes. This is why multi-repo and immutable storage are critical.

5. **How do you test that your backups are actually restorable?** Schedule regular test restores to a separate server. Automate this - do not rely on manual testing. Restore the backup, start PostgreSQL, run validation queries (row counts, checksums). pgBackRest's `--target-action=promote` makes test restores straightforward. Some teams restore nightly and run their full test suite against the restored copy.
