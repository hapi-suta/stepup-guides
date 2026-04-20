# USE Exercise 01 - Backup Inventory

| | |
|---|---|
| **Time** | 20 minutes |
| **What you'll practice** | Reading pgBackRest info output, understanding backup chains, checking WAL archives, and answering real questions your manager will ask |
| **Prerequisites** | Completed BUILD guides 01-05 (pgBackRest installed, stanza created, full + diff/incr backups taken) |

---

## The Scenario

Your manager walks over and asks:

> "What's our current backup situation? How far back can we recover if something goes wrong?"

You need to answer confidently - with evidence. Let's gather that evidence now.

---

## Exercise 1: Get the Full Backup Report

Run the `pgbackrest info` command. This is the single most important command for understanding your backup state.

Switch to the postgres user first.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/00000001000000000000000F

        full backup: 20260420-100000F
            timestamp start/stop: 2026-04-20 10:00:00+00 / 2026-04-20 10:02:30+00
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 838.2MB, database backup size: 838.2MB
            repo1: backup set size: 112.5MB, backup size: 112.5MB

        diff backup: 20260420-100000F_20260420-140000D
            timestamp start/stop: 2026-04-20 14:00:00+00 / 2026-04-20 14:00:45+00
            wal start/stop: 00000001000000000000000A / 00000001000000000000000A
            database size: 838.5MB, database backup size: 8.3MB
            repo1: backup set size: 112.8MB, backup size: 1.2MB
...
```

Take a moment to read every line. Here is what each field means:

- **stanza: main** - The backup configuration name. Think of it as a label for this server's backup set.
- **status: ok** - pgBackRest can connect to PostgreSQL and the repository is healthy.
- **cipher: none** - Backups are not encrypted. In production, you would enable encryption.
- **wal archive min/max** - The oldest and newest WAL file in the archive. This defines your recovery window.
- **full backup: 20260420-100000F** - The backup label. The `F` at the end means "full."
- **timestamp start/stop** - When the backup started and finished.
- **wal start/stop** - Which WAL files the backup spans. You need these WAL files (plus any after them) to restore.
- **database size** - The actual size of the database at backup time.
- **database backup size** - How much data was actually backed up. For a full backup, this matches database size. For diff/incr, it is only the changed data.
- **repo1: backup set size** - The compressed size of the full backup set in the repository.
- **repo1: backup size** - The compressed size of just this backup's data in the repository.

> **Concept: Full vs Diff vs Incr Labels**
> Look at the backup label endings: `F` = full, `D` = differential, `I` = incremental. A diff backup label always starts with its parent full backup label, showing the chain relationship.

---

## Exercise 2: Count Your Backups

Look at the output from Exercise 1 and answer these questions. Write your answers down.

**Question A:** How many full backups do you have?

Count every line that says `full backup:`. Each full backup is an independent starting point for recovery.

**Question B:** How many differential backups do you have?

Count every line that says `diff backup:`. Each diff backup depends on its parent full backup.

**Question C:** How many incremental backups do you have?

Count every line that says `incr backup:`. Each incr backup depends on the previous backup in the chain (which could be a full, diff, or another incr).

> **Concept: Backup Chains**
> A full backup stands alone. A diff backup needs its parent full. An incr backup needs EVERY backup in the chain back to the full. Longer chains = more files needed for restore = more risk. That is why you take regular full backups.

---

## Exercise 3: Find Your Recovery Window

Using the info output, answer these two questions:

**Question A:** What is the OLDEST point you could recover to?

Look at the first full backup's `timestamp start` value. That is the earliest point in time you can reach. You cannot recover to any time before your oldest backup.

**Question B:** What is the NEWEST point you could recover to?

Look at the `wal archive max` value. That represents the most recent WAL file archived. You can recover up to the end of that WAL file - which is very close to "right now."

To see the exact timestamp of the most recent archived WAL, connect to PostgreSQL. You should still be the postgres user from Exercise 1. If not, run `sudo -i -u postgres` first.

```bash
psql
```

Then run this query:

```sql
SELECT last_archived_wal, last_archived_time FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
     last_archived_wal      |       last_archived_time
----------------------------+-------------------------------
 00000001000000000000000F   | 2026-04-20 15:42:18.293847+00
