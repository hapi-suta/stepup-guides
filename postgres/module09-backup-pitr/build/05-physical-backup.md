# Build 05: Physical Backups

Configure WAL archiving and take physical backups with pg_basebackup. Physical
backups capture the entire cluster at the filesystem level - combined with WAL,
they enable point-in-time recovery.

---

## 1. Configure WAL archiving on NODE1

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Open postgresql.conf for editing:

```bash
vim /opt/pgsql/data/postgresql.conf
```

Set or uncomment these parameters:

```
wal_level = replica
archive_mode = on
archive_command = 'rsync -a %p postgres@pg-backup:/opt/pgsql/backup/archive/%f'
archive_timeout = 60
```

The `archive_command` tells PostgreSQL what to do with each completed WAL segment:
- `rsync -a` - archive mode, which preserves file permissions and timestamps
- `%p` - PostgreSQL replaces this with the full path to the WAL file on the primary
- `%f` - PostgreSQL replaces this with just the WAL filename (used to name the file on the backup server)

This works because you set up passwordless SSH between the postgres users in Build 01.

Save and exit vim.

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

> **Concept - wal_level = replica**: This is the minimum WAL level that includes
> enough information for both streaming replication and PITR. The `logical` level
> adds even more detail for logical replication. The default in PG 16 is `replica`,
> but always set it explicitly.

> **Concept - archive_command**: PostgreSQL calls this command every time a WAL
> segment is complete (16 MB by default). The `%p` placeholder is the full path
> to the WAL file, and `%f` is just the filename. The command must return exit
> code 0 only on success - PostgreSQL retries on failure and never recycles a
> WAL segment until archiving succeeds. Using rsync over SSH sends each segment
> to the backup server immediately.

> **Concept - archive_timeout**: Forces a WAL segment switch after this many
> seconds of inactivity. Without it, a quiet database might not complete a WAL
> segment for hours, leaving recent changes unarchived. 60 seconds means you lose
> at most 60 seconds of data if the primary dies before the current WAL segment
> is archived. In production, 60-300 seconds is typical.

## 2. Verify the archive directory on NODE2

**Run on NODE1 (pg-primary):**

Check that the directory from Build 01 exists on the backup server. This works because you set up passwordless SSH between the postgres users in Build 01.

```bash
ssh postgres@pg-backup "ls -la /opt/pgsql/backup/archive/"
```

Expected: empty directory owned by `postgres`.

## 3. Restart PostgreSQL to enable archiving

**Run on NODE1 (pg-primary):**

Restart PostgreSQL. The `archive_mode` change requires a full restart (reload is not enough):

```bash
sudo systemctl restart postgresql-16
```

Switch to the postgres user to verify the settings:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Check that archive_mode is on:

```bash
psql -c "SHOW archive_mode;"
```

```
Expected output:
 archive_mode
--------------
 on
(1 row)
```

Check that the archive_command is set:

```bash
psql -c "SHOW archive_command;"
```

```
Expected output:
                       archive_command
--------------------------------------------------------------
 rsync -a %p postgres@pg-backup:/opt/pgsql/backup/archive/%f
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

## 4. Force a WAL switch and verify archiving

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Force PostgreSQL to finish the current WAL segment and archive it:

```bash
psql -c "SELECT pg_switch_wal();"
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 0/2000108
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Wait a few seconds for the archive to complete, then check NODE2. This works because you set up passwordless SSH between the postgres users in Build 01.

```bash
ssh postgres@pg-backup "ls -la /opt/pgsql/backup/archive/"
```

Expected: at least one WAL file (named like `000000010000000000000001`).

WAL filenames are 24-character hex numbers. The first 8 characters are the timeline ID, the next 16 identify the segment position. You don't need to memorize this - just know that each file is a 16MB chunk of database changes.

```
Expected output (yours will differ):
total 16M
-rw-------. 1 postgres postgres 16M Apr 19 01:05 000000010000000000000001
```

Switch to postgres to check the archiver stats:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

```bash
psql -c "SELECT archived_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;"
```

Expected: `archived_count >= 1`, `last_archived_wal` shows a WAL filename.

