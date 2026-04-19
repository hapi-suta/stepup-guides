# Runbook 05 - pgBackRest Repo Corruption

**Severity:** Critical - Backup integrity compromised, restore capability at risk
**Time to resolve:** 15-20 minutes

---

## Fix Path

### Step 1: Confirm pgBackRest reports errors

SSH to [NODE1] and check backup status:

```bash
sudo -u postgres pgbackrest --stanza=main info
```

Expected: Errors, missing backup info, or corrupted output.

Also run a verify:

```bash
sudo -u postgres pgbackrest --stanza=main verify
```

This will report specific files that are corrupted or missing.

> **Concept - pgBackRest Verify**: The verify command checks every file in the repository against stored checksums. It can detect bit rot, truncation, and missing files. Run it regularly as a monitoring check.

### Step 2: Identify the corrupted backup

List the backup directory to find which backup is affected:

```bash
sudo ls -la /opt/pgsql/backup/pgbackrest/backup/main/
```

Each subdirectory is a backup set. Look for the one with a corrupted `backup.manifest` file:

```bash
sudo find /opt/pgsql/backup/pgbackrest/backup/main -name 'backup.manifest' -exec md5sum {} \;
```

Try reading the manifest:

```bash
sudo cat /opt/pgsql/backup/pgbackrest/backup/main/[BACKUP_LABEL]/backup.manifest | head -20
```

If the output is binary garbage, the manifest is corrupted.

### Step 3: Remove the corrupted backup

Use pgBackRest expire to remove the corrupted backup, or manually remove the directory:

```bash
# Manual removal of the corrupted backup directory
sudo rm -rf /opt/pgsql/backup/pgbackrest/backup/main/[CORRUPTED_BACKUP_LABEL]
```

> **Concept - Backup Manifest**: The backup.manifest file contains the checksum, size, and timestamp of every file in the backup. Without a valid manifest, pgBackRest cannot restore from that backup. Corruption of the manifest effectively destroys the entire backup set.

### Step 4: Take a new full backup

```bash
sudo -u postgres pgbackrest --stanza=main --type=full backup
```

This will take several minutes depending on database size. Monitor progress:

```bash
# In another terminal
sudo -u postgres pgbackrest --stanza=main info
```

### Step 5: Verify the new backup

```bash
sudo -u postgres pgbackrest --stanza=main info
```

Expected: A valid full backup with correct size and timestamp.

Run a deeper check:

```bash
sudo -u postgres pgbackrest --stanza=main check
```

Expected: "check command end: completed successfully"

### Step 6: Verify stanza health

```bash
sudo -u postgres pgbackrest --stanza=main verify
```

Expected: No errors. All WAL segments and backup files pass checksum validation.

### Step 7: Test restore capability

Do a quick restore to a scratch location to confirm the backup is usable:

```bash
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/tmp/pg-restore-test \
  --type=immediate \
  --target-action=promote \
  restore

sudo -u postgres /usr/pgsql-16/bin/pg_ctl \
  -D /tmp/pg-restore-test -o "-p 5433" start

sudo -u postgres /usr/pgsql-16/bin/psql -p 5433 -d labdb -c "SELECT count(*) FROM employees;"

# Clean up
sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /tmp/pg-restore-test stop
rm -rf /tmp/pg-restore-test
```

---

## Key Concepts for Revision

- **backup.manifest** is the critical metadata file in each pgBackRest backup set. It stores checksums, sizes, timestamps, and file lists. Losing it makes the backup unrestorable.
- **pgbackrest verify** performs integrity checking of the entire repository - backups and WAL archive. It should be scheduled as a regular job (e.g., weekly).
- **pgbackrest check** is lighter than verify - it confirms the stanza is correctly configured and archiving works, but does not check every file's checksum.
- **Full vs incremental after corruption**: After removing a corrupted backup, you must take a new full backup. Incremental and differential backups depend on a valid full backup as their base.
- **Repository encryption**: pgBackRest supports repo encryption. If enabled, corruption of the encryption key file is even more catastrophic than manifest corruption.
- **Backup retention**: With retention-full=2, losing one backup still leaves you with one valid full backup. Single-backup retention (retention-full=1) means any corruption leaves you with zero backups.
- **Offsite copies**: Mirror your pgBackRest repo to a second location (S3, another server) so that local corruption does not destroy all backups.

---

## Interview Discussion Points

1. **Repository monitoring**: How do you detect pgBackRest repo corruption before you need to restore? What automated checks do you run?

2. **Backup chain dependencies**: If a differential backup's parent full backup is corrupted, what happens to the differential? Can you restore from it?

3. **Storage-layer protection**: What storage features help prevent silent data corruption? Discuss: ZFS checksums, ECC RAM, RAID scrubbing, S3 data integrity checks.

4. **Recovery time impact**: How long does it take to take a new full backup of a 500 GB database? How does this affect your recovery posture while the backup is running?

5. **Multi-repo strategy**: pgBackRest supports multiple repositories (repo1, repo2). How would you use this to protect against repo corruption? What is the cost?

6. **Encryption key management**: If you use pgBackRest repo encryption and lose the key, what happens? How do you back up the encryption key itself?

7. **Corruption root cause**: What causes repo corruption in practice? Discuss: disk failures, filesystem bugs, incomplete writes during power loss, storage controller issues.
