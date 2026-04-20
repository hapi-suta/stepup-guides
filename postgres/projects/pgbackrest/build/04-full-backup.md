# Take Your First Full Backup

**Estimated time:** 20 minutes

**What you'll learn:**
- What a full backup is
- How to take a full backup with pgBackRest
- How to read the backup output and info report
- How to calculate compression savings

**Prerequisites:**
- Completed guides 01-03 (pgBackRest installed, stanza created, WAL archiving working)
- PostgreSQL 16 is running

---

## What is a full backup?

A full backup is a complete copy of your entire PostgreSQL data directory. It includes every database, every table, every index - everything. A full backup is self-contained, meaning you can restore from it without needing anything else (except WAL files for point-in-time recovery).

Full backups are the foundation of your backup strategy. Differential and incremental backups (covered in guide 05) depend on having a full backup to start from.

---

## Step 1: Connect to your server

```bash
ssh -i your-key.pem ec2-user@your-server-ip
```

---

## Step 2: Switch to the postgres user

pgBackRest runs as the `postgres` user because it needs to read the PostgreSQL data directory.

```bash
sudo -i -u postgres
```

---

## Step 3: Take a full backup

Run the backup command. This will take a minute or two depending on your database size.

```bash
pgbackrest --stanza=main --type=full backup
```

The `--type=full` flag tells pgBackRest to back up everything. You'll see output as the backup runs.

```
Expected output (yours will differ):
P00   INFO: backup command begin 2.54: --compress-type=lz4 ...
P00   INFO: execute non-exclusive backup start: backup begins after the next regular checkpoint completes
P00   INFO: backup start archive = 000000010000000000000006, lsn = 0/6000028
P00   INFO: check archive for prior segment 000000010000000000000005
P00   INFO: execute non-exclusive backup stop and target backup
P00   INFO: backup stop archive = 000000010000000000000006, lsn = 0/6000138
P00   INFO: check archive for segment(s) 000000010000000000000006:000000010000000000000006
P00   INFO: new backup label = 20260420-111500F
P00   INFO: full backup size = 823.4MB, repo size = 142.1MB
P00   INFO: backup command end: completed successfully
...
```

Let's break down the important lines:
- **backup start archive** - the WAL position when the backup began
- **backup stop archive** - the WAL position when the backup ended
- **new backup label** - the name of this backup (date + time + F for Full)
- **full backup size = 823.4MB** - the actual size of your data
- **repo size = 142.1MB** - how much space the backup takes after compression
- **completed successfully** - the backup worked!

> **Concept: Full backup = self-contained**
> A full backup doesn't depend on any previous backup. You can restore from it all by itself. This makes it the safest type of backup, but also the largest and slowest to create.

---

## Step 4: Check the backup info

pgBackRest keeps detailed records of every backup. Let's see the summary.

```bash
pgbackrest --stanza=main info
```

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000005/000000010000000000000006

        full backup: 20260420-111500F
            timestamp start/stop: 2026-04-20 11:15:00+00 / 2026-04-20 11:16:23+00
            wal start/stop: 000000010000000000000006 / 000000010000000000000006
            database size: 823.4MB, database backup size: 823.4MB
            repo size: 142.1MB, repo backup size: 142.1MB
            backup reference list:
```

Let's understand each part:
- **status: ok** - your backup infrastructure is healthy
- **wal archive min/max** - the range of WAL files stored in the archive
- **full backup: 20260420-111500F** - the backup label (date-time-F for Full)
- **timestamp start/stop** - when the backup started and finished
- **database size** - the uncompressed size of your data
- **repo size** - the compressed size stored in the repository

> **Concept: Compression ratio**
> pgBackRest compresses backups with lz4 by default. In this example, 823.4MB of data was compressed down to 142.1MB - that's about a 5.8x compression ratio, saving you roughly 83% of disk space. Your numbers will vary depending on your data.

---

## Step 5: Calculate the compression ratio

Let's do the math. Look at your output from the previous step and find the two size numbers.

Divide the database size by the repo size. For example:
- 823.4 / 142.1 = 5.8x compression

That means pgBackRest is storing your backup at about 1/6th of its original size. This adds up fast - if you have 1 TB of data, your backups might only use 170 GB.

---

## Step 6: Explore the backup in the repository

Let's see what pgBackRest created in the backup directory.

```bash
ls /opt/pgsql/backup/pgbackrest/backup/main/
```

```
Expected output (yours will differ):
20260420-111500F  backup.info  backup.info.copy
```

The directory name matches the backup label from the info output. Let's look inside.

```bash
ls /opt/pgsql/backup/pgbackrest/backup/main/20260420-111500F/
```

```
Expected output (yours will differ):
backup.manifest  backup.manifest.copy  pg_data
```

- `backup.manifest` - a detailed record of every file in the backup (checksums, sizes, timestamps)
- `pg_data` - the actual backed-up database files

```bash
ls /opt/pgsql/backup/pgbackrest/backup/main/20260420-111500F/pg_data/
```

```
Expected output (yours will differ):
PG_VERSION  base  global  pg_commit_ts  pg_dynshmem  pg_logical  pg_multixact
pg_notify  pg_replslot  pg_serial  pg_snapshots  pg_stat  pg_stat_tmp
pg_subtrans  pg_tblspc  pg_twophase  pg_wal  postgresql.auto.conf
postgresql.conf
...
```

This looks familiar - it's the structure of your PostgreSQL data directory, but compressed and stored safely in the backup repository.

> **Concept: start-fast=y triggers an immediate checkpoint**
> When a backup starts, PostgreSQL needs to do a checkpoint - flushing all buffered data to disk. Normally it waits for the next scheduled checkpoint (which could be minutes away). Because we set `start-fast=y` in the config, pgBackRest tells PostgreSQL to checkpoint immediately, so your backup starts faster.

---

## Step 7: Verify the stanza

Run a check to make sure everything is still healthy after the backup.

```bash
pgbackrest --stanza=main check
```

```
Expected output (yours will differ):
P00   INFO: check command begin 2.54: ...
P00   INFO: check repo1 configuration (primary)
P00   INFO: check repo1 archive for WAL (primary)
P00   INFO: WAL segment ... successfully archived to ...
P00   INFO: check command end: completed successfully
```

Everything should report successfully. Exit the postgres user.

```bash
exit
```

---

## What you built

- Took your first full backup of the entire PostgreSQL cluster
- Learned to read the backup output and info report
- Explored the backup inside the repository
- Saw the compression savings (lz4 compression)

## Verification

Switch to the postgres user and confirm the backup exists.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main info
```

You should see one full backup listed with status `ok`. Note the backup label (something like `20260420-111500F`) - you'll need this in later guides.

```bash
exit
```

## What's next

In the next guide, you'll learn about differential and incremental backups - faster, smaller backups that only capture what changed since the last backup.