```
Expected output (yours will differ):
 archived_count |    last_archived_wal     |      last_archived_time       | failed_count
----------------+--------------------------+-------------------------------+--------------
              1 | 000000010000000000000002 | 2026-04-19 01:05:25.981701+00 |            0
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

> **Concept - pg_stat_archiver**: This view is your monitoring source for WAL
> archiving health. Key columns:
> - `archived_count`: total segments archived since last stats reset
> - `failed_count`: total failures (should be 0)
> - `last_archived_wal`: most recent successful archive
> - `last_failed_wal`: if non-null, investigate immediately
>
> A growing `failed_count` means your archive_command is broken - WAL will
> accumulate on the primary until the disk fills.

## 5. Take a base backup with pg_basebackup - plain format

**Run on NODE2 (pg-backup):**

Run from NODE2 (the backup server pulls from the primary).

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

Take the base backup. Setting `PGPASSWORD` before the command passes the password automatically. This is the password you set in Build 02. In production, use a `.pgpass` file instead - `PGPASSWORD` is for lab use only.

This copies every file in the primary's data directory over the network:

```bash
PGPASSWORD=backup_lab_2026 pg_basebackup \
    -h pg-primary \
    -U postgres \
    -D /opt/pgsql/backup/basebackup/plain_backup \
    -Fp \
    -Xs \
    -P \
    --checkpoint=fast
```

What each flag means:
- `-h pg-primary` = connect to the primary server
- `-U postgres` = connect as the postgres user
- `-D` = destination directory for the backup
- `-Fp` = plain format (exact copy of data files)
- `-Xs` = stream WAL during backup (captures all changes made while the backup runs)
- `-P` = show progress
- `--checkpoint=fast` = start backup immediately instead of waiting for the next scheduled checkpoint

```
Expected output (yours will differ):
89562/89562 kB (100%), 1/1 tablespace
```

Verify the backup directory has a full data directory:

```bash
ls -la /opt/pgsql/backup/basebackup/plain_backup/
```

Expected: a full PostgreSQL data directory (base/, global/, pg_wal/, postgresql.conf, etc.).

```
Expected output (yours will differ):
total 68K
drwx------. 6 postgres postgres  54 Apr 19 01:08 base
drwx------. 2 postgres postgres 4.0K Apr 19 01:08 global
drwx------. 2 postgres postgres  32 Apr 19 01:08 pg_wal
-rw-------. 1 postgres postgres  227 Apr 19 01:08 backup_label
-rw-------. 1 postgres postgres 3.0K Apr 19 01:08 postgresql.conf
...
```

Exit back to NODE1:

```bash
exit
```

> **Concept - pg_basebackup**: This tool creates a binary copy of the entire
> PostgreSQL data directory. Combined with WAL archives, it forms the foundation
> for PITR. The `-Xs` (stream) flag is critical - it opens a second connection to
> stream WAL during the backup, guaranteeing the backup is self-consistent even
> without referring to the archive.

> **Concept - checkpoint=fast**: By default, pg_basebackup waits for PostgreSQL's
> next scheduled checkpoint before starting. With `--checkpoint=fast`, it triggers
> an immediate checkpoint. This starts the backup faster but causes a brief I/O
> spike. In production during business hours, consider omitting this flag.

## 6. Take a base backup - TAR compressed format

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

Take a compressed backup. Setting `PGPASSWORD` before the command passes the password automatically. This is the password you set in Build 02. In production, use a `.pgpass` file instead - `PGPASSWORD` is for lab use only.

The `-Ft -z` flags produce a gzip-compressed tar archive instead of a plain copy:

```bash
PGPASSWORD=backup_lab_2026 pg_basebackup \
    -h pg-primary \
    -U postgres \
    -D /opt/pgsql/backup/basebackup/tar_backup \
    -Ft \
    -z \
    -Xs \
    -P \
    --checkpoint=fast
