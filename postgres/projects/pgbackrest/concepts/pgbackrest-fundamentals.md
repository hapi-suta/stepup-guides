# pgBackRest Fundamentals

A comprehensive reference for understanding pgBackRest - what it does, how it works, and why each piece matters. This document explains the concepts behind the commands. For step-by-step instructions, see the [BUILD guides](../build/).

---

## Table of Contents

1. [What Is pgBackRest?](#1-what-is-pgbackrest)
2. [Architecture](#2-architecture)
3. [Core Concepts](#3-core-concepts)
4. [How Backups Work](#4-how-backups-work)
5. [How WAL Archiving Works](#5-how-wal-archiving-works)
6. [How Restore Works](#6-how-restore-works)
7. [Retention and Expiration](#7-retention-and-expiration)
8. [Configuration Reference](#8-configuration-reference)
9. [Monitoring and Verification](#9-monitoring-and-verification)
10. [Troubleshooting Quick Reference](#10-troubleshooting-quick-reference)

---

## 1. What Is pgBackRest?

pgBackRest is an enterprise-grade backup and restore tool purpose-built for PostgreSQL. It manages the entire backup lifecycle - creating backups, compressing them, archiving WAL files, and restoring databases when things go wrong.

### What It Replaces

Without pgBackRest, DBAs typically cobble together a backup pipeline from several disconnected pieces:

| Manual Approach | Problem | pgBackRest Replacement |
|---|---|---|
| `pg_basebackup` scripts | No compression, no parallelism, no catalog | `pgbackrest backup` with built-in compression and catalog |
| `cp` or `rsync` as `archive_command` | No verification, no async queuing | `archive-push` with checksum verification |
| Custom retention scripts | Error-prone, miss dependency chains | Built-in retention with automatic expiration |
| Manual `pg_ctl stop` + copy + start | Downtime required | Hot backups with no downtime |
| Home-grown monitoring scripts | Incomplete, drift over time | `pgbackrest info` and `pgbackrest check` |

pgBackRest replaces all of these with a single binary and a single configuration file.

### Brief History

- **2014** - David Steele releases pgBackRest as an open-source Perl project
- **2019** - Complete rewrite from Perl to C for better performance and lower memory usage
- **Today** - pgBackRest is the most widely used PostgreSQL backup tool in production environments, supported by the PostgreSQL community and included in all major Linux distributions

> **Concept:** pgBackRest is not just a backup command - it is a backup *management system*. It tracks every file in every backup, verifies integrity with checksums, handles compression and parallelism, and maintains a catalog of all backups and archived WAL segments. This is why it replaces an entire pipeline, not just a single script.

---

## 2. Architecture

### Components

pgBackRest has three components:

1. **The binary** (`/usr/bin/pgbackrest`) - A single compiled C binary that handles all operations: backup, restore, archive-push, archive-get, check, info, stanza-create, and expire
2. **The configuration file** (`/etc/pgbackrest.conf`) - Tells pgBackRest where PostgreSQL lives and where to store backups
3. **The repository** (`/opt/pgsql/backup/pgbackrest`) - The directory where all backups and archived WAL files are stored

### Single-Server Architecture (This Lab)

In this lab, all three components live on the same server as PostgreSQL:

```
┌────────────────────────────────────────────────────────────────┐
│                       CentOS Stream 9                          │
│                                                                │
│  ┌──────────────────────┐       ┌───────────────────────────┐  │
│  │   PostgreSQL 16      │       │   pgBackRest Repository   │  │
│  │                      │       │                           │  │
│  │  PGDATA:             │       │  /opt/pgsql/backup/       │  │
│  │  /opt/pgsql/data     │       │    pgbackrest/            │  │
│  │                      │       │    ├── archive/           │  │
│  │  archive_command ──────────> │    │   └── main/          │  │
│  │   (archive-push)     │       │    │       └── 16-1/      │  │
│  │                      │       │    └── backup/            │  │
│  │  restore_command <────────── │        └── main/          │  │
│  │   (archive-get)      │       │            ├── (backups   │  │
│  │                      │       │            └── (manifests │  │
│  └──────────────────────┘       └───────────────────────────┘  │
│                                                                │
│  Config: /etc/pgbackrest.conf                                  │
│  Binary: /usr/bin/pgbackrest                                   │
└────────────────────────────────────────────────────────────────┘
```

### Multi-Server Architecture (Production)

In production, the repository often lives on a separate dedicated backup server. pgBackRest communicates over SSH or TLS. This lab uses the simpler single-server setup so you can focus on learning the tool without network complexity.

### Repository Structure

Inside the repository directory, pgBackRest organizes files by stanza:

```
/opt/pgsql/backup/pgbackrest/
├── archive/
│   └── main/                      <-- stanza name
│       └── 16-1/                  <-- PG version + system ID
│           ├── 0000000100000000/  <-- WAL timeline + segment range
│           │   ├── 000000010000000000000001-abc123.gz
│           │   ├── 000000010000000000000002-def456.gz
│           │   └── ...
│           └── 0000000200000000/  <-- new timeline after PITR
│               └── ...
└── backup/
    └── main/                      <-- stanza name
        ├── 20260420-100000F/      <-- full backup (F suffix)
        ├── 20260420-120000D/      <-- diff backup (D suffix)
        ├── 20260420-140000I/      <-- incr backup (I suffix)
        └── latest -> 20260420-140000I  <-- symlink to newest
```

> **Concept:** The stanza name appears everywhere in the repository structure. It is the organizing key that links a PostgreSQL cluster to its backups and archived WAL files. One pgBackRest installation can manage multiple stanzas (multiple PostgreSQL clusters), each with its own backup chain.

---

## 3. Core Concepts

### Stanza

A stanza is a named configuration that links pgBackRest to a specific PostgreSQL cluster. Think of it as a label. In this lab, the stanza is called `main`.

The stanza tells pgBackRest:
- Where PostgreSQL's data directory is (`pg1-path`)
- Which port PostgreSQL listens on (`pg1-port`)
- Where to store backups for this cluster (under `repo1-path/backup/main/`)
- Where to store archived WAL files (under `repo1-path/archive/main/`)

You create a stanza once with `pgbackrest stanza-create`. See [BUILD 02 - Configure Stanza](../build/02-configure-stanza.md).

### Repository

The repository is where pgBackRest stores everything - backups, WAL archives, and metadata. In this lab, it is a local directory: `/opt/pgsql/backup/pgbackrest`.

In production, repositories can also be:
- A remote server (accessed via SSH or TLS)
- Amazon S3
- Google Cloud Storage
- Azure Blob Storage

pgBackRest supports up to four repositories simultaneously (repo1 through repo4), so you can keep a local copy for fast restores and a cloud copy for disaster recovery.

### Backup Types

pgBackRest supports three backup types:

| Type | What It Copies | Depends On | Size | Speed | Use Case |
|---|---|---|---|---|---|
| **Full** | Every file in PGDATA | Nothing - self-contained | Largest | Slowest | Weekly baseline |
| **Differential** | Files changed since last **full** backup | The last full backup | Medium | Medium | Daily between fulls |
| **Incremental** | Files changed since last **any-type** backup | The entire chain back to last full | Smallest | Fastest | Multiple times per day |

> **Concept:** Differential backups always depend on the last full backup, no matter how many diffs you have taken. Incremental backups depend on the immediately previous backup (which could be full, diff, or another incr). This dependency chain matters during restore - pgBackRest must have every link in the chain or the restore will fail.

### Backup Manifest

Every backup includes a manifest file - a detailed inventory of every file that was backed up. The manifest records:

- File path, size, and modification time
- Checksum (SHA-256) of every file
- Whether the file was copied or referenced from a prior backup
- Tablespace mappings
- PostgreSQL version and system identifier

pgBackRest uses the manifest during restore to verify that every file is intact before applying it.

### WAL Archiving: archive-push vs archive-get

PostgreSQL writes all changes to WAL (Write-Ahead Log) files before applying them to data files. pgBackRest plugs into this system:

- **archive-push** - PostgreSQL calls this (via `archive_command`) every time a WAL segment is complete. pgBackRest compresses and stores it in the repository.
- **archive-get** - During restore, PostgreSQL calls this (via `restore_command`) to retrieve archived WAL segments from the repository and replay them.

These two commands form the continuous archiving pipeline that makes point-in-time recovery possible.

---

## 4. How Backups Work

### Full Backup Flow

When you run `pgbackrest backup --stanza=main --type=full`, here is what happens:

1. **Start checkpoint** - pgBackRest tells PostgreSQL to run a checkpoint, flushing all dirty pages from memory to disk
2. **Copy files** - pgBackRest reads every file in PGDATA and copies it to the repository, compressing each file along the way
3. **Page verification** - If PostgreSQL has data checksums enabled, pgBackRest verifies every page checksum during the copy (catching silent corruption)
4. **Stop checkpoint** - pgBackRest tells PostgreSQL the backup is complete
5. **Build manifest** - pgBackRest records checksums, sizes, and paths for every copied file
6. **Catalog entry** - The backup is registered in the repository catalog with a label like `20260420-100000F`

The entire process runs while PostgreSQL is online serving queries. There is no downtime.

### Differential and Incremental Flow

Differential and incremental backups follow the same steps, but in step 2, pgBackRest compares each file against the reference backup:

- **Differential** compares against the last **full** backup
- **Incremental** compares against the last backup of **any** type

Only files that have changed (different checksum or modification time) are copied. Unchanged files are referenced from the prior backup.

### The Dependency Chain

Understanding the dependency chain is critical for retention planning:

```
Monday       Tuesday     Wednesday   Thursday    Friday
  FULL ─────── DIFF ─────── DIFF ─────── DIFF ─────── DIFF
   │             │            │            │            │
   │             └─depends──> │            │            │
   │             └─depends────────────────>│            │
   │             └─depends───────────────────────────> │
   └─────────────────────all diffs depend on this full─┘
```

If you delete Monday's full backup, all four differential backups become useless - they only contain the changed files, not the complete database.

Incremental chains are even more fragile:

```
Monday       Tuesday     Wednesday   Thursday    Friday
  FULL ─────── INCR ─────── INCR ─────── INCR ─────── INCR
   │             │            │            │            │
   │             └──────────> │            │            │
   │                          └──────────> │            │
   │                                       └──────────>│
   └──────────────chain: each link depends on the previous─┘
```

If you lose Wednesday's incremental, you cannot restore Thursday's or Friday's.

> **Concept:** Differential backups are more resilient than incrementals because every diff only depends on the full. Losing any single diff does not affect the others. Incremental backups save more space but create a longer dependency chain where one broken link invalidates everything after it.

### Process Parallelism

pgBackRest can use multiple processes to copy files in parallel, controlled by the `process-max` setting. For a t3.small instance (2 vCPUs), `process-max=2` is appropriate. On larger servers with 8+ CPUs, you can increase this to 4-6 to significantly speed up backups.

### Compression Comparison

| Algorithm | Speed | Compression Ratio | CPU Usage | Best For |
|---|---|---|---|---|
| **lz4** | Very fast | Good (3-4x) | Low | Large databases, frequent backups |
| **zstd** | Fast | Very good (5-7x) | Medium | General production use |
| **gzip** | Slow | Good (4-5x) | High | Legacy compatibility |
| **none** | N/A | 1x (no compression) | None | Fast local storage, testing |

This lab uses `lz4` for the best balance of speed and compression on a small instance.

### Page Checksum Verification

If PostgreSQL was initialized with data checksums (`initdb --data-checksums`), pgBackRest verifies every data page during backup. This catches silent corruption - disk errors that flip bits without the operating system noticing. A backup tool that does not verify checksums might faithfully back up corrupted data, making the corruption permanent.

> **Concept:** Backups are not just about copying files. A backup that copies corrupted data is worse than useless - it gives you false confidence. pgBackRest's page verification during backup is one of its most important features because it catches problems while you still have time to fix them.

---

## 5. How WAL Archiving Works

### PostgreSQL's Archive Lifecycle

PostgreSQL generates WAL (Write-Ahead Log) files as it processes transactions. Each WAL file is exactly 16 MB. When a WAL file is full, PostgreSQL does two things:

1. Starts writing to a new WAL file
2. Calls the `archive_command` to send the completed file to archival storage

The `archive_command` is a shell command that PostgreSQL invokes with the path to the completed WAL file. If the command returns exit code 0, PostgreSQL considers the file archived. If it returns non-zero, PostgreSQL retries.

### How archive-push Works

In this lab, the `archive_command` is:

```
pgbackrest --stanza=main archive-push %p
```

When PostgreSQL calls this:

1. pgBackRest reads the WAL file from `pg_wal/`
2. Compresses it (using the configured algorithm)
3. Computes a checksum
4. Writes the compressed file to `repo1-path/archive/main/16-1/`
5. Returns exit code 0 to PostgreSQL

```
PostgreSQL                     pgBackRest                 Repository
    │                              │                          │
    │  WAL segment complete        │                          │
    │──── archive_command ────────>│                          │
    │                              │── read file ──>          │
    │                              │── compress ──>           │
    │                              │── checksum ──>           │
    │                              │── write ─────────────────>│
    │                              │                          │
    │<──── exit code 0 ───────────│                          │
    │                              │                          │
    │  (safe to recycle WAL file)  │                          │
```

### Async Archiving

By default, `archive-push` runs synchronously - PostgreSQL waits for the push to complete before continuing. For high-write workloads, this can create a bottleneck.

pgBackRest supports async archiving with `archive-push-queue-max`. When enabled, pgBackRest copies the WAL file to a local spool directory immediately (fast) and pushes it to the repository in the background. This decouples PostgreSQL's performance from the archiving speed.

### Why Continuous Archiving Enables PITR

Every transaction that modifies data is recorded in WAL. If you have:
- A base backup (full backup of all data files)
- Every WAL file generated after that backup

Then you can replay those WAL files to reconstruct the database at any point in time between the backup and the last archived WAL file. This is Point-in-Time Recovery (PITR), and it only works if the WAL archive has no gaps.

> **Concept:** A missing WAL file creates a gap that breaks the recovery chain. If PostgreSQL archived files 1, 2, 3, 5, 6 (but file 4 failed), you can only recover up to the end of file 3. Everything after the gap is unreachable. This is why monitoring `archive-push` failures is critical. See [SURVIVE 02 - Archive Command Broken](../survive/02-archive-command-broken/) and [SURVIVE 05 - WAL Accumulation](../survive/05-wal-accumulation/) for hands-on practice with archive failures.

---

## 6. How Restore Works

### Full Restore Flow

A restore replaces your PostgreSQL data directory with a backup. Here is the sequence:

1. **Stop PostgreSQL** - The database must be stopped before restoring
2. **Clear or delta PGDATA** - Either empty the data directory or use `--delta` to keep unchanged files
3. **Run `pgbackrest restore`** - pgBackRest copies backup files into PGDATA, decompressing along the way
4. **Write recovery signal** - pgBackRest creates `recovery.signal` (or `standby.signal`) and configures `restore_command` in `postgresql.auto.conf`
5. **Start PostgreSQL** - PostgreSQL enters recovery mode, replays WAL from the archive until it reaches the target
6. **Promote** - PostgreSQL exits recovery and opens for read-write connections

```
┌────────────┐      ┌──────────────┐      ┌─────────────┐
│ Stop PG    │ ──>  │ pgbackrest   │ ──>  │ Start PG    │
│            │      │ restore      │      │             │
│ systemctl  │      │              │      │ Enters      │
│ stop       │      │ Copies files │      │ recovery    │
│ postgresql │      │ from repo to │      │ mode,       │
│            │      │ PGDATA       │      │ replays WAL │
└────────────┘      └──────────────┘      └─────────────┘
```

### Delta Restore

A normal restore requires an empty PGDATA directory. A delta restore (`--delta`) is smarter - it compares each file in PGDATA against the backup manifest using checksums. Files that match are left in place. Only changed or missing files are copied from the repository.

Delta restore is faster when most files have not changed (common after a configuration mistake or minor corruption).

### Point-in-Time Recovery (PITR)

PITR lets you restore to a specific moment in time. The key flags:

```bash
pgbackrest restore --stanza=main \
  --type=time \
  --target="2026-04-20 14:30:00" \
  --target-action=promote
```

- `--type=time` - Tells pgBackRest to restore to a point in time (not just the backup)
- `--target="2026-04-20 14:30:00"` - The exact timestamp to recover to
- `--target-action=promote` - After reaching the target, promote to read-write

pgBackRest restores the closest backup before the target time, then PostgreSQL replays WAL files until it reaches the specified timestamp.

### Timeline Concept

Every time PostgreSQL recovers from a backup, it creates a new timeline. Timelines prevent confusion between the original history and the recovered history.

```
Timeline 1:  ──────────────────────────X (disaster at 14:45)
                                      │
                        PITR to 14:30 │
                                      │
Timeline 2:  ─────────────────────────┴────────────> (new history)
```

After PITR, your database is on Timeline 2. New WAL files are numbered differently so they never conflict with the original Timeline 1 WAL files still sitting in the archive.

> **Concept:** After performing PITR, always take a new full backup immediately. Your old backups are on Timeline 1, and your database is now on Timeline 2. The old backups cannot be used for incremental or differential backups going forward. See [BUILD 07 - Retention and Scheduling](../build/) for how to integrate post-PITR backups into your schedule. See [SURVIVE 06 - Wrong PITR Target](../survive/06-restore-wrong-target/) for practice with PITR recovery.

### The Critical Rule: Backup After PITR

This is worth repeating because it catches people off guard. After any PITR:

1. Your database is on a new timeline
2. Your old full backup is on the old timeline
3. Differential and incremental backups cannot span timelines
4. You **must** take a new full backup before your next scheduled diff/incr

If you forget this, your next scheduled differential backup will fail.

---

## 7. Retention and Expiration

### How Retention Works

Retention controls how many backups pgBackRest keeps. When a backup exceeds the retention count, pgBackRest automatically removes it (and its dependent WAL archives) during the `expire` command, which runs automatically at the end of every backup.

### Retention Settings

| Setting | Controls | Example | Meaning |
|---|---|---|---|
| `repo1-retention-full` | Full backups | `2` | Keep the 2 most recent full backups |
| `repo1-retention-diff` | Differential backups | `7` | Keep the 7 most recent diff backups |
| `repo1-retention-full-type` | Count vs time | `count` or `time` | Count-based (default) or days-based |

### Count-Based vs Time-Based

**Count-based** (default): Keep N full backups. Simple to reason about.

```ini
repo1-retention-full=2
repo1-retention-full-type=count
```

This keeps exactly 2 full backups. When the 3rd full backup completes, the oldest full (and all its dependent diffs/incrs and WAL) is automatically deleted.

**Time-based**: Keep all full backups newer than N days.

```ini
repo1-retention-full=14
repo1-retention-full-type=time
```

This keeps all full backups taken within the last 14 days.

### Expiration Dependency Chain

When pgBackRest expires a full backup, it also removes:
- All differential backups that depend on that full
- All incremental backups in that chain
- All WAL files that are only needed by the expired backups

pgBackRest never removes a WAL file that is still needed by a surviving backup.

```
EXPIRE retention-full=2:

  Full-1 (oldest)  ── Diff-A ── Diff-B    <-- ALL removed
  Full-2           ── Diff-C ── Diff-D    <-- KEPT
  Full-3 (newest)                          <-- KEPT
```

### The Danger of retention=1

With `repo1-retention-full=1`, you have exactly one full backup at all times. During the window when a new full backup is running:

- The old full backup is your only safety net
- If the new backup fails, you still have one
- When the new backup completes, the old one is immediately expired

But if your single backup is corrupted and you do not know it, you have zero good backups. There is no fallback.

> **Concept:** retention-full=1 means "one backup, zero margin." In production, always use retention-full=2 or higher. The extra storage cost is trivial compared to the risk of having no recoverable backup. See [SURVIVE 04 - Backup Expiry Crisis](../survive/04-backup-expiry-crisis/) for a scenario where aggressive retention causes problems.

### Recommended Retention Strategies

| Environment | Full Retention | Diff Retention | Backup Schedule | Recovery Window |
|---|---|---|---|---|
| **Development** | 1 full | N/A (full only) | Weekly full | Up to 7 days |
| **Staging** | 2 full | 7 diff | Weekly full, daily diff | Up to 14 days |
| **Production** | 4 full | 14 diff | Weekly full, daily diff | Up to 28 days |
| **Compliance** | time-based 90 days | 30 diff | Weekly full, daily diff | Up to 90 days |

---

## 8. Configuration Reference

### Configuration File Location

pgBackRest reads its configuration from `/etc/pgbackrest.conf`. The file uses INI format with sections.

### File Format

```ini
[global]
# Repository and general settings
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7

# Performance
process-max=2
compress-type=lz4
compress-level=1

# Logging
log-level-console=info
log-level-file=detail

[main]
# Stanza: links pgBackRest to this PostgreSQL cluster
pg1-path=/opt/pgsql/data
pg1-port=5432
```

### [global] Section - Repository and General Settings

Settings in `[global]` apply to all stanzas.

| Parameter | Description | Recommended (This Lab) | Production |
|---|---|---|---|
| `repo1-path` | Repository directory path | `/opt/pgsql/backup/pgbackrest` | Remote/S3 path |
| `repo1-retention-full` | Number of full backups to keep | `2` | `4` |
| `repo1-retention-diff` | Number of diff backups to keep | `7` | `14` |
| `process-max` | Parallel processes for backup/restore | `2` | `4-6` |
| `compress-type` | Compression algorithm | `lz4` | `zstd` |
| `compress-level` | Compression level (algorithm-specific) | `1` | `3` |
| `log-level-console` | Console log verbosity | `info` | `info` |
| `log-level-file` | File log verbosity | `detail` | `detail` |
| `start-fast` | Request immediate checkpoint at backup start | `y` | `y` |
| `archive-push-queue-max` | Max WAL queue size before blocking | (not set) | `4GB` |

### [stanza] Section - PostgreSQL Cluster Settings

Each stanza gets its own section, named by the stanza name (e.g., `[main]`).

| Parameter | Description | This Lab |
|---|---|---|
| `pg1-path` | Path to PostgreSQL data directory (PGDATA) | `/opt/pgsql/data` |
| `pg1-port` | PostgreSQL port number | `5432` |
| `pg1-socket-path` | Unix socket directory (if non-default) | (not needed) |
| `pg1-user` | PostgreSQL user for connections | (defaults to OS user) |

### Common Configuration Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Wrong `pg1-path` | `stanza-create` or `check` fails with "path not found" | Verify with `cat pgbackrest.conf` and `ls -la /opt/pgsql/data` |
| Repo directory does not exist | Backup fails with "unable to create path" | `mkdir -p /opt/pgsql/backup/pgbackrest` and `chown postgres:postgres` |
| Wrong ownership on repo | Backup fails with "permission denied" | `chown -R postgres:postgres /opt/pgsql/backup/pgbackrest` |
| Wrong ownership on config | pgBackRest fails to read config | `chown postgres:postgres /etc/pgbackrest.conf` |
| Missing `[global]` section | Settings silently ignored | Ensure section header exists |
| Tab characters in config | Parse error | Use spaces, not tabs |

See [SURVIVE 01 - Stanza Misconfigured](../survive/01-stanza-misconfigured/) for hands-on practice diagnosing and fixing configuration problems.

---

## 9. Monitoring and Verification

### pgbackrest check

The `check` command validates that:
- The configuration is correct
- pgBackRest can connect to PostgreSQL
- WAL archiving is working (it forces a WAL switch and verifies the file arrives in the archive)

```bash
sudo -u postgres pgbackrest --stanza=main check
```

If this command returns exit code 0, your archiving pipeline is healthy. Run this after any configuration change.

### pgbackrest info

The `info` command shows your complete backup inventory:

```bash
sudo -u postgres pgbackrest --stanza=main info
```

This shows:
- Stanza status (ok, error, or missing stanza)
- Each backup: label, type, timestamp, size, database size, repository size
- WAL archive: min/max archived WAL segments

For JSON output (useful for scripting and monitoring tools):

```bash
sudo -u postgres pgbackrest --stanza=main info --output=json
```

### pg_stat_archiver

PostgreSQL tracks archiving statistics in the `pg_stat_archiver` system view:

```sql
SELECT archived_count,
       last_archived_wal,
       last_archived_time,
       failed_count,
       last_failed_wal,
       last_failed_time
FROM pg_stat_archiver;
```

| Column | What to Watch For |
|---|---|
| `archived_count` | Should increase steadily during write activity |
| `failed_count` | Should be 0. Any non-zero value means WAL archiving has failed at some point |
| `last_archived_time` | Should be recent. If it is hours old during active writes, archiving is stalled |
| `last_failed_time` | If recent, investigate immediately |

### What to Monitor in Production

| Metric | Warning Threshold | Critical Threshold | Diagnostic Command |
|---|---|---|---|
| Last backup age | > 25 hours | > 49 hours | `pgbackrest info --output=json` |
| Backup size trend | > 20% growth week-over-week | > 50% growth | Compare `info` output over time |
| WAL archive lag | > 100 pending files | > 1000 pending files | `ls pg_wal/ \| wc -l` |
| Failed archives | Any non-zero | Growing count | `SELECT failed_count FROM pg_stat_archiver;` |
| Repository disk usage | > 80% | > 90% | `df -h /opt/pgsql/backup` |
| Backup duration trend | > 2x baseline | > 4x baseline | Parse `pgbackrest info` timestamps |

> **Concept:** The most dangerous backup failure is a silent one. If your backup fails but nobody notices for three days, you may have no usable backup when disaster strikes. Automated monitoring of backup age and archive health is not optional in production - it is the difference between a recoverable incident and a data loss event. See [USE 01 - Backup Inventory](../use/01-backup-inventory.md) and [USE 02 - WAL Archiving Health](../use/02-wal-archiving-health.md) for practice reading and interpreting these metrics.

### Setting Up Alerts

At minimum, set up automated checks for:

1. **Backup age** - Run `pgbackrest info --output=json` daily and parse the last backup timestamp. Alert if it is older than your backup schedule interval + buffer.
2. **Archive failures** - Query `pg_stat_archiver` for `failed_count > 0`.
3. **Disk space** - Monitor the repository filesystem usage.

A simple cron-based check:

```bash
# Check if last backup is older than 25 hours (86400 + 3600 seconds)
LAST_BACKUP=$(sudo -u postgres pgbackrest --stanza=main info --output=json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['backup'][-1]['timestamp']['stop'])")
```

---

## 10. Troubleshooting Quick Reference

### Common Problems

| Symptom | Likely Cause | Diagnostic Command | Fix |
|---|---|---|---|
| `stanza-create` fails with "pg1-path does not exist" | Wrong `pg1-path` in config | `cat /etc/pgbackrest.conf` | Fix path to match actual PGDATA location |
| `stanza-create` fails with "unable to create path" | Repo directory missing or wrong permissions | `ls -la /opt/pgsql/backup/` | `mkdir -p` and `chown postgres:postgres` |
| `backup` fails with "permission denied" | Repo or PGDATA not owned by postgres | `ls -la /opt/pgsql/backup/pgbackrest/` | `chown -R postgres:postgres` on the repo |
| `archive-push` fails continuously | Wrong `archive_command` in PostgreSQL | `SHOW archive_command;` inside psql | `ALTER SYSTEM SET archive_command = '...'` then reload |
| `archive-push` fails with "WAL file not found" | PostgreSQL recycled the WAL before push | Check `pg_stat_archiver` for failures | Investigate disk pressure, increase `wal_keep_size` |
| `check` fails with "WAL segment not archived" | Archiving pipeline broken | `SELECT * FROM pg_stat_archiver;` | Check archive_command, repo permissions, disk space |
| `restore` fails with "PGDATA is not empty" | Forgot to clear data directory | `ls /opt/pgsql/data/` | Use `--delta` flag or clear PGDATA manually |
| `restore` says "backup not found" | Wrong stanza name or empty repo | `pgbackrest info` | Verify stanza name, check repo directory |
| PITR misses target data | Target timestamp too early or too late | Check INSERT timestamps in your marker table | Re-restore with corrected `--target` |
| Backup size suddenly much larger | Table bloat or new large table loaded | Compare `info` output across backups | Investigate with `pg_size_pretty()` |
| Expiration removes too many backups | Retention set too low | `cat /etc/pgbackrest.conf` | Increase `repo1-retention-full` |

### Log Files

pgBackRest writes detailed logs to `/var/log/pgbackrest/`. Each operation gets its own log file:

```bash
# List recent log files
ls -lt /var/log/pgbackrest/

# View the most recent backup log
cat /var/log/pgbackrest/main-backup-*.log | tail -50
```

Log levels (from least to most verbose): `off`, `error`, `warn`, `info`, `detail`, `debug`, `trace`.

For troubleshooting, temporarily increase console log level:

```bash
sudo -u postgres pgbackrest --stanza=main --log-level-console=detail check
```

### Emergency Checklist

If backups are broken and you need to fix them fast:

1. **Check the config**: `cat /etc/pgbackrest.conf`
2. **Check the stanza**: `sudo -u postgres pgbackrest --stanza=main check`
3. **Check archiving**: `SELECT * FROM pg_stat_archiver;` in psql
4. **Check permissions**: `ls -la /opt/pgsql/backup/pgbackrest/`
5. **Check disk space**: `df -h /opt/pgsql/backup`
6. **Check logs**: `ls -lt /var/log/pgbackrest/ | head -5`
7. **Take a manual backup**: `sudo -u postgres pgbackrest --stanza=main backup --type=full`

> **Concept:** When troubleshooting backup issues, work from the outside in. Start with configuration (is it pointed at the right place?), then connectivity (can pgBackRest talk to PostgreSQL?), then archiving (are WAL files flowing?), then the backup itself. Most problems are configuration or permission issues, not software bugs.

---

## Cross-Reference Guide

| Topic | Where to Learn More |
|---|---|
| Installing pgBackRest | [BUILD 01 - Install pgBackRest](../build/01-install-pgbackrest.md) |
| Creating a stanza | [BUILD 02 - Configure Stanza](../build/02-configure-stanza.md) |
| Setting up WAL archiving | [BUILD 03 - WAL Archiving](../build/03-wal-archiving.md) |
| Taking a full backup | [BUILD 04 - Full Backup](../build/04-full-backup.md) |
| Reading backup inventory | [USE 01 - Backup Inventory](../use/01-backup-inventory.md) |
| Checking archive health | [USE 02 - WAL Archiving Health](../use/02-wal-archiving-health.md) |
| Broken stanza config | [SURVIVE 01 - Stanza Misconfigured](../survive/01-stanza-misconfigured/) |
| Archive command failures | [SURVIVE 02 - Archive Command Broken](../survive/02-archive-command-broken/) |
| Repository corruption | [SURVIVE 03 - Repo Corruption](../survive/03-repo-corruption/) |
| Retention/expiry problems | [SURVIVE 04 - Backup Expiry Crisis](../survive/04-backup-expiry-crisis/) |
| WAL buildup on disk | [SURVIVE 05 - WAL Accumulation](../survive/05-wal-accumulation/) |
| PITR gone wrong | [SURVIVE 06 - Wrong PITR Target](../survive/06-restore-wrong-target/) |
| Full cluster recovery | [SURVIVE 07 - Full Cluster Recovery](../survive/07-full-cluster-recovery/) |
| Backup verification | [SURVIVE 08 - Verification Failure](../survive/08-backup-verification-failure/) |
