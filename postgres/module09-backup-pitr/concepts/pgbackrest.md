# pgBackRest - Comprehensive Concepts Guide

A teaching reference for DBA students moving from pg_dump and pg_basebackup to
enterprise-grade backup management with pgBackRest.

---

## Table of Contents

1. [Why pgBackRest Exists](#1-why-pgbackrest-exists)
2. [Architecture](#2-architecture)
3. [Core Concepts](#3-core-concepts)
4. [Key Features](#4-key-features)
5. [How It Works - Under the Hood](#5-how-it-works---under-the-hood)
6. [Configuration Reference](#6-configuration-reference)
7. [Comparison Table](#7-comparison-table)
8. [Production Best Practices](#8-production-best-practices)
9. [Common Commands Quick Reference](#9-common-commands-quick-reference)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Why pgBackRest Exists

### The problem with manual backups

If you have completed Build Guides 05 and 06 in this lab, you have already felt
the pain of manual backup management:

- **pg_basebackup is single-threaded.** A 500 GB database takes hours to back up
  with one process copying files sequentially. You cannot parallelize it.
- **Manual WAL archiving is fragile.** A hand-rolled `archive_command` using
  `cp` or `rsync` gives you no compression, no verification, no retry logic.
  If the archive destination fills up or goes offline, WAL segments pile up on
  the primary and you risk running out of disk.
- **No incremental backups.** pg_basebackup always copies the entire data
  directory. Changed one row? Too bad - you are copying the full 500 GB again.
- **No built-in retention.** You write your own cron jobs to delete old backups.
  Miss a run and your disk fills. Delete too aggressively and you lose your
  recovery window.
- **No verification.** pg_basebackup does not validate page checksums during
  the copy. You may back up corrupted data and not know until restore time.
- **No encryption.** Backups sit on disk in plain text. Regulatory compliance
  (HIPAA, SOC2, PCI-DSS) requires encryption at rest.

### What pgBackRest fills

pgBackRest replaces your entire backup pipeline - archiving, base backups,
retention, and restore - with a single, purpose-built tool:

| Gap | pgBackRest Solution |
| --- | ------------------- |
| Single-threaded backup | Parallel backup and restore (configurable process count) |
| No compression control | Multiple algorithms: lz4, zstd, gzip, bzip2 |
| No incremental backups | Full, differential, incremental, and block-level incremental |
| No retention management | Automatic expiration by count or time |
| No verification | Page-level checksum validation during backup |
| No encryption | AES-256-CBC repository encryption |
| Local-only storage | S3, GCS, Azure, SFTP, and local filesystem |
| Fragile archive_command | Reliable archive-push with async mode and queue management |
| No resume on failure | Interrupted backups resume from where they stopped |

### Brief history

pgBackRest was created by David Steele, with the first public release around
2014. It was designed from the ground up specifically for PostgreSQL - not
adapted from a general-purpose backup tool. Key milestones:

- **2014** - Initial release, replacing custom Perl-based backup scripts
- **2019** - Rewritten from Perl to C for performance and reduced dependencies
- **2020** - Multi-repository support added
- **2022** - TLS server mode introduced (alternative to SSH)
- **2023** - Block-level incremental backup (v2.46)
- **2025** - Current stable release: v2.58.0

Today pgBackRest is the most widely used PostgreSQL backup tool. It is included
in the default package repositories for every major Linux distribution and is
the backup engine behind managed PostgreSQL services at Crunchy Data, AWS RDS
(internally), and many others.

---

## 2. Architecture

### Local backup setup

The simplest deployment. PostgreSQL and the backup repository live on the same
server. This is what you build in Build Guide 07.

```
+----------------------------------------------------------+
|                     pg-primary (NODE1)                    |
|                                                          |
|  +------------------+       +-------------------------+  |
|  |   PostgreSQL 16  |       |   pgBackRest Repository |  |
|  |                  |       |                         |  |
|  |  /opt/pgsql/data | ----> |  /opt/pgsql/backup/     |  |
|  |  /opt/pgsql/wal  |  WAL  |    pgbackrest/          |  |
|  |                  | push  |      archive/           |  |
|  |  archive_command |       |      backup/            |  |
|  |  = pgbackrest    |       |                         |  |
|  |    archive-push  |       |                         |  |
|  +------------------+       +-------------------------+  |
|                                                          |
|  pgbackrest.conf:                                        |
|    [main]                                                |
|    pg1-path=/opt/pgsql/data                              |
|    [global]                                              |
|    repo1-path=/opt/pgsql/backup/pgbackrest               |
+----------------------------------------------------------+
```

> **Concept:** A local repository is simple to set up but violates a
> fundamental backup rule - your backups live on the same machine as your data.
> If the server's storage fails, you lose both. Use local repos for dev/test
> or as one leg of a multi-repo strategy.

### Remote backup setup (dedicated backup server)

The production pattern. A dedicated backup server (repo host) stores all backups
and WAL archives. This is the architecture in our lab with NODE1 and NODE2.

```
+---------------------------+          +---------------------------+
|      pg-primary (NODE1)   |          |     pg-backup (NODE2)     |
|                           |   SSH    |                           |
|  PostgreSQL 16            |  or TLS  |  pgBackRest repo host     |
|  /opt/pgsql/data          | -------> |  /opt/pgsql/backup/       |
|  /opt/pgsql/wal           |          |    pgbackrest/            |
|                           |  backup  |      archive/             |
|  pgBackRest (pg host)     |  + WAL   |      backup/              |
|  archive_command =        | -------> |                           |
|    pgbackrest archive-push|          |  pgbackrest.conf:         |
|                           |          |    pg1-host=pg-primary    |
|  pgbackrest.conf:         |          |    pg1-path=/opt/pgsql/   |
|    repo1-host=pg-backup   |          |           data            |
|    repo1-path=...         |          |    repo1-path=...         |
+---------------------------+          +---------------------------+
```

> **Concept:** With a dedicated repo host, backup I/O does not compete with
> production queries. The repo host can have cheaper, larger storage optimized
> for sequential writes. If the primary dies, your backups are safe on a
> separate machine.

### Multi-repository setup (local + cloud)

pgBackRest can write to multiple repositories simultaneously. This gives you
fast local restores plus offsite disaster recovery.

```
+---------------------------+
|      pg-primary (NODE1)   |
|                           |
|  PostgreSQL 16            |
|  pgBackRest               |
|                           |
|  repo1 (local)            |--> /opt/pgsql/backup/pgbackrest/
|    retention-full=2       |      (fast restore, limited history)
|                           |
|  repo2 (S3)               |--> s3://company-pg-backups/main/
|    retention-full=4       |      (offsite DR, longer history)
|                           |
|  repo3 (GCS)              |--> gcs://pg-archive-bucket/main/
|    retention-full=8       |      (compliance archive, deep history)
|                           |
+---------------------------+

WAL archive-push --> writes to ALL repos simultaneously
Backups          --> scheduled per repo (can differ)
Restore          --> choose repo with --repo flag
```

> **Concept:** Each repository can have its own retention policy, compression
> settings, and encryption configuration. WAL archiving pushes to all repos
> automatically. If one repo is temporarily unavailable, async archiving queues
> the segments and retries.

### Data flow overview

```
                          archive-push
PostgreSQL WAL ---------------------------------> Repository
  (pg_wal/)           (compressed, checksummed)     archive/
                                                      stanza/
                                                        16-1/
                          backup command                  WAL files...
PostgreSQL PGDATA ------------------------------> Repository
  (base/, global/,    (parallel, compressed,        backup/
   pg_tblspc/, ...)    page-verified)                 stanza/
                                                        full/diff/incr
                          restore command
Repository ----------------------------------------> Target PGDATA
  backup/ + archive/  (parallel, delta-aware,        (recovered cluster)
                       checksummed)

                          archive-get
Repository ----------------------------------------> PostgreSQL
  archive/            (during recovery,              (pg_wal/)
                       replay WAL to target)
```

---

## 3. Core Concepts

### Stanza

A stanza is pgBackRest's name for a backup configuration that maps to one
PostgreSQL cluster. Think of it as a named profile that ties together:

- The path to a PostgreSQL data directory
- The repository location for that cluster's backups
- Retention rules, compression settings, and other options

**Naming conventions:** Name stanzas after the cluster's purpose, not its
hostname. Good names: `main`, `app`, `analytics`, `dw`. Bad names:
`pg-primary-01`, `ip-10-0-1-42` - these break when you failover or rebuild.

In our lab, the stanza is named `main`:

```ini
[main]
pg1-path=/opt/pgsql/data
```

You create a stanza once, then reference it in every command:

```bash
pgbackrest --stanza=main backup
pgbackrest --stanza=main info
pgbackrest --stanza=main restore
```

> **Note:** These are examples showing how the stanza name appears in every
> pgBackRest command. Do not run these now - you will run them step-by-step
> in Build Guide 07.

> **Concept:** The `stanza-create` command initializes the repository structure
> and writes metadata about the PostgreSQL cluster (version, system identifier).
> Always run `pgbackrest --stanza=main check` after creation to verify that
> archiving works end-to-end. You will do both in Build Guide 07.

### Repository

The repository is where pgBackRest stores backup data and WAL archives. It is
organized internally by stanza name, then by type (archive vs backup).

**Supported repository types:**

| Type | Config Value | Use Case |
| ---- | ------------ | -------- |
| Local filesystem | `posix` (default) | Dev/test, fast local restore |
| CIFS/SMB share | `cifs` | NAS-attached storage |
| Amazon S3 | `s3` | AWS cloud backups |
| Google Cloud Storage | `gcs` | GCP cloud backups |
| Azure Blob Storage | `azure` | Azure cloud backups |
| SFTP | `sftp` | Remote server without pgBackRest installed |

**Repository structure on disk:**

```
/opt/pgsql/backup/pgbackrest/          # repo1-path
  archive/
    main/                              # stanza name
      16-1/                            # PG major version - system id
        0000000100000000/              # timeline + WAL segment prefix
          000000010000000000000001-abc123.gz   # compressed WAL
          000000010000000000000002-def456.gz
  backup/
    main/                              # stanza name
      20260415-120000F/                # full backup (F suffix)
        backup.manifest                # file list, checksums, sizes
        pg_data/                       # backed up files
      20260416-060000F_20260416-180000D/   # diff (D suffix)
      20260416-060000F_20260417-060000I/   # incr (I suffix)
```

### Backup types

pgBackRest supports four backup types. Understanding the chain of dependencies
between them is critical for planning your retention policy.

**Full backup** - A complete, standalone copy of the entire PGDATA directory.
No dependencies on other backups. Largest size, longest duration, but simplest
to restore.

**Differential backup** - Contains all files that changed since the last full
backup. To restore: you need the full + the differential. Faster and smaller
than a full, but grows over time as more data changes.

**Incremental backup** - Contains only files that changed since the last backup
of any type (full, diff, or incr). Smallest and fastest, but creates a chain of
dependencies. To restore: you need the full + all intermediates up to the incr.

**Block-level incremental** (pgBackRest 2.46+) - Instead of copying entire
changed files, only the changed blocks within each file are stored. Enabled
with `repo-bundle=y` and `repo-block=y`. Dramatically reduces backup size for
large tables with small changes.

```
Backup Chain Dependencies
=========================

Day 1 (Sun)    Day 2 (Mon)    Day 3 (Tue)    Day 4 (Wed)    Day 5 (Thu)
+---------+    +---------+    +---------+    +---------+    +---------+
|  FULL   |    |  DIFF   |    |  DIFF   |    |  DIFF   |    |  DIFF   |
|  (F)    |    |  (D1)   |    |  (D2)   |    |  (D3)   |    |  (D4)   |
+---------+    +---------+    +---------+    +---------+    +---------+
    ^              |              |              |              |
    |              |              |              |              |
    +--------------+--------------+--------------+--------------+
    All diffs depend only on the last full

+---------+    +---------+    +---------+    +---------+    +---------+
|  FULL   |    |  INCR   |    |  INCR   |    |  INCR   |    |  INCR   |
|  (F)    |    |  (I1)   |    |  (I2)   |    |  (I3)   |    |  (I4)   |
+---------+    +---------+    +---------+    +---------+    +---------+
    ^              ^              ^              ^              |
    |              |              |              |              |
    +--------------+--------------+--------------+--------------+
    Each incr depends on the previous backup in the chain

Restore Wednesday's differential:   F + D3       (2 backups)
Restore Wednesday's incremental:    F + I1 + I2 + I3  (4 backups)
```

> **Concept:** Differentials are a balance between size and restore complexity.
> In production, a common pattern is: full weekly, differential daily,
> incremental hourly. You get fast hourly backups during the day, reasonable
> daily restore complexity, and a clean full baseline each week.

### WAL archiving

pgBackRest replaces your manual `archive_command` with its own `archive-push`
command. This gives you:

- **Compression** - WAL segments are compressed before storage (configurable
  algorithm and level)
- **Checksums** - Each segment is verified during the push
- **Parallel async mode** - Multiple WAL segments can be pushed simultaneously
  using a spool directory and background processes
- **Deduplication** - If the same WAL segment is pushed twice (e.g., after a
  PostgreSQL restart), pgBackRest detects the duplicate and skips it

PostgreSQL configuration (set in `postgresql.conf`):

```ini
wal_level = replica            # minimum for archiving
archive_mode = on              # enable WAL archiving
archive_command = 'pgbackrest --stanza=main archive-push %p'
```

**Async archiving** adds a queue between PostgreSQL and the repository:

```
PostgreSQL                    pgBackRest                    Repository
+-----------+    write     +---------------+    push     +----------+
| WAL       | ----------> | Spool dir     | ----------> | archive/ |
| pg_wal/   |  (fast,     | /var/spool/   |  (parallel, |          |
|           |   local)    |  pgbackrest/  |   async)    |          |
+-----------+             +---------------+             +----------+

archive_command returns SUCCESS as soon as WAL hits the spool.
Background processes handle the actual transfer to the repo.
```

> **Concept:** Async archiving is essential for high-throughput databases. If
> your database generates WAL faster than a single process can push it, the
> WAL directory fills up. Async mode decouples PostgreSQL from the transfer
> speed. Configure it with `archive-async=y` in the `[global:archive-push]`
> section.

### Backup manifest

Every backup contains a `backup.manifest` file - a JSON document that records:

- Every file in PGDATA with its path, size, timestamp, and SHA-1 checksum
- Tablespace locations and OIDs
- PostgreSQL version and system identifier
- Backup start/stop LSN and WAL segment range
- Compression type and level used
- Whether page checksums were validated

The manifest is how pgBackRest knows which files changed between backups
(for diff/incr), which files to verify during restore, and which files can
be preserved during a delta restore.

### Retention

Retention controls how many backups pgBackRest keeps before expiring old ones.
Three settings work together:

**`repo1-retention-full`** - How many full backups to retain. When a new full
backup completes and the count exceeds this number, the oldest full (and all
its dependent diffs/incrs) are expired.

- By count: `repo1-retention-full=2` keeps the 2 most recent full backups
- By time: `repo1-retention-full-type=time` with `repo1-retention-full=14`
  keeps full backups from the last 14 days

**`repo1-retention-diff`** - How many differential backups to retain within the
current full backup's set. `repo1-retention-diff=4` keeps the 4 most recent
diffs.

**`repo1-retention-archive`** - Controls WAL archive retention. WAL required by
any retained backup is never removed. Additional WAL beyond that is controlled
by this setting and `repo1-retention-archive-type`.

```
Retention Example: retention-full=2, retention-diff=3
=====================================================

Week 1 Full  --> kept (2nd most recent full)
  Mon Diff   --> expired (only 3 diffs kept per full set)
  Tue Diff   --> expired
  Wed Diff   --> kept (3rd most recent diff of this full's set)
  Thu Diff   --> kept
  Fri Diff   --> kept

Week 2 Full  --> kept (most recent full)
  Mon Diff   --> kept
  Tue Diff   --> kept (most recent diff overall)

Week 0 Full  --> EXPIRED (3rd full, exceeds retention-full=2)
  All diffs  --> EXPIRED (parent full is expired)
  WAL before Week 1 Full --> EXPIRED (no backup needs it)
```

> **Concept:** The `expire` command runs automatically after each successful
> backup. It never removes a backup that another backup depends on. You can
> also run it manually with `pgbackrest --stanza=main expire`.

### Delta restore

A standard restore wipes the target PGDATA directory and copies everything from
the backup. A delta restore is smarter - it computes the SHA-1 checksum of each
file in the target directory and compares it to the backup manifest. Files that
match are left in place. Only changed or missing files are copied.

Why this matters:

- **Speed** - If 90% of your files have not changed, a delta restore copies
  only 10% of the data
- **Restore into existing directory** - You do not need to rm -rf PGDATA first
- **Switchover scenarios** - After promoting a standby, you can delta-restore
  the old primary to rejoin as a standby without a full copy

Delta restore also removes files that exist in PGDATA but are not in the
backup manifest (e.g., temp files, leftover WAL).

You configure delta as the default in pgbackrest.conf with `delta=y` (as we
do in Build Guide 07) or pass `--delta` on the command line.

---

## 4. Key Features

### Parallel backup and restore

pgBackRest uses multiple processes for file compression and transfer. Each
process handles a different file, so large databases with many files benefit
significantly.

```ini
[global]
process-max=4    # use 4 parallel processes
```

Guidelines for setting `process-max`:

| Environment | Recommended | Reasoning |
| ----------- | ----------- | --------- |
| Dev/test | 1-2 | Limited CPU, small databases |
| Production (local repo) | 2-4 | Balance with production workload |
| Production (remote repo) | 4-8 | Network is usually the bottleneck |
| Dedicated backup server | 4-16 | Backup is the primary workload |
| SFTP repository | 4 | SFTP protocol overhead limits scaling |

> **Concept:** More processes is not always better. Each process needs CPU for
> compression and memory for buffering. On a busy production server, setting
> process-max too high steals resources from queries. Start with 2-4 and
> benchmark.

### Compression

pgBackRest compresses backup files and WAL archives. You choose the algorithm
based on your priorities:

| Algorithm | Config Value | Speed | Ratio | CPU Usage | Best For |
| --------- | ------------ | ----- | ----- | --------- | -------- |
| LZ4 | `lz4` | Fastest | Lower | Minimal | Large DBs, fast networks |
| Zstandard | `zst` | Fast | High | Moderate | Best overall balance |
| Gzip | `gz` (default) | Moderate | Good | Moderate | Compatibility, default |
| Bzip2 | `bz2` | Slow | Highest | High | Maximum compression, slow OK |
| None | `none` | N/A | 1:1 | None | Pre-compressed data, testing |

```ini
[global]
compress-type=zst         # algorithm for backups
compress-level=3          # balance speed vs ratio (zstd range: -7 to 22)

[global:archive-push]
compress-level=1          # faster compression for WAL (time-sensitive)
```

> **Concept:** You can set different compression levels for different commands.
> WAL archiving is time-sensitive (PostgreSQL waits for archive_command to
> return), so use a lower compress-level for archive-push. Backups are less
> time-critical, so you can afford higher compression. This is configured
> using command-level sections like `[global:archive-push]`.

### Page checksums

During backup, pgBackRest can validate PostgreSQL page-level checksums (if
enabled on the cluster with `initdb --data-checksums` or `pg_checksums`).
This catches corruption during the backup process - not after.

If pgBackRest detects a bad page checksum, it logs a warning but continues
the backup. The `info` command and backup manifest record which pages failed.

This is separate from PostgreSQL's `data_checksums` setting - pgBackRest reads
and verifies the checksums itself during the file copy.

### Resume

If a backup is interrupted (network failure, server reboot, out of memory),
pgBackRest can resume from where it stopped instead of starting over. The
manifest is saved periodically during backup (controlled by
`manifest-save-threshold`, default 1 GiB). On resume, files already copied
are verified by checksum and skipped if valid.

```ini
[global]
resume=y                        # enabled by default
manifest-save-threshold=512MiB  # save progress more frequently for large DBs
```

> **Concept:** Resume works by keeping the incomplete backup directory in the
> repository. The next backup attempt detects it and continues. If you need
> to abandon a failed backup and start fresh, the new backup will automatically
> clean up the incomplete one. Note: file bundles (when `repo-bundle=y`)
> cannot be resumed, so keep `repo-bundle-limit` reasonable.

### Encryption

pgBackRest encrypts the entire repository at rest using AES-256-CBC. Encryption
happens client-side before data leaves the pg host - even if your cloud
provider offers server-side encryption, pgBackRest encrypts independently.

```ini
[global]
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=a-very-long-random-passphrase-here
```

Important rules:

- Encryption is set once during `stanza-create`. You cannot change it later.
- The passphrase must be the same on all hosts that access the repository.
- If you lose the passphrase, your backups are unrecoverable. Store it in a
  secrets manager (Vault, AWS Secrets Manager, etc.).
- Encryption adds CPU overhead. Benchmark with and without to understand the
  impact on your backup window.

### Multi-repository

pgBackRest can write to up to four repositories simultaneously (repo1 through
repo4). Each repo is independently configured with its own:

- Storage type (local, S3, GCS, Azure, SFTP)
- Retention policy
- Compression settings
- Encryption settings

```ini
[global]
# Local repo for fast restores
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=4

# S3 repo for offsite DR
repo2-type=s3
repo2-s3-bucket=company-pg-backups
repo2-s3-region=us-east-1
repo2-s3-endpoint=s3.us-east-1.amazonaws.com
repo2-path=/main
repo2-retention-full=4
repo2-cipher-type=aes-256-cbc
repo2-cipher-pass=offsite-encryption-passphrase
```

WAL archive-push writes to all configured repos. Backups are per-repo - you
schedule them separately. Restore defaults to repo1 but you can choose with
`--repo=2`.

### Backup from standby

In production, you want to minimize I/O on the primary. pgBackRest can run the
backup against a standby server, reading data files from the replica while
coordinating start/stop backup with the primary.

```ini
[global]
backup-standby=y       # or 'prefer' to fall back to primary if standby is down

[main]
pg1-path=/opt/pgsql/data                    # primary
pg1-host=pg-primary
pg2-path=/opt/pgsql/data                    # standby
pg2-host=pg-standby
```

> **Concept:** The backup still needs brief communication with the primary
> (to call `pg_backup_start()` and `pg_backup_stop()`), but the heavy file
> copying happens from the standby. This is the recommended pattern for large
> production databases.

### Tablespace support

pgBackRest handles tablespace backup and restore transparently. During restore,
you can remap tablespaces to different directories:

```bash
pgbackrest --stanza=main \
  --tablespace-map=ts_data=/new/path/ts_data \
  --tablespace-map=ts_index=/new/path/ts_index \
  restore
```

Or put all tablespaces under one parent:

```bash
pgbackrest --stanza=main \
  --tablespace-map-all=/opt/pgsql/tablespaces \
  restore
```

### Link support

pgBackRest preserves and restores symbolic links. This matters for our lab
setup where `/opt/pgsql/wal` is a separate mount point symlinked from
`pg_wal` inside PGDATA.

Options for link handling during restore:

- `--link-all` - Restore all symlinks as they were in the backup
- `--link-map` - Remap specific links to new targets

```bash
pgbackrest --stanza=main \
  --link-map=pg_wal=/opt/pgsql/wal \
  restore
```

### Block-level incremental backup

Traditional incremental backups copy entire files that have any change.
A 1 GB table file with one changed page still copies the full 1 GB.

Block-level incremental (pgBackRest 2.46+, recommended 2.52.1+) divides files
into blocks and stores only the changed blocks. This provides dramatic space
savings for large tables with small update patterns.

```ini
[global]
repo1-bundle=y     # required - groups small files into bundles
repo1-block=y      # enable block-level incremental
```

```
Traditional incremental:              Block-level incremental:
+-----------+                         +-----------+
| 1 GB file |  1 page changed         | 1 GB file |  1 page changed
| COPY ALL  |  --> copies 1 GB        | COPY BLOCK|  --> copies 8 KB
+-----------+                         +-----------+
```

> **Concept:** Block-level incremental is one of pgBackRest's most impactful
> recent features. It makes hourly incremental backups practical even for
> multi-terabyte databases. The tradeoff is slightly more complex restore
> (pgBackRest must reconstruct files from blocks) and incompatibility with
> resume for bundled files.

---

## 5. How It Works - Under the Hood

### Backup process step by step

```
1. ACQUIRE ADVISORY LOCK
   pgBackRest acquires a lock to prevent concurrent backups.

2. CHECK CONFIGURATION
   Validates stanza config, PG version, system identifier.
   Compares against previous backups to detect cluster changes.

3. START BACKUP
   Calls pg_backup_start() on PostgreSQL (pg_start_backup on PG < 15).
   If start-fast=y, forces an immediate checkpoint.
   If start-fast=n, waits for the next natural checkpoint.

4. COPY FILES (parallel)
   Reads the file list from PGDATA.
   For full: copies all files.
   For diff: compares file timestamps/sizes against last full's manifest.
   For incr: compares against last backup's manifest (any type).
   Each process compresses and checksums files during transfer.
   Page checksums are validated if the cluster has them enabled.

5. STOP BACKUP
   Calls pg_backup_stop() on PostgreSQL.
   PostgreSQL switches to a new WAL segment and returns the
   backup label and tablespace map.

6. VERIFY AND SAVE MANIFEST
   pgBackRest writes the backup manifest with all file checksums.
   Verifies that the required WAL segments are in the archive.

7. EXPIRE OLD BACKUPS
   If expire-auto=y (default), runs the expire command to remove
   backups that exceed retention policy.
```

### WAL archive-push flow

```
PostgreSQL completes a WAL segment (16 MB by default)
         |
         v
archive_command = 'pgbackrest --stanza=main archive-push %p'
         |
         v
pgBackRest reads the WAL file from pg_wal/
         |
         v
Compresses with configured algorithm (default: gz)
         |
         v
Computes checksum for verification
         |
         v
Writes to repository: archive/<stanza>/<pg-version>/<WAL-path>/
         |
         v
Returns exit code 0 to PostgreSQL (success)

With async mode (archive-async=y):
- WAL is first copied to spool directory (fast, local)
- archive_command returns immediately
- Background process transfers from spool to repository
- Multiple segments are transferred in parallel
```

### WAL archive-get flow (during recovery)

```
PostgreSQL needs WAL segment for replay (recovery or standby)
         |
         v
restore_command = 'pgbackrest --stanza=main archive-get %f "%p"'
         |
         v
pgBackRest checks the repository for the requested segment
         |
         v
If found: decompress, verify checksum, write to pg_wal/
         |
         v
Return exit code 0 (PostgreSQL replays the segment)

If not found: return exit code 1 (PostgreSQL knows recovery is complete)
```

### Restore process step by step

```
1. VALIDATE
   Check that the target backup exists and is valid.
   Check that PGDATA is either empty or --delta is specified.

2. SELECT BACKUP
   By default, use the latest backup.
   Or select by --set=<backup-label> for a specific backup.
   For PITR, select the backup whose WAL range covers the target time.

3. CLEAN TARGET (if not delta)
   Remove all files from PGDATA.
   If --delta, compute checksums and keep matching files.

4. RESTORE FILES (parallel)
   For full backup: copy all files from the backup.
   For diff/incr: combine the full + chain of backups, copying each
   file from the most recent backup that contains it.
   Decompress and verify checksums during copy.

5. WRITE RECOVERY CONFIGURATION
   Write restore_command to postgresql.auto.conf:
     restore_command = 'pgbackrest --stanza=main archive-get %f "%p"'
   For PITR, also write:
     recovery_target_time = '<target>'
     recovery_target_action = 'promote'
   Create recovery.signal (PG 12+) or recovery.conf (PG < 12).

6. DONE
   PGDATA is ready. Start PostgreSQL - it enters recovery mode,
   replays WAL from the archive, and promotes when target is reached.
```

### PITR with pgBackRest

Point-in-time recovery lets you restore to any moment within your WAL archive
window. pgBackRest automates the process that you did manually in Build Guide 06.

```bash
# Restore to a specific time
pgbackrest --stanza=main --delta \
  --type=time \
  "--target=2026-04-17 14:30:00.000000+00" \
  --target-action=promote \
  restore
```

Flag breakdown:
- `--stanza=main` - identifies which PostgreSQL cluster to restore
- `--delta` - only restores files that differ from what is already on disk (faster than a full copy)
- `--type=time` - tells pgBackRest to stop WAL replay at a specific timestamp
- `--target=...` - the timestamp to recover to (must be quoted because of the space)
- `--target-action=promote` - automatically promote to read-write primary when recovery reaches the target
- `restore` - the pgBackRest command (always comes last)

Recovery target types:

| Type | Flag | Example | Use Case |
| ---- | ---- | ------- | -------- |
| Time | `--type=time` | `--target="2026-04-17 14:30:00+00"` | "Restore to just before the DROP" |
| LSN | `--type=lsn` | `--target="0/1A2B3C4D"` | Precise recovery point |
| Transaction ID | `--type=xid` | `--target="12345"` | Specific transaction |
| Named restore point | `--type=name` | `--target="before_migration"` | Pre-set recovery markers |
| Immediate | `--type=immediate` | (no target needed) | Restore to backup consistency point |
| Default | `--type=default` | (no target needed) | Replay all available WAL |

> **Concept:** PITR requires continuous WAL archiving. If there are gaps in
> your WAL archive (segments that were never pushed), recovery stops at the
> gap. This is why WAL archive monitoring is critical - see the Best Practices
> section below.

---

## 6. Configuration Reference

### pgbackrest.conf structure

The configuration file uses INI format with three levels of settings:

```ini
# STANZA SECTION - settings specific to one PostgreSQL cluster
[main]
pg1-path=/opt/pgsql/data

# GLOBAL SECTION - defaults for all stanzas
[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
compress-type=zst

# GLOBAL COMMAND SECTION - defaults for a specific command across all stanzas
[global:archive-push]
compress-level=1
process-max=2

# STANZA COMMAND SECTION - settings for a command on one stanza only
[main:backup]
process-max=4
```

Priority order (highest to lowest):
1. Command line flags
2. Stanza command section (`[main:backup]`)
3. Global command section (`[global:archive-push]`)
4. Stanza section (`[main]`)
5. Global section (`[global]`)

### PostgreSQL settings required

These must be set in `postgresql.conf` (or via ALTER SYSTEM):

```ini
# Minimum required for pgBackRest
wal_level = replica                  # 'logical' also works
archive_mode = on                    # enable archiving
archive_command = 'pgbackrest --stanza=main archive-push %p'

# Recommended
archive_timeout = 300                # force a WAL switch every 5 min (for low-traffic DBs)
```

### Common configuration patterns

**Pattern 1: Single server, local repository**

Simple setup for dev/test. Everything on one machine.

```ini
[main]
pg1-path=/opt/pgsql/data

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7

process-max=2
compress-type=lz4
start-fast=y
delta=y
log-level-console=info
log-level-file=detail

[global:archive-push]
compress-level=1
```

**Pattern 2: Dedicated backup server (SSH)**

Production pattern with backups on a separate host. Config on the pg host:

```ini
# /etc/pgbackrest/pgbackrest.conf on pg-primary

[main]
pg1-path=/opt/pgsql/data

[global]
repo1-host=pg-backup
repo1-host-user=pgbackrest
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7

process-max=4
compress-type=zst
start-fast=y
delta=y
log-level-console=info
log-level-file=detail

[global:archive-push]
compress-level=1
process-max=2
archive-async=y
```

Config on the repo host:

```ini
# /etc/pgbackrest/pgbackrest.conf on pg-backup

[main]
pg1-host=pg-primary
pg1-path=/opt/pgsql/data

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7

process-max=4
compress-type=zst
start-fast=y
delta=y
```

**Pattern 3: S3 remote repository**

Cloud-only backups. Good for ephemeral environments or when a dedicated backup
server is not available.

```ini
[main]
pg1-path=/opt/pgsql/data

[global]
repo1-type=s3
repo1-s3-bucket=company-pg-backups
repo1-s3-region=us-east-1
repo1-s3-endpoint=s3.us-east-1.amazonaws.com
repo1-path=/main
repo1-retention-full=4
repo1-retention-diff=14

repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=long-random-passphrase

repo1-bundle=y
repo1-block=y

process-max=4
compress-type=zst
start-fast=y
delta=y
```

> **Concept:** When using S3, enable `repo-bundle=y` to group small files into
> larger bundles. Object stores charge per API call, and a PostgreSQL data
> directory can have hundreds of thousands of small files. Bundling reduces
> both cost and backup time. Block-level incremental (`repo-block=y`) requires
> bundling to be enabled.

**Pattern 4: Multi-repository (local + remote)**

Belt and suspenders. Local repo for fast restore, S3 for disaster recovery.

```ini
[main]
pg1-path=/opt/pgsql/data

[global]
# Local repo - fast restore, short retention
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=4

# S3 repo - offsite DR, longer retention
repo2-type=s3
repo2-s3-bucket=company-pg-backups
repo2-s3-region=us-east-1
repo2-s3-endpoint=s3.us-east-1.amazonaws.com
repo2-path=/main
repo2-retention-full=8
repo2-retention-diff=30
repo2-cipher-type=aes-256-cbc
repo2-cipher-pass=offsite-encryption-passphrase
repo2-bundle=y
repo2-block=y

process-max=4
compress-type=zst
start-fast=y
delta=y
archive-async=y
```

---

## 7. Comparison Table

| Feature | pg_basebackup | pgBackRest | Barman |
| ------- | ------------- | ---------- | ------ |
| **Backup types** | Full only | Full, diff, incr, block-level incr | Full, incr (rsync) |
| **Parallel backup** | No | Yes (configurable process count) | Limited (parallel WAL) |
| **Parallel restore** | N/A (manual) | Yes | No |
| **Compression** | gzip only (client-side) | lz4, zstd, gzip, bzip2, none | gzip, bzip2 |
| **Encryption** | No | AES-256-CBC (client-side) | No (rely on filesystem) |
| **Incremental** | No | File-level and block-level | File-level (rsync) |
| **PITR** | Manual WAL management | Integrated (--type=time/lsn/xid) | Integrated |
| **Remote repos** | Stream to remote | S3, GCS, Azure, SFTP, SSH | SSH, S3 (via hooks) |
| **Multi-repo** | No | Up to 4 simultaneous repos | No |
| **Retention mgmt** | Manual | Automatic (count or time-based) | Automatic |
| **Backup verification** | No checksum validation | Page-level checksum validation | WAL verification |
| **Resume** | No | Yes | No |
| **Backup from standby** | Yes | Yes (with primary coordination) | Yes |
| **Delta restore** | N/A | Yes (checksum-based) | No |
| **Tablespace remap** | --tablespace-mapping | --tablespace-map | --tablespace |
| **WAL archiving** | Separate configuration | Integrated (archive-push/get) | Integrated |
| **Configuration** | Command-line flags | INI config file | INI config file |
| **Language** | C (part of PG core) | C | Python |
| **License** | PostgreSQL License | MIT | GPL-3.0 |

> **Concept:** pg_basebackup is great for initial standby setup and one-off
> backups. Barman is a solid tool with a long history. pgBackRest is purpose-
> built for production PostgreSQL backup management and has the most complete
> feature set. For managed backup infrastructure, pgBackRest is the standard
> choice.

---

## 8. Production Best Practices

### Backup schedule recommendations

| Backup Type | Frequency | Rationale |
| ----------- | --------- | --------- |
| Full | Weekly (Sunday night) | Clean baseline, no dependency chain |
| Differential | Daily (midnight) | Reasonable restore complexity (full + 1 diff) |
| Incremental | Hourly (on the hour) | Minimize data loss window, fast backups |

Example cron schedule (running as postgres user):

```cron
# Full backup - Sunday at 01:00
0 1 * * 0   pgbackrest --stanza=main --type=full backup

# Differential backup - Mon-Sat at 01:00
0 1 * * 1-6 pgbackrest --stanza=main --type=diff backup

# Incremental backup - every hour on the half-hour (skip 01:30 to avoid overlap)
30 0,2-23 * * * pgbackrest --stanza=main --type=incr backup
```

### Monitoring - what to watch

| Metric | Warning Threshold | Critical Threshold | How to Check |
| ------ | ----------------- | ------------------ | ------------ |
| Last full backup age | > 8 days | > 14 days | `pgbackrest info --output=json` |
| Last any backup age | > 2 hours | > 6 hours | `pgbackrest info --output=json` |
| WAL archive lag | > 100 segments | > 500 segments | `pg_stat_archiver` view |
| Archive failures | > 0 | > 5 | `pg_stat_archiver.failed_count` |
| Repo disk usage | > 70% | > 85% | `df -h <repo-path>` |
| Backup duration trend | > 2x baseline | > 4x baseline | Parse log files |

```sql
-- Check archiving health from PostgreSQL
SELECT archived_count, failed_count,
       last_archived_wal, last_archived_time,
       now() - last_archived_time AS archive_lag
FROM pg_stat_archiver;
```

### Test restores regularly

The most important backup practice: regularly restore backups to verify they
work. A backup you have never tested is a backup you cannot trust.

- **Weekly:** Automated restore to a test server, run `pg_isready` and basic
  query validation
- **Monthly:** Full PITR drill - restore to a random point in time, verify
  data integrity
- **Quarterly:** Full disaster recovery drill - simulate primary loss, restore
  on a fresh server, measure RTO

### The 3-2-1 rule for PostgreSQL

The 3-2-1 rule states:

- **3** copies of your data (production + 2 backups)
- **2** different storage media (local disk + object storage)
- **1** offsite copy (different region or cloud provider)

Applied with pgBackRest multi-repo:

```
Copy 1: Production database (pg-primary, local SSD)
Copy 2: repo1 - local or nearby server (fast restore, HDD OK)
Copy 3: repo2 - S3 in different region (offsite, encrypted)
```

### Sizing the backup repository

Rule of thumb estimates:

| Component | Size Estimate |
| --------- | ------------- |
| Full backup (compressed) | 30-50% of database size |
| Differential (1 day of changes) | 5-15% of database size |
| Incremental (1 hour of changes) | 0.5-3% of database size |
| WAL per day (moderate write load) | 2-10 GB |
| WAL per day (heavy write load) | 50-200 GB |

For a 500 GB database with `retention-full=2` and `retention-diff=7`:

```
2 full backups:     2 x 200 GB = 400 GB
7 differentials:    7 x 50 GB  = 350 GB
WAL (14 days):      14 x 10 GB = 140 GB
                                --------
Estimated total:                 890 GB

Add 30% buffer:                 ~1.2 TB repo size needed
```

> **Concept:** Block-level incremental (`repo-block=y`) can reduce incremental
> and differential sizes by 50-90% compared to file-level. If you are on
> pgBackRest 2.52+, enable it.

---

## 9. Common Commands Quick Reference

| Command | Description |
| ------- | ----------- |
| `pgbackrest stanza-create --stanza=main` | Initialize a new stanza in the repository |
| `pgbackrest check --stanza=main` | Validate config and test archiving end-to-end |
| `pgbackrest backup --stanza=main --type=full` | Take a full backup |
| `pgbackrest backup --stanza=main --type=diff` | Take a differential backup |
| `pgbackrest backup --stanza=main --type=incr` | Take an incremental backup |
| `pgbackrest backup --stanza=main` | Take a backup (default: incr) |
| `pgbackrest info --stanza=main` | Show backup details (sizes, times, WAL range) |
| `pgbackrest info --stanza=main --output=json` | JSON output (for scripts and monitoring) |
| `pgbackrest restore --stanza=main --delta` | Delta restore from latest backup |
| `pgbackrest restore --stanza=main --delta --type=time "--target=2026-04-17 14:30:00+00"` | PITR to specific time |
| `pgbackrest restore --stanza=main --delta --db-include=appdb` | Restore only one database |
| `pgbackrest restore --stanza=main --set=20260415-120000F` | Restore a specific backup |
| `pgbackrest restore --stanza=main --repo=2` | Restore from a specific repository |
| `pgbackrest expire --stanza=main` | Manually run retention expiration |
| `pgbackrest archive-push <path>` | Push a WAL segment (called by archive_command) |
| `pgbackrest archive-get <file> <path>` | Get a WAL segment (called by restore_command) |
| `pgbackrest stanza-upgrade --stanza=main` | Update stanza after PostgreSQL major upgrade |
| `pgbackrest stanza-delete --stanza=main --repo=1` | Delete a stanza from a specific repo |
| `pgbackrest annotate --stanza=main --set=<label> --annotation=key=value` | Add metadata to a backup |
| `pgbackrest version` | Show pgBackRest version |

**Common flags used with multiple commands:**

| Flag | Description |
| ---- | ----------- |
| `--stanza=<name>` | Target stanza (required for most commands) |
| `--repo=<n>` | Target repository number (default: 1) |
| `--log-level-console=detail` | Increase console verbosity for debugging |
| `--process-max=<n>` | Override parallel process count |
| `--dry-run` | Show what would happen without doing it (not all commands) |

---

## 10. Troubleshooting

### Common errors and solutions

**Error: `unable to find a valid repository`**

```
ERROR: [075]: unable to find a valid repository
```

Cause: No stanza has been created, or the repository path is wrong.
Fix: Run `pgbackrest --stanza=main stanza-create` and verify `repo1-path`
in pgbackrest.conf points to a directory the postgres user can write to.

---

**Error: `[ProtocolError] expected value '2.58'`**

```
ERROR: [ProtocolError] expected value '2.58' but got '2.53'
```

Cause: pgBackRest version mismatch between the pg host and the repo host.
Fix: Upgrade both hosts to the same version. Always upgrade repo host first,
then pg host.

---

**Error: `WAL segment not found in archive`**

```
ERROR: [044]: WAL segment 000000010000000000000005 was not archived
```

Cause: archive_command is not working, or PostgreSQL has not flushed WAL yet.
Fix:
1. Check `SELECT * FROM pg_stat_archiver;` for failures
2. Verify `archive_mode = on` and `archive_command` is set correctly
3. Run `pgbackrest --stanza=main check` to test archiving
4. Check pgBackRest logs in `/var/log/pgbackrest/`

---

**Error: `unable to acquire lock`**

```
ERROR: [055]: unable to acquire lock on file '/tmp/pgbackrest/main-backup.lock'
```

Cause: Another pgBackRest backup process is already running.
Fix: Wait for the running backup to complete, or if it crashed, investigate manually:

Check whether a lock file exists:
```bash
ls -la /tmp/pgbackrest/main-*.lock
```

Verify no pgbackrest processes are still running:
```bash
ps aux | grep pgbackrest
```

If no processes are running and the lock is stale, remove it:
```bash
rm /tmp/pgbackrest/main-backup.lock
```

---

**Error: `pg_control exists and PostgreSQL is running`**

Cause: Trying to restore while PostgreSQL is still running.
Fix: You must stop PostgreSQL before restoring.

Stop PostgreSQL first - you cannot restore into a running cluster:
```bash
sudo systemctl stop postgresql-16
```

Run the restore:
```bash
pgbackrest --stanza=main --delta restore
```

Start PostgreSQL after the restore completes:
```bash
sudo systemctl start postgresql-16
```

---

**Error: `archive-push queue max exceeded`**

```
WARN: WAL segment was dropped because archive-push-queue-max was exceeded
```

Cause: WAL is being generated faster than pgBackRest can archive it. The
queue limit was reached and WAL was DROPPED (not archived).
Fix:
1. Increase `archive-push-queue-max` or remove the limit
2. Increase `process-max` for archive-push
3. Investigate what is generating excessive WAL (large bulk loads?)
4. **WARNING**: Dropped WAL creates gaps that break PITR continuity

---

### How to verify backup integrity

> **Note:** These are individual reference commands for verifying backup
> integrity. Run them one at a time as needed - this is not a sequence to
> execute all at once.

List all backups with details (date, size, type, WAL range):
```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):
```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000005

        full backup: 20260415-120000F
            timestamp start/stop: 2026-04-15 12:00:00+00 / 2026-04-15 12:05:30+00
            wal start/stop: 000000010000000000000003 / 000000010000000000000003
            database size: 5.1GB, database backup size: 5.1GB
            repo1: backup set size: 1.1GB, backup size: 1.1GB
        ...
```

Get JSON output for scripting and monitoring tools:
```bash
pgbackrest --stanza=main info --output=json
```

Verify repository integrity - checks every file against its stored checksum (pgBackRest 2.36+):
```bash
pgbackrest --stanza=main verify
```

Expected output (yours will differ):
```
stanza: main
    status: ok
    archiveId: 16-1, total WAL checked: 5, total valid WAL: 5
    backup: 20260415-120000F, status: valid, total file checked: 1234, total valid file: 1234
```

Check a specific backup's manifest by its label:
```bash
pgbackrest --stanza=main info --set=20260415-120000F
```

Test restore without affecting production - restores to a temporary directory:
```bash
pgbackrest --stanza=main \
  --pg1-path=/tmp/pgbackrest-test \
  --delta restore
```

Check that the data directory was populated:
```bash
ls /tmp/pgbackrest-test/
```

Clean up the test directory when done:
```bash
rm -rf /tmp/pgbackrest-test/
```

### What to do when a backup fails

1. **Read the error message.** pgBackRest error messages are specific and
   usually tell you exactly what is wrong.

2. **Check the log file.** Console output is abbreviated. The full log is at
   `/var/log/pgbackrest/<stanza>-backup.log` with timestamps and detail.

3. **Run `check` first.** Before debugging the backup itself, verify the
   configuration is valid:
   ```bash
   pgbackrest --stanza=main check
   ```

4. **Increase log verbosity.** Re-run with detailed logging:
   ```bash
   pgbackrest --stanza=main --log-level-console=detail --type=full backup
   ```

5. **Verify connectivity.** For remote repos, test SSH or TLS connectivity:
   ```bash
   # SSH test
   ssh pgbackrest@pg-backup 'pgbackrest version'

   # S3 test - list the repo path
   pgbackrest --stanza=main --repo=2 info
   ```

6. **Check disk space.** Both the source (PGDATA) and destination (repo) need
   sufficient free space. Compression happens in memory, so the repo needs less
   space than the raw data, but temp files during backup need room.

7. **Retry.** If the failure was transient (network timeout, brief disk full),
   the backup will resume automatically thanks to the resume feature:
   ```bash
   pgbackrest --stanza=main --type=full backup
   ```

---

## Further Reading

- [pgBackRest Official Documentation](https://pgbackrest.org/)
- [pgBackRest User Guide](https://pgbackrest.org/user-guide.html)
- [pgBackRest Configuration Reference](https://pgbackrest.org/configuration.html)
- [pgBackRest GitHub Repository](https://github.com/pgbackrest/pgbackrest)
- Build Guide 07: `build/07-install-pgbackrest.md` - Install and configure pgBackRest in the lab
- Build Guide 08: `build/08-pgbackrest-operations.md` - Full/diff/incr backups, restore, and PITR operations