```

Verify the tar files were created:

```bash
ls -lh /opt/pgsql/backup/basebackup/tar_backup/
```

Expected: `base.tar.gz` and `pg_wal.tar.gz`.

```
Expected output (yours will differ):
total 273M
-rw-------. 1 postgres postgres 268K Apr 19 01:10 backup_manifest
-rw-------. 1 postgres postgres 273M Apr 19 01:10 base.tar.gz
-rw-------. 1 postgres postgres  34K Apr 19 01:10 pg_wal.tar.gz
```

Compare the size of the plain format backup:

```bash
du -sh /opt/pgsql/backup/basebackup/plain_backup/
```

Compare the size of the TAR+gzip backup:

```bash
du -sh /opt/pgsql/backup/basebackup/tar_backup/
```

Exit back to NODE1:

```bash
exit
```

> **Concept - TAR format for base backups**: The `-Ft -z` combination produces a
> compressed tar archive. This is more space-efficient for storage and easier to
> transfer. The tradeoff - you cannot start a PostgreSQL instance directly from a
> tar backup; you must extract it first. Plain format backups can be started
> in-place (useful for fast PITR).

## 7. Verify the base backup (plain format)

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

Check that critical files exist. The PG_VERSION file tells you which major version made the backup:

```bash
cat /opt/pgsql/backup/basebackup/plain_backup/PG_VERSION
```

```
Expected output:
16
```

The pg_control file is the most important file in any PostgreSQL cluster:

```bash
ls /opt/pgsql/backup/basebackup/plain_backup/global/pg_control
```

Expected: file exists.

Exit back to NODE1:

```bash
exit
```

> **Concept - What is in a base backup?**: A base backup is a filesystem snapshot
> of the data directory taken while PostgreSQL is running. It includes everything -
> all databases, all tables, configuration files, WAL position markers. What it
> does NOT include is the WAL generated during and after the backup. That is why
> you need WAL archiving - the base backup is your starting point, and WAL replay
> brings it to any point in time after the backup.

## 8. Understand the PITR equation

**Run on NODE2 (pg-backup):**

```
Base Backup (Point A) + WAL Archives (A -> B) = Recovery to Point B
```

SSH into NODE2 to inspect the backup label:

```bash
ssh ec2-user@pg-backup
```

The backup_label file records where this backup started in the WAL stream:

```bash
cat /opt/pgsql/backup/basebackup/plain_backup/backup_label
```

Expected: shows `START WAL LOCATION` and `START TIME`.

```
Expected output (yours will differ):
START WAL LOCATION: 1/12000028 (file 000000010000000100000012)
CHECKPOINT LOCATION: 1/12000060
BACKUP METHOD: streamed
BACKUP FROM: primary
START TIME: 2026-04-19 01:08:30 UTC
LABEL: pg_basebackup base backup
START TIMELINE: 1
```

WAL filenames are 24-character hex numbers. The first 8 characters are the timeline ID, the next 16 identify the segment position. You don't need to memorize this - just know that each file is a 16MB chunk of database changes.

Check how many WAL files have been archived so far:

```bash
ls /opt/pgsql/backup/archive/ | wc -l
```

Exit back to NODE1:

```bash
exit
```

> **Concept - The PITR equation**: A base backup records the starting WAL
> position. WAL archiving continuously saves every change after that position.
> To recover to any point in time T:
> 1. Restore the most recent base backup taken before T
> 2. Replay WAL from the backup's start position up to T
> 3. PostgreSQL stops replaying at T - your database is exactly as it was
>
> This is why both pieces are essential. A base backup alone gives you the
> database at backup time. WAL alone is useless without a starting point.
> Together, they give you any point in time.

## 9. Create additional WAL activity for PITR testing

**Run on NODE1 (pg-primary):**

Generate some WAL activity so there are segments to replay in the next guide.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Insert 10,000 rows into the pgbench_history table:

```bash
psql -d labdb -c "
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime)
SELECT (random() * 32)::int + 1,
       (random() * 32)::int + 1,
       (random() * 32999999)::int + 1,
       (random() * 10000)::int,
       now()
FROM generate_series(1, 10000) g;
"
```

```
Expected output:
INSERT 0 10000
```

Force PostgreSQL to finish the current WAL segment and archive it:

```bash
psql -c "SELECT pg_switch_wal();"
```

```
Expected output (yours will differ):
 pg_switch_wal
---------------
 0/4000108
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user.**

Wait a few seconds for archiving:

```bash
sleep 5
```

Verify new WAL files arrived on NODE2. This works because you set up passwordless SSH between the postgres users in Build 01.

```bash
ssh postgres@pg-backup "ls -lt /opt/pgsql/backup/archive/ | head -5"
```

Expected: recent WAL files with timestamps after the base backup.

WAL filenames are 24-character hex numbers. The first 8 characters are the timeline ID, the next 16 identify the segment position. You don't need to memorize this - just know that each file is a 16MB chunk of database changes.

```
Expected output (yours will differ):
-rw-------. 1 postgres postgres 16777216 Apr 19 01:14 00000001000000010000001A
-rw-------. 1 postgres postgres 16777216 Apr 19 01:13 000000010000000100000019
-rw-------. 1 postgres postgres 16777216 Apr 19 01:12 000000010000000100000018
```

---

## Checkpoint

NODE1 (primary) has:
- [x] `wal_level = replica`
- [x] `archive_mode = on`
- [x] `archive_command` rsync to NODE2 at `/opt/pgsql/backup/archive/`
- [x] `archive_timeout = 60`
- [x] WAL archiving confirmed working (`pg_stat_archiver`)

NODE2 (backup server) has:
- [x] WAL files in `/opt/pgsql/backup/archive/`
- [x] Plain format base backup in `/opt/pgsql/backup/basebackup/plain_backup/`
- [x] TAR format base backup in `/opt/pgsql/backup/basebackup/tar_backup/`
- [x] Base backup verified (PG_VERSION, backup_label)

Proceed to `06-pitr.md`.
