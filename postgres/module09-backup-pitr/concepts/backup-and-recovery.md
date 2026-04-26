# PostgreSQL Backup and Recovery - Concepts Guide

Before you touch a single command in the BUILD guides, read through this. It gives you the mental model for everything you are about to do - the "why" behind every tool, setting, and recovery technique. When you get into the labs, the commands will make sense because you already understand how the pieces fit together.

---

## Table of Contents

1. [Why Backups Exist - The Problem They Solve](#1-why-backups-exist---the-problem-they-solve)
2. [Backup Architecture](#2-backup-architecture)
3. [Core Concepts](#3-core-concepts)
4. [Logical Backups - pg_dump and pg_restore](#4-logical-backups---pg_dump-and-pg_restore)
5. [Physical Backups - WAL Archiving and pg_basebackup](#5-physical-backups---wal-archiving-and-pg_basebackup)
6. [Point-in-Time Recovery (PITR)](#6-point-in-time-recovery-pitr)
7. [Configuration Reference](#7-configuration-reference)
8. [Logical vs Physical - When to Use Each](#8-logical-vs-physical---when-to-use-each)
9. [Production Best Practices](#9-production-best-practices)
10. [Common Commands Quick Reference](#10-common-commands-quick-reference)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Why Backups Exist - The Problem They Solve

Databases fail. Hardware dies, humans make mistakes, software has bugs. The question is never "will you lose data?" but "how much data can you afford to lose, and how fast can you recover?"

Picture this: someone runs `DROP TABLE employees;` at 2 AM. Without a backup, every employee record is gone - permanently. A disk failure wipes the entire database. A ransomware attack encrypts everything. These are not hypothetical scenarios. They happen at real companies, to real DBAs, on regular schedules. Your job is to make sure they are survivable.

PostgreSQL gives you two fundamentally different backup strategies, and each one solves a different problem.

**Logical backups** use a tool called `pg_dump`, which is a command-line utility that exports your database as SQL statements or archive files. Think of it as photocopying every page of a book. You can selectively copy chapters, you can read the copies on any printer, but it takes time to copy and the copies only reflect the moment you started.

**Physical backups** use `pg_basebackup` combined with WAL archiving. `pg_basebackup` is a command-line utility that copies the raw database files over a replication connection, while WAL archiving continuously saves your transaction logs. Think of this as cloning the entire hard drive. It is faster, captures everything, and combined with WAL archiving lets you rewind to any second in time - but the clone only works on the same type of machine.

> **Concept:** No single backup strategy is sufficient. Logical backups give you portability and selectivity. Physical backups give you speed and point-in-time recovery. Production systems need both. You will set up both kinds in the BUILD guides.

---

## 2. Backup Architecture

### Simple Setup - Single Server

This is the architecture you will build in Build Guides 03-06. Both backup types originate from the same server.

```
+-------------------------------------------------------+
|                  pg-primary (NODE1)                    |
|                                                       |
|   PostgreSQL 16                                       |
|   /opt/pgsql/data                                     |
|                                                       |
|   +------------------+    +------------------------+  |
|   | Logical Backups  |    | Physical Backups       |  |
|   |                  |    |                        |  |
|   | pg_dump -------> |    | pg_basebackup -------> |  |
|   | pg_dumpall       |    |   base.tar.gz          |  |
|   |   appdb.dump     |    |                        |  |
|   |   labdb_dir/     |    | WAL Archiving -------> |  |
|   |   globals.sql    |    |   /opt/pgsql/wal_arch/ |  |
|   +------------------+    +------------------------+  |
|                                                       |
+-------------------------------------------------------+
```

### Production Setup - Separate Backup Server

In production, backups live on a different machine entirely. If the primary burns down, your backups survive because they are on separate hardware.

```
+---------------------------+          +---------------------------+
|    pg-primary (NODE1)     |          |     pg-backup (NODE2)     |
|                           |          |                           |
|  PostgreSQL 16            |  rsync   |  Backup Storage           |
|  /opt/pgsql/data          | -------> |  /opt/pgsql/backup/       |
|  /opt/pgsql/data/pg_wal   |  (WAL)   |    logical/               |
|                           |          |      appdb.dump            |
|  archive_command = rsync  | pg_base  |      labdb_dir/            |
|  wal_level = replica      | backup   |    physical/               |
|                           | -------> |      base.tar.gz           |
|  pg_dump runs here        |  (base)  |    wal_archive/            |
|  or on NODE2 via network  |          |      000000010000000X...   |
+---------------------------+          +---------------------------+
```

> **Concept:** The 3-2-1 backup rule says: keep 3 copies of your data, on 2 different media types, with 1 copy offsite. A local dump and a local base backup sitting on the same disk is only 1 copy on 1 media. That is not a backup strategy - it is an illusion of safety.

### The PITR Equation

Point-in-time recovery combines two ingredients. This is the most important diagram in this entire guide - everything in Build Guides 05 and 06 builds toward this equation.

```
  Base Backup          +        WAL Archive           =     Recovery to Any Point
  (snapshot at         +     (every change since      =     (replay WAL to target
   time T0)            +      that snapshot)           =      time, LSN, or name)

  +----------------+       +----+----+----+----+         +------------------+
  | pg_basebackup  |       |WAL |WAL |WAL |WAL |         | Recovered state  |
  | taken at       |  +    |seg |seg |seg |seg |    =    | at any point     |
  | 2026-04-19     |       | 01 | 02 | 03 | 04 |         | between T0 and   |
  | 02:00 UTC      |       |    |    |    |    |         | latest WAL       |
  +----------------+       +----+----+----+----+         +------------------+
        T0                   T0  T1   T2   T3                 T0...T3
```

This equation only works if the WAL chain is unbroken. A single missing segment breaks recovery past that point. SURVIVE Scenario 03 (Missing WAL Segment) will have you practice handling exactly that failure.

---

## 3. Core Concepts

### RPO and RTO

These two acronyms will come up constantly in backup conversations. Get comfortable with them now.

| Term | Stands For | Meaning | Example |
|------|-----------|---------|---------|
| **RPO** | Recovery Point Objective | How much data can you afford to lose | "We can lose up to 5 minutes of transactions" |
| **RTO** | Recovery Time Objective | How long can you be down | "We must be back online within 1 hour" |

RPO determines your backup frequency. If your RPO is 5 minutes, you need continuous WAL archiving (RPO near zero) or very frequent logical dumps (RPO = time since last dump). If your RPO is 24 hours, a nightly pg_dump might be enough.

RTO determines your backup type. Restoring a 500 GB database from a plain SQL dump takes hours. Restoring from a physical backup takes minutes. If your RTO is 15 minutes, logical backups alone will not meet it.

> **Concept:** RPO and RTO are business decisions, not technical ones. The CTO decides "we can lose 5 minutes and be down for 1 hour." You, the DBA, design the backup strategy to meet those numbers. If the budget does not support the required RPO/RTO, that is a business conversation, not a technical problem.

### WAL - Write-Ahead Log

Every single change to your PostgreSQL data goes through the WAL before it touches the actual data files. Think of the WAL as a journal - PostgreSQL writes down what it intends to do before it does it. This is the foundation of crash recovery, replication, and PITR.

WAL segments are 16 MB files with 24-character hex names. Here is how to read them:

```
000000010000000000000001
^^^^^^^^                  Timeline ID (8 hex chars)
        ^^^^^^^^          Log segment high bits
                ^^^^^^^^  Log segment low bits
```

When you see a WAL filename in the logs or on disk, now you know what each part means.

PostgreSQL writes changes to WAL first, then to data files later (during checkpoints). If the server crashes, it replays the WAL on restart to recover uncommitted changes. PITR exploits this same mechanism - instead of replaying all the WAL, you replay it up to a specific point and stop.

### Checkpoint

A **checkpoint** is when PostgreSQL writes all dirty buffers from shared memory to disk. Think of it as hitting "Save" on a very large document. After a checkpoint completes, WAL segments before it are no longer needed for crash recovery (though they may still be needed for archiving or replication).

```
  WAL Stream
  |---seg01---|---seg02---|---seg03---|---seg04---|---seg05---|
              ^                       ^
              Checkpoint A            Checkpoint B
              (seg01 safe             (seg01-02 safe
               to recycle)             to recycle)
```

When you run `pg_basebackup` with `--checkpoint=fast`, you force an immediate checkpoint so the backup can start right away instead of waiting for the next scheduled one. Build Guide 05 walks you through this flag.

### Timeline

A **timeline** is a sequence of WAL records. Every PostgreSQL cluster starts on timeline 1. When you perform PITR and promote the recovered instance, it increments to timeline 2. This prevents the recovered instance from accidentally overwriting WAL from the original timeline.

```
Timeline 1:  ---[backup]---[normal ops]---[disaster]---[dead]
                    |
                    +--- PITR recovery
                    |
Timeline 2:  ------[recovered]---[new ops continue]---
```

Think of timelines like branches in Git. The original history is preserved, and the recovered database starts a new branch. Timeline history files (e.g., `00000002.history`) record where each timeline branched from. This is how tools like pgBackRest and pg_basebackup know which WAL segments belong to which recovery path.

> **Concept:** Timelines exist to protect you. Without them, recovering a cluster would overwrite the WAL stream, making it impossible to try a different recovery target if the first one was wrong. SURVIVE Scenario 07 (PITR Wrong Target) will have you practice this - you may need multiple attempts to find the right recovery point, and timelines make that safe.

### LSN - Log Sequence Number

An **LSN** (Log Sequence Number) is a byte offset into the WAL stream. It uniquely identifies every change ever made to the database. The format looks like this: `0/1A000060` (segment/offset).

Why should you care? LSNs are more precise than timestamps. If two transactions commit in the same millisecond, they have different LSNs but the same timestamp. Build Guide 06 walks you through LSN-based recovery as the most precise targeting method.

### Backup Label

When pg_basebackup runs, it creates a `backup_label` file in the data directory. This file records:

- The exact WAL position (LSN) where the backup started
- The checkpoint location
- The backup method and start time

During recovery, PostgreSQL reads this file to know where to start replaying WAL. Never delete or modify `backup_label` - it is the link between your base backup and the WAL archive. If you see this file, leave it alone.

---

## 4. Logical Backups - pg_dump and pg_restore

### How pg_dump Works Under the Hood

`pg_dump` is PostgreSQL's built-in logical backup utility. It connects to a running database and exports its contents as SQL statements or compressed archive files. Here is the important part: it does not lock the database or block writes.

Instead, pg_dump opens a single transaction with `SERIALIZABLE` isolation (or `REPEATABLE READ` as of PG 16) and reads every table within that consistent snapshot. Other sessions continue reading and writing normally.

```
Time ------>

Session A (pg_dump):  [BEGIN SERIALIZABLE]---[read t1]---[read t2]---[read t3]---[COMMIT]
                              |
                              | snapshot taken here
                              | pg_dump sees data as of this moment
                              |
Session B (app):      [INSERT INTO t1].........[UPDATE t2].........[DELETE t3]...
                       ^                        ^                   ^
                       these changes are        invisible to        pg_dump
                       invisible to pg_dump     pg_dump
```

This means your dump is always consistent - it represents the database at a single point in time, even if the dump takes 30 minutes to complete. When you see this happening in the BUILD guides, you will know exactly what is going on under the hood.

> **Concept:** pg_dump's consistency comes from PostgreSQL's MVCC (Multi-Version Concurrency Control). It sees a frozen snapshot of the database regardless of concurrent writes. This is why pg_dump does not need exclusive locks and can run safely on a production primary during business hours - though it will add CPU and I/O load.

### Format Comparison

pg_dump supports four output formats. Understanding the trade-offs here will help you make the right choice in every situation.

| Feature | Plain (-Fp) | Custom (-Fc) | Directory (-Fd) | Tar (-Ft) |
|---------|-------------|-------------|-----------------|-----------|
| Output | Single .sql file | Single .dump file | Directory of files | Single .tar file |
| Compressed | No (gzip externally) | Yes (zlib built-in) | Yes (per-table) | No (gzip externally) |
| Selective restore | No | Yes (-t flag) | Yes (-t flag) | No |
| Parallel dump | No | No | Yes (--jobs) | No |
| Parallel restore | No | Yes (--jobs) | Yes (--jobs) | No |
| Human readable | Yes | No | No | No |
| TOC editing | N/A | Yes (--list/--use-list) | Yes (--list/--use-list) | N/A |
| Corruption resilience | All or nothing | All or nothing | Per-table files | All or nothing |
| Typical size (5GB DB) | ~5 GB | ~850 MB | ~850 MB | ~5 GB |

Use Exercise 01 will show you the size difference firsthand. Custom and directory formats compress 4-6x compared to plain format. For a 500 GB production database, that is the difference between 500 GB and 85 GB of backup storage. That matters for your disk budget.

### The Three Sections

pg_dump internally organizes every dump into three sections. Understanding these is key to knowing how parallel restore works.

| Section | Contains | Restore Order |
|---------|----------|---------------|
| **pre-data** | CREATE TABLE, CREATE TYPE, CREATE SEQUENCE, constraints without indexes | First |
| **data** | COPY statements (the actual rows) | Second |
| **post-data** | CREATE INDEX, ALTER TABLE ADD CONSTRAINT (foreign keys), triggers | Last |

This ordering is deliberate. Indexes are created after data loading because building an index on an empty table then inserting millions of rows is far slower than inserting all rows then building the index once. Build Guide 04 walks you through restoring these sections independently with `--section`.

> **Concept:** When pg_restore runs with `--jobs=4`, it parallelizes within each section. During the data section, it loads 4 tables simultaneously. During post-data, it builds 4 indexes simultaneously. But it never loads data and builds indexes at the same time - the section boundary is a synchronization point.

### TOC Editing - Surgical Restore

The Table of Contents (TOC) is the most powerful feature of custom and directory formats. `pg_restore` is the companion tool to pg_dump - it reads archive-format dumps and restores them into a database. When you run `pg_restore --list`, you get every object in the dump with a sequence number:

```
;
; Archive created at 2026-04-19 02:00:00 UTC
;     dbname: appdb
;
2; TABLE DATA public employees postgres
3; TABLE DATA public departments postgres
4; SEQUENCE SET public employees_id_seq postgres
5; INDEX public employees_pkey postgres
6; FK CONSTRAINT public employees departments_fk postgres
```

Comment out lines with `;` to skip them, reorder lines to change restore sequence, then feed the edited file back with `--use-list`. This technique is exactly what SURVIVE Scenario 01 (Accidental Table Drop) will have you use to extract a single table from a full database dump without restoring everything.

### pg_dumpall - The Forgotten Command

`pg_dump` exports one database at a time. But roles, tablespaces, and other cluster-wide objects live outside any single database. `pg_dumpall` is a separate utility that captures these cluster-wide objects:

```
pg_dumpall --globals-only    Roles + tablespaces only (small, fast)
pg_dumpall                   Everything (all databases + globals)
```

In production, run `pg_dumpall --globals-only` nightly. It is tiny (usually < 1 MB) but without it, you cannot restore user permissions after a full cluster rebuild. If you skip this, you will have a database with no users who can log into it.

---

## 5. Physical Backups - WAL Archiving and pg_basebackup

### How WAL Archiving Works

WAL archiving is a continuous process. PostgreSQL calls your `archive_command` every time a WAL segment fills up (every 16 MB of changes) or when `archive_timeout` expires - whichever comes first. You will configure this yourself in Build Guide 05.

```
PostgreSQL                              Archive Destination
                                        /opt/pgsql/wal_archive/
+-------------------+
| pg_wal/           |     archive_command
|   000000010...01  | --- cp %f /opt/pgsql/wal_archive/%f --->  000000010...01
|   000000010...02  | --- (waits for 01 to succeed) -------->  000000010...02
|   000000010...03  | --- (waits for 02 to succeed) -------->  000000010...03
+-------------------+
                          If archive_command FAILS:
                          - PostgreSQL retries indefinitely
                          - pg_wal grows (segments not recycled)
                          - Disk fills up eventually
                          - SURVIVE Scenario 04 simulates this
```

The `%p` placeholder is the full path to the WAL file. The `%f` placeholder is just the filename. Your archive_command must return exit code 0 on success and non-zero on failure. PostgreSQL will not recycle a WAL segment until the archive_command succeeds for it.

> **Concept:** WAL archiving is all-or-nothing per segment. If your archive_command fails, PostgreSQL keeps retrying and the segment stays in pg_wal. This is a safety feature - it guarantees no WAL is lost. But it also means a broken archive_command will eventually fill your pg_wal directory and crash the server. SURVIVE Scenario 04 (Archive Command Broken) and Scenario 05 (WAL Accumulation) will have you practice diagnosing and fixing this exact cascade.

### archive_timeout - The Silent Gap

By default, a WAL segment is only archived when it fills up (16 MB of changes). On a quiet database, this could take hours. During those hours, you have an RPO gap - the unarchived changes would be lost in a disaster.

`archive_timeout = 300` (5 minutes) forces PostgreSQL to switch to a new WAL segment every 5 minutes, even if it is not full. The partially-filled segment gets archived, closing the RPO gap to at most 5 minutes.

The trade-off: more frequent switches means more (mostly empty) WAL files in your archive. At 16 MB per segment, that is 16 MB every 5 minutes = 192 MB/hour of archive storage even on a completely idle database. When you configure this in Build Guide 05, keep that math in mind.

### How pg_basebackup Works

`pg_basebackup` is PostgreSQL's built-in tool for taking physical backups. It copies the entire data directory over a replication connection. Here is what happens step by step:

```
1. Connect to primary via replication protocol (port 5432)
2. Request checkpoint (immediate if --checkpoint=fast)
3. Start streaming WAL (if -Xs / --wal-method=stream)
4. Copy all files from PGDATA
   - Skips pg_wal (WAL comes from stream)
   - Skips postmaster.pid, pg_replslot/
   - Includes all tablespaces
5. Record backup end position
6. Write backup_label with start/end LSN
7. Disconnect
```

The `-Xs` (stream) flag is critical. Without it, pg_basebackup uses `-Xf` (fetch) mode which retrieves WAL after the backup completes. If the backup takes 2 hours, the primary might have recycled WAL segments from the beginning of the backup, making the backup unusable. Streaming mode captures WAL in parallel, guaranteeing consistency. Build Guide 05 walks you through running this command with the right flags.

### Plain vs Tar Format

| Aspect | Plain (-Fp) | Tar (-Ft -z) |
|--------|-------------|--------------|
| Output | Files copied directly | Single compressed archive |
| Size (5 GB DB) | ~5.5 GB | ~1.1 GB |
| Restore speed | Fast (files already in place) | Slower (extract first) |
| Transfer speed | Slow (many small files) | Fast (single file, compressed) |
| Can start PG directly | Yes (after ownership fix) | No (must extract first) |
| Best for | Local restore, fast RTO | Remote storage, archiving |

Use Exercise 03 will let you compare these two formats directly. Plain format is faster to restore but uses 5x more storage. For the lab's t3.small servers with limited disk, tar+gzip is the practical choice.

---

## 6. Point-in-Time Recovery (PITR)

### How PITR Works Under the Hood

PITR combines a base backup with WAL replay. This is the crown jewel of PostgreSQL backup - the ability to rewind your database to any second in time. Here is the process:

```
1. Restore base backup files to PGDATA
   (this gets you back to the backup's start point)

2. PostgreSQL reads backup_label
   (finds the WAL position where backup started)

3. PostgreSQL reads restore_command
   (knows where to fetch archived WAL segments)

4. WAL replay begins
   +------+------+------+------+------+------+
   |seg 01|seg 02|seg 03|seg 04|seg 05|seg 06|
   +------+------+------+------+------+------+
   ^                            ^
   backup start                 recovery_target_time
   (replay from here)           (stop here)

5. When target is reached:
   - pause:    Hold in recovery, let DBA inspect
   - promote:  Automatically become primary
   - shutdown: Stop cleanly (for backup purposes)
```

### Recovery Targets

PostgreSQL supports four types of recovery targets. Build Guide 06 walks you through three of them, and Use Exercise 04 gives you more practice.

| Target Type | Setting | Precision | Best For |
|-------------|---------|-----------|----------|
| **Timestamp** | `recovery_target_time` | Second-level | "Recover to 5 minutes before the incident" |
| **LSN** | `recovery_target_lsn` | Byte-level | "Recover to exact transaction boundary" |
| **Named** | `recovery_target_name` | Exact point | "Recover to the restore point we created before deployment" |
| **Transaction ID** | `recovery_target_xid` | Transaction-level | "Recover to include/exclude a specific transaction" |

> **Concept:** Named restore points (`pg_create_restore_point('before_deploy_v2')`) are the most reliable recovery target because they are immune to timezone confusion, clock skew, and same-second transactions. The cost is near zero - call it before any risky operation. Use Exercise 04 will show you why: if you have a named point, use it. Fall back to timestamp or LSN only when you do not have one.

### recovery_target_inclusive

This boolean (default: true) controls whether the target transaction itself is included in the recovery:

```
Timeline:  [tx100] [tx101] [tx102-DELETE employees] [tx103] [tx104]
                            ^
                            recovery_target_xid = 102

inclusive = true:   Recovery includes tx102 (the DELETE happens)
inclusive = false:  Recovery stops just before tx102 (DELETE does not happen)
```

When you are recovering from a destructive operation, you almost always want `recovery_target_inclusive = false` to stop just before the damage. When you see this setting in Build Guide 06, that is why it matters.

### The Side-Restore Pattern

Never perform PITR directly on your production server. Instead, you will use what is called the side-restore pattern. Use Exercise 04 walks you through it step by step.

```
+-------------------+          +---------------------+
| Production (5432) |          | Scratch (5433)      |
| (still running    |          | (PITR target)       |
|  with current     |          |                     |
|  data)            |          | 1. Restore backup   |
|                   |          | 2. Replay WAL       |
|                   |          | 3. Verify data      |
|                   |  pg_dump | 4. Dump good table  |
|                   | <------- | 5. Stop scratch     |
| 6. Restore table  |          |                     |
+-------------------+          +---------------------+
```

This pattern is safe because production stays online the entire time. If your recovery target is wrong, you throw away the scratch instance and try again - no harm done. SURVIVE Scenario 07 (PITR Wrong Target) will have you practice this exact situation - first attempt wrong, second attempt correct.

### pg_waldump - Forensic Analysis

When you do not know the exact time of an incident, `pg_waldump` is a command-line tool that decodes WAL files to show you every operation that occurred:

```
rmgr: Heap    len:  54  tx: 1234  lsn: 0/1A000060  desc: DELETE off 3
rmgr: Heap    len: 211  tx: 1235  lsn: 0/1A0000A0  desc: INSERT off 4
```

You filter for destructive operations to find the exact LSN of the incident, then set `recovery_target_lsn` to just before it. When you see `DELETE` or `DROP` in this output, that is your smoking gun. SURVIVE Scenario 07 will walk you through this forensic technique.

---

## 7. Configuration Reference

These tables are your cheat sheet. Bookmark this section - you will reference it constantly during the BUILD guides.

### WAL and Archiving Settings

| Setting | Default | Recommended | Description |
|---------|---------|-------------|-------------|
| `wal_level` | `replica` | `replica` | Minimum for PITR and replication. `logical` adds more info for logical replication. |
| `archive_mode` | `off` | `on` | Enable WAL archiving. Requires restart to change. |
| `archive_command` | `''` | `rsync` or pgBackRest | Shell command to copy WAL segments. Must return 0 on success. |
| `archive_timeout` | `0` (disabled) | `300` (5 min) | Force WAL switch after N seconds of inactivity. Controls max RPO gap. |
| `max_wal_senders` | `10` | `5-10` | Max concurrent replication/backup connections. pg_basebackup uses one. |
| `wal_keep_size` | `0` | `1GB-5GB` | Keep this much WAL on primary as buffer. Safety net if archiving falls behind. |

### Recovery Settings (postgresql.auto.conf)

| Setting | Values | Description |
|---------|--------|-------------|
| `restore_command` | Shell command | How to fetch archived WAL during recovery. `%f` = filename, `%p` = path. |
| `recovery_target_time` | Timestamp | Stop recovery at this time. |
| `recovery_target_lsn` | LSN string | Stop recovery at this WAL position. |
| `recovery_target_name` | String | Stop at named restore point. |
| `recovery_target_xid` | Integer | Stop at this transaction ID. |
| `recovery_target_action` | `pause`/`promote`/`shutdown` | What to do when target is reached. Default: `pause`. |
| `recovery_target_inclusive` | `true`/`false` | Include the target transaction? Default: `true`. |
| `recovery_target_timeline` | `latest`/number | Which timeline to follow. Default: `latest`. |

### pg_dump Key Flags

| Flag | Long Form | Description |
|------|-----------|-------------|
| `-Fp` | `--format=plain` | Plain SQL output |
| `-Fc` | `--format=custom` | Custom compressed format (recommended default) |
| `-Fd` | `--format=directory` | Directory format (enables parallel dump) |
| `-Ft` | `--format=tar` | Tar archive format |
| `-j N` | `--jobs=N` | Parallel dump/restore (directory format only for dump) |
| `-t` | `--table=TABLE` | Dump specific table(s) |
| `-T` | `--exclude-table=TABLE` | Exclude table(s) |
| `-n` | `--schema=SCHEMA` | Dump specific schema |
| `-s` | `--schema-only` | Structure only, no data |
| `-a` | `--data-only` | Data only, no structure |
| `--section` | `pre-data/data/post-data` | Dump specific section |
| `--no-owner` | | Omit ownership commands |
| `--no-privileges` | | Omit GRANT/REVOKE commands |

---

## 8. Logical vs Physical - When to Use Each

This is the decision matrix. When someone asks you "which backup type should I use?", this table is your answer.

| Scenario | Logical (pg_dump) | Physical (basebackup + WAL) | Winner |
|----------|-------------------|----------------------------|--------|
| Single table recovery | `-t employees` from custom dump | PITR side-restore, dump table, re-insert | **Logical** (faster, simpler) |
| Full cluster recovery | Restore every database sequentially | Restore base backup, replay WAL | **Physical** (10x faster) |
| Cross-version upgrade | pg_dump from PG15, pg_restore to PG16 | Not possible | **Logical** (only option) |
| Point-in-time recovery | Not possible (snapshot only) | Replay WAL to exact second | **Physical** (only option) |
| Cross-platform migration | pg_dump on Linux, restore on Windows | Not possible | **Logical** (only option) |
| 500 GB database, RTO < 1 hour | Restore takes 4-8 hours | Restore takes 15-30 minutes | **Physical** |
| 50 MB database, simple needs | pg_dump takes seconds | Overkill | **Logical** |
| Selective schema export | `--schema-only` for version control | Not possible | **Logical** |
| Continuous zero-RPO protection | Not possible (point-in-time snapshots) | WAL archiving (near-zero RPO) | **Physical** |

> **Concept:** The decision is not either/or. Production environments run both. Nightly pg_dump (custom format) for portability and selective restore. Continuous WAL archiving + weekly pg_basebackup for PITR and fast full recovery. This dual strategy covers every failure mode you will encounter in the SURVIVE scenarios.

### Recovery Time Estimates

These are rough estimates for a 100 GB database on a t3.small (2 vCPU, 2 GB RAM). Keep these numbers in mind when someone asks about your RTO.

| Operation | Estimated Time |
|-----------|---------------|
| pg_dump -Fc (100 GB) | 45-90 minutes |
| pg_restore -j 2 (100 GB custom) | 60-120 minutes |
| pg_basebackup -Ft -z (100 GB) | 20-40 minutes |
| Physical restore (extract + start) | 10-20 minutes |
| WAL replay (1 hour of changes) | 2-5 minutes |
| pg_dump plain SQL restore (100 GB) | 3-6 hours |

---

## 9. Production Best Practices

### Backup Scheduling

Here is a baseline schedule you can adapt for any production environment:

| Backup Type | Frequency | Retention | Purpose |
|-------------|-----------|-----------|---------|
| `pg_dumpall --globals-only` | Daily | 30 days | Roles and tablespaces |
| `pg_dump -Fc` (each database) | Daily | 7-14 days | Selective restore, cross-version |
| `pg_basebackup` or pgBackRest full | Weekly | 4 weeks | PITR base |
| pgBackRest differential | Daily | 7 days | Reduce WAL replay time |
| WAL archiving | Continuous | Match oldest base backup | PITR capability |

### What Senior DBAs Do Differently

**They test restores, not backups.** A backup that has never been restored is a hope, not a backup. Schedule monthly restore drills. Automate them if possible. Track restore time to predict RTO. This is a mindset shift - the backup is not done when the file is written, it is done when you have proven you can restore from it.

**They monitor backup size trends.** If your nightly dump suddenly drops from 50 GB to 5 GB, something is wrong - a schema change dropped tables, or the dump silently failed partway through. Alert on size anomalies, not just success/failure.

**They separate filesystems.** Production systems put `pg_wal`, `PGDATA`, and backup storage on separate filesystems (or separate EBS volumes on AWS). A full backup disk should never cascade into a full WAL directory which crashes PostgreSQL. SURVIVE Scenario 06 (Disk Full During Backup) will have you practice diagnosing this cascade.

**They verify after every backup:**

```
BAD:   pg_dump -Fc appdb > appdb.dump  (hope it worked)

GOOD:  pg_dump -Fc appdb > appdb.dump && pg_restore --list appdb.dump > /dev/null
       (verify the dump is readable)

BEST:  pg_dump -Fc appdb > appdb.dump && \
       pg_restore --list appdb.dump > /dev/null && \
       md5sum appdb.dump > appdb.dump.md5
       (verify readable + checksum for corruption detection)
```

SURVIVE Scenario 02 (Corrupted Dump File) will show you what happens when a dump file has a bad header - it is worthless. Post-backup verification catches this immediately instead of during a real emergency.

> **Concept:** The worst time to discover your backup is corrupted is when you need to restore it. Every backup should be verified immediately after creation. Every backup strategy should include periodic full restore tests to a scratch environment. The cost of a monthly restore drill is trivial compared to the cost of discovering your backups are useless during an actual outage.

**They use multiple formats.** Keep both custom (-Fc) and directory (-Fd) dumps. If custom is corrupted, directory format stores each table as a separate file - partial recovery is possible even if one file is damaged.

---

## 10. Common Commands Quick Reference

Keep this section handy. These are the commands you will use most frequently, organized by category.

### Logical Backup

| Command | Description |
|---------|-------------|
| `pg_dump -Fc dbname > db.dump` | Custom format dump (recommended default) |
| `pg_dump -Fd -j 4 dbname -f db_dir/` | Parallel directory dump |
| `pg_dump -Fp --schema-only dbname > schema.sql` | Schema only for version control |
| `pg_dump -Fc -t tablename dbname > table.dump` | Single table dump |
| `pg_dump -Fc -T 'temp_*' dbname > db.dump` | Exclude tables by pattern |
| `pg_dumpall --globals-only > globals.sql` | Roles and tablespaces |
| `pg_restore --list db.dump` | View dump contents (verify + plan) |
| `pg_restore -d target -j 4 db.dump` | Parallel restore |
| `pg_restore -d target -t tablename db.dump` | Restore single table |
| `pg_restore --list db.dump > toc.txt` | Export TOC for editing |
| `pg_restore --use-list=toc.txt -d target db.dump` | Restore with edited TOC |

### Physical Backup

| Command | Description |
|---------|-------------|
| `pg_basebackup -D /backup -Fp -Xs -P` | Plain format with streaming WAL |
| `pg_basebackup -D /backup -Ft -z -Xs -P` | Compressed tar with streaming WAL |
| `SELECT pg_switch_wal();` | Force WAL segment switch |
| `SELECT * FROM pg_stat_archiver;` | Check archiving health |
| `SELECT pg_create_restore_point('name');` | Create named restore point |
| `SELECT pg_current_wal_lsn();` | Get current WAL position |
| `SELECT pg_walfile_name(pg_current_wal_lsn());` | Get current WAL filename |
| `pg_waldump 000000010000000000000001` | Decode WAL for forensics |

### Recovery

| Command | Description |
|---------|-------------|
| `touch /opt/pgsql/data/recovery.signal` | Signal PostgreSQL to start recovery |
| `SELECT pg_is_in_recovery();` | Check if instance is in recovery |
| `SELECT pg_wal_replay_resume();` | Resume paused recovery |
| `SELECT pg_promote();` | Promote standby to primary (SQL) |
| `pg_ctl promote -D /opt/pgsql/data` | Promote standby to primary (CLI) |

---

## 11. Troubleshooting

When things go wrong (and they will), this section is your starting point. If you run into an error during the BUILD guides, check here first.

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `pg_dump: error: connection to server failed` | PostgreSQL not running or wrong host/port | Check `pg_isready`, verify connection params |
| `pg_restore: error: input file appears to be a text format dump` | Used pg_restore on a plain SQL file | Use `psql -f file.sql` for plain format, not pg_restore |
| `FATAL: could not open file "backup_label"` | backup_label missing or corrupted in restored data | Re-restore from base backup, do not manually delete backup_label |
| `FATAL: the database system is starting up` | Recovery still in progress | Wait for recovery to complete, check logs |
| `requested WAL segment 000000010000000000000005 has already been removed` | pg_basebackup too slow, WAL recycled | Use `-Xs` (stream), increase `wal_keep_size` |
| `archive command failed with exit code 1` | archive_command has a bug or target is full | Check disk space, test archive_command manually |
| `could not restore file from archive` | restore_command cannot find WAL segment | Verify archive path, check file permissions |
| `recovery ended before configured recovery target was reached` | Target is beyond available WAL | Check WAL archive completeness, may need more segments |
| `pg_restore: [archiver] unsupported version (X.Y) in file header` | Dump from newer PG version | Use pg_restore from the same or newer PG version |
| `pg_basebackup: error: could not initiate base backup: too many replication connections` | `max_wal_senders` exhausted | Increase max_wal_senders, check for stuck replication slots |

When you see any of these errors, do not panic. Read the error message carefully - PostgreSQL error messages are usually very specific about what went wrong.

### Diagnostic Queries

These queries will help you figure out what is happening inside your PostgreSQL instance:

| Query | Purpose |
|-------|---------|
| `SELECT * FROM pg_stat_archiver;` | Last archived WAL, last failure, fail count |
| `SELECT pg_walfile_name(pg_current_wal_lsn());` | Current WAL segment |
| `SELECT pg_is_in_recovery();` | Am I a standby or in recovery? |
| `SELECT pg_last_wal_replay_lsn();` | How far recovery has progressed |
| `SELECT pg_last_xact_replay_timestamp();` | Timestamp of last replayed transaction |
| `SELECT datname, pg_database_size(datname) FROM pg_database;` | Database sizes for backup planning |
| `SELECT slot_name, active, restart_lsn FROM pg_replication_slots;` | Replication slots holding WAL |

### When Recovery Stalls

If PostgreSQL seems stuck during PITR, here is your checklist:

1. Check the log file - it reports which WAL segment it is replaying and what target it is aiming for
2. If `restore_command` fails, the log shows the exact command and exit code
3. If recovery reaches the target but nothing happens, check `recovery_target_action` - it may be set to `pause`, which means PostgreSQL is waiting for you to run `pg_wal_replay_resume()`
4. If recovery reaches the end of available WAL without hitting the target, your target is in the future relative to your WAL archive - you need more WAL segments or a different target

> **Concept:** The PostgreSQL log file is your best friend during recovery. Every WAL segment replayed, every error encountered, and every target check is logged. When PITR does not do what you expect, the answer is almost always in the last 20 lines of the log. Build Guide 06 will have you watching these logs in real time as recovery progresses.
