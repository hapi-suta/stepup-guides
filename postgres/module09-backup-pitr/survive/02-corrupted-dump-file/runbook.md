# Runbook 02 - Corrupted Dump File

**Severity:** High - Backup integrity compromised, recovery capability degraded
**Time to resolve:** 10-15 minutes

---

## Fix Path

### Step 1: Confirm the dump file is corrupt

SSH to [NODE2].

Switch to the postgres user.

```bash
sudo -iu postgres
```

Try to list the dump contents:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.custom
```

Expected output (yours will differ):

```
pg_restore: error: did not find magic string in file header
```

This means the file header is corrupted and pg_restore cannot read it.

```bash
file /opt/pgsql/backup/dumps/stepup_store.custom
```

This may show "data" instead of the expected "PostgreSQL custom database dump" signature.

> **Concept - pg_restore --list**: The --list flag reads the table of contents from a custom-format dump without actually restoring anything. It is the fastest way to verify a dump file is structurally valid. Always use this as a post-backup verification step.

### Step 2: Check for alternative backup formats

Look for other dump formats on [NODE2]:

```bash
ls -lh /opt/pgsql/backup/dumps/
```

You may find:
- Directory-format dumps (a folder with toc.dat and data files)
- Tar-format dumps (.tar)
- Plain SQL dumps (.sql)

If a directory-format dump exists:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.dir/
```

If a tar-format dump exists:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.tar
```

### Step 3: If no valid dump exists, take a fresh one

Connect to the primary. If you are not already the postgres user, switch now.

```bash
sudo -iu postgres
```

Create a custom-format dump. This is the most versatile format for selective restores.

```bash
/usr/pgsql-16/bin/pg_dump -p 5432 -d stepup_store -Fc -f /opt/pgsql/backup/dumps/stepup_store.custom
```

Create a directory-format dump. The `-Fd` flag tells pg_dump to write a directory-format archive. The `-j 4` flag runs 4 parallel jobs to dump tables at the same time, which is faster on multi-core servers.

```bash
/usr/pgsql-16/bin/pg_dump -p 5432 -d stepup_store -Fd -j 4 -f /opt/pgsql/backup/dumps/stepup_store.dir
```

Verify the custom-format dump is valid.

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.custom
```

Verify the directory-format dump is valid.

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.dir/
```

> **Concept - Backup Format Diversity**: Maintaining dumps in multiple formats (custom, directory, tar) provides resilience. If one format is corrupted, you can fall back to another. Directory-format dumps are especially resilient because each table is a separate file - corruption of one file does not destroy the entire backup.

### Step 4: Verify the new backup

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.custom | head -20
```

Expected: Clean table-of-contents listing with table names, sequences, constraints, etc.

Also verify row counts by doing a test restore to /dev/null. The `grep -c "INSERT\|COPY"` part counts how many INSERT or COPY statements appear in the dump output - these are the commands that load actual data into tables, so a non-zero count confirms data is present.

```bash
/usr/pgsql-16/bin/pg_restore -f /dev/stdout /opt/pgsql/backup/dumps/stepup_store.custom | grep -c "INSERT\|COPY"
```

### Step 5: Remove the corrupted file

First, rename the corrupted file in case you want to keep it for analysis later.

```bash
mv /opt/pgsql/backup/dumps/stepup_store.custom.corrupt /opt/pgsql/backup/dumps/stepup_store.custom.corrupt.bak
```

Once you have confirmed the new backup is valid, remove the corrupted file.

```bash
rm /opt/pgsql/backup/dumps/stepup_store.custom.corrupt.bak
```

### Step 6: Set up backup verification

Add a post-backup verification step to your backup scripts. Run `pg_restore --list` against the dump file after every backup.

```bash
/usr/pgsql-16/bin/pg_restore --list "$DUMP_FILE"
```

If this shows an error, the backup file is still corrupted. A clean run produces a table-of-contents listing with no errors.

Expected output (yours will differ):

```
;
; Archive created at 2026-04-19 10:30:00 UTC
;     dbname: stepup_store
;     TOC Entries: 42
;
; Selected TOC Entries:
;
200; 1259 16385 TABLE public customers postgres
201; 1259 16392 TABLE public orders postgres
...
```

Exit the postgres user when you are done.

```bash
exit
```

---

## Key Concepts for Revision

- **pg_restore --list** is a non-destructive way to verify dump integrity. Run it after every backup to catch corruption early.
- **Custom format (-Fc)** stores data in a compressed, reorderable format with a table of contents. It supports selective restore but is a single binary file - corruption at the header is fatal.
- **Directory format (-Fd)** splits each table into a separate compressed file with a toc.dat manifest. This is more resilient to partial corruption and supports parallel dump/restore with -j.
- **Backup verification** should be automated and run immediately after every backup completes. A backup that has not been verified is not a backup.
- **Multiple backup methods** (pg_dump + pgBackRest + pg_basebackup) provide defense in depth. Never rely on a single backup type.
- **File-level checksums** (md5sum, sha256sum) should be stored alongside dump files so corruption can be detected by comparing hashes.
- **3-2-1 backup rule**: 3 copies, 2 different media types, 1 offsite. Corruption of a single dump file should never be a crisis.

---

## Interview Discussion Points

1. **Backup verification strategy**: How do you verify backups in production? Do you restore them regularly? What is the difference between verifying a dump file header vs doing a full test restore?

2. **Silent corruption**: A dump file passes pg_restore --list but contains wrong data due to a bug in pg_dump or storage-layer bit rot. How would you detect this? Discuss checksums, periodic test restores, and data validation queries.

3. **Format selection**: When would you choose custom format over directory format? What about plain SQL? How does the choice affect restore speed, parallelism, and resilience?

4. **Backup monitoring**: What metrics would you monitor for your backup pipeline? (Backup duration, file size trends, verification status, age of newest backup, success/failure ratio.)

5. **Recovery from total dump loss**: If all dump files on the backup server are corrupted, what are your remaining options? (pgBackRest physical backups, pg_basebackup from a running replica, WAL archive for PITR.)

6. **Backup storage reliability**: How do you protect backup storage from corruption? Discuss: RAID, ZFS checksums, S3 versioning, cross-region replication, and immutable backups.

7. **Compliance and audit**: In regulated environments, how do you prove that backups are valid and tested? What documentation do you maintain?