(1 row)
```

Exit psql:

```sql
\q
```

The `last_archived_time` tells you the most recent point you could recover to. If the database crashed RIGHT NOW, you could recover up to that timestamp.

---

## Exercise 4: Calculate Compression Ratio

pgBackRest compresses backups by default. Let's see how effective that compression is.

From the info output, find these two numbers for your full backup:

- **database size** (the uncompressed database size)
- **repo1: backup set size** (the compressed size in the repository)

Now calculate:

```
Compression ratio = database size / repo backup set size
```

For the example output above: 838.2 MB / 112.5 MB = **7.45x compression**

> **Concept: Compression Saves Storage**
> pgBackRest uses lz4 compression by default (or zst/gz depending on configuration). A 7x compression ratio means your 838 MB database only takes about 112 MB of backup storage. This matters when you have terabytes of data and weeks of retention.

**Question:** What is YOUR compression ratio? Is it higher or lower than 7x? Databases with lots of text compress better than databases with lots of binary data.

---

## Exercise 5: Inspect the WAL Archive

WAL (Write-Ahead Log) files are the continuous stream of changes that PostgreSQL writes. pgBackRest archives these so you can replay them during recovery.

List the archive directory. You should still be the postgres user. If not, run `sudo -i -u postgres` first.

```bash
ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/0000000100000000/
```

Expected output (yours will differ):

```
000000010000000000000001.00000028.backup
000000010000000000000001-abc123def456.gz
000000010000000000000002-789abc012def.gz
000000010000000000000003-345678901abc.gz
...
```

Count how many WAL files are archived. The `|` (pipe) sends the output of the first command as input to the second.

```bash
ls /opt/pgsql/backup/pgbackrest/archive/main/16-1/0000000100000000/ | grep -c ".gz"
```

Expected output (yours will differ):

```
15
```

Each `.gz` file is a compressed WAL segment. Each uncompressed WAL file is exactly 16 MB. These are the files that make point-in-time recovery possible - they contain every change made to the database.

> **Concept: WAL Is Your Safety Net**
> Backups give you a starting point. WAL files fill in the gap between that starting point and your recovery target. Without WAL archiving, you can only recover to the exact moment a backup finished. With WAL archiving, you can recover to any second between the backup and the last archived WAL.

---

## Exercise 6: Check the Logs

Every pgBackRest operation writes to a log file. Let's see what happened last.

List the pgBackRest log directory:

```bash
ls -lt /opt/pgsql/log/ | grep pgbackrest
```

Expected output (yours will differ):

```
-rw-r----- 1 postgres postgres  12847 Apr 20 14:00 pgbackrest-backup.log
-rw-r----- 1 postgres postgres   4521 Apr 20 10:02 pgbackrest-stanza-create.log
-rw-r----- 1 postgres postgres   2103 Apr 20 09:55 pgbackrest-check.log
```

Look at the most recent backup log:

```bash
tail -20 /opt/pgsql/log/pgbackrest-backup.log
```

Expected output (yours will differ):

```
2026-04-20 14:00:45.123 P00   INFO: diff backup size = 8.3MB, file total = 1247
2026-04-20 14:00:45.456 P00   INFO: new backup label = 20260420-100000F_20260420-140000D
2026-04-20 14:00:45.789 P00   INFO: diff backup command end: completed successfully
...
```

This tells you:
- **When** the last backup ran (the timestamp)
- **What type** it was (diff, full, incr)
- **Whether it succeeded** ("completed successfully")
- **How much data** was backed up

> **Concept: Always Check the Logs**
> The `pgbackrest info` command shows you the end result. The log files show you what happened along the way. When something goes wrong, the log file is where you find out why.

Exit the postgres user session.

```bash
exit
```

---

## Exercise 7: Answer Your Manager

Now you have all the information. Write a short summary as if you were replying to your manager. It should include:

1. **Number of backups:** "We have X full backups and Y differential backups."
2. **Recovery window:** "We can recover to any point between [oldest backup timestamp] and [latest archived WAL timestamp]."
3. **Storage efficiency:** "Our database is X MB but only uses Y MB of backup storage (Zx compression)."
4. **Archiving status:** "WAL archiving is active. The last WAL was archived at [timestamp]."
5. **Last backup:** "The most recent backup completed at [timestamp] and was a [type] backup."

Practice writing this summary. In a real job, you will need to give this kind of report regularly.

---

## What You Learned

- How to read and interpret `pgbackrest info` output
- How to identify full, differential, and incremental backups
- How to determine your recovery window (oldest and newest recovery points)
- How to calculate backup compression ratios
- How to inspect the WAL archive directory
- How to check pgBackRest log files for operation history
- How to communicate backup status to non-technical stakeholders
