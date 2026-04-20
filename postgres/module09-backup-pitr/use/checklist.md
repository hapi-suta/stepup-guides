# Phase 2 (USE) - Knowledge Check

Answer each question before moving to Phase 3. Hidden answers are provided - try answering from memory first, then expand the answer to check yourself.

---

## Instructions

For each question, formulate your answer mentally or on paper. Then expand the answer block to verify. If you get fewer than 12 correct, review the relevant exercises before proceeding.

---

## Questions

### Logical Backups

**1. Name the 4 pg_dump output formats and state the restore tool for each.**

<details>
<summary>Answer</summary>

- **Plain** (`-Fp`) - restored with `psql` (it is raw SQL)
- **Custom** (`-Fc`) - restored with `pg_restore`
- **Directory** (`-Fd`) - restored with `pg_restore`
- **Tar** (`-Ft`) - restored with `pg_restore`

Plain is the only format restored with `psql`. The other three require `pg_restore`. Custom and directory support parallel restore with `--jobs`. Directory is the only format that supports parallel dump.

On CentOS Stream 9 with PostgreSQL 16, use the full binary paths: `/usr/pgsql-16/bin/pg_dump`, `/usr/pgsql-16/bin/pg_restore`, `/usr/pgsql-16/bin/psql`.
</details>

---

**2. What is the difference between pg_dumpall and pg_dump? When do you need pg_dumpall?**

<details>
<summary>Answer</summary>

`pg_dump` operates on a single database. It captures tables, indexes, functions, sequences, and other database-specific objects. It does NOT capture roles, tablespaces, or other cluster-wide objects.

`pg_dumpall` dumps all databases in the cluster plus global objects (roles, tablespaces). Use `pg_dumpall --globals-only` to capture just the globals without database data. You need this alongside `pg_dump` backups - otherwise a restore fails because the owning roles do not exist.

On CentOS, switch to the postgres user first (`sudo -iu postgres`), then run: `/usr/pgsql-16/bin/pg_dumpall --globals-only -f /opt/pgsql/backup/globals.sql`
</details>

---

**3. Explain what these pg_restore flags do: `-c`, `-C`, `--data-only`, `--schema-only`, `-j 4`.**

<details>
<summary>Answer</summary>

- `-c` (--clean) - drops each object before recreating it. Useful for restoring into an existing database.
- `-C` (--create) - includes the `CREATE DATABASE` command in the restore. The database specified by `-d` is used only for the initial connection; the restore creates and switches to the target database.
- `--data-only` - restores only the data (COPY statements), not the schema. The target database must already have the schema.
- `--schema-only` - restores only the schema (DDL), not the data. Useful for setting up structure before loading data separately.
- `-j 4` (--jobs=4) - uses 4 parallel workers for restore. Only works with custom and directory formats. Can dramatically reduce restore time on multi-core systems.
</details>

---

**4. You have a custom-format dump of appdb at `/opt/pgsql/backup/appdb_full.dump`. How do you restore only the employees table?**

<details>
<summary>Answer</summary>

Two approaches:

**Quick method:**

Switch to the postgres user first:
```bash
sudo -iu postgres
```

Then run the restore:
```bash
/usr/pgsql-16/bin/pg_restore -d targetdb -t employees /opt/pgsql/backup/appdb_full.dump
```

Expected output (yours will differ):
```
$ /usr/pgsql-16/bin/pg_restore -d targetdb -t employees /opt/pgsql/backup/appdb_full.dump
$
```
No output means success. If there were errors, pg_restore prints them to stderr.

**Precise method (TOC editing):**

Switch to the postgres user first:
```bash
sudo -iu postgres
```

1. Generate the TOC listing:
```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/appdb_full.dump > /opt/pgsql/backup/toc.txt
```

2. Edit `/opt/pgsql/backup/toc.txt` - comment out (`;`) all lines not related to the employees table

3. Restore using the filtered TOC:
```bash
/usr/pgsql-16/bin/pg_restore -d targetdb --use-list=/opt/pgsql/backup/toc.txt /opt/pgsql/backup/appdb_full.dump
```

When done, exit back to ec2-user:
```bash
exit
```

The TOC method gives you surgical control over exactly which objects (table definition, data, indexes, constraints) get restored. The `-t` shortcut is simpler but includes all associated objects automatically.
</details>

---

### Physical Backups

**5. What server-side settings does pg_basebackup require, and what do the flags `-Fp`, `-Xs`, `-P` mean?**

<details>
<summary>Answer</summary>

Server-side requirements:
- `wal_level` must be `replica` or `logical`
- `max_wal_senders` must have at least one available slot
- A user with `REPLICATION` privilege must exist
- `/opt/pgsql/data/pg_hba.conf` must allow replication connections from the backup host

Flag meanings:
- `-Fp` - plain format (copies files as-is into the target directory, ready to start PostgreSQL from)
- `-Xs` - stream WAL during backup (opens a second connection to capture WAL generated during the backup, making it self-contained)
- `-P` - show progress (displays a percentage and data rate during the backup)

On CentOS, switch to the postgres user first:
```bash
sudo -iu postgres
```

Then run the backup:
```bash
/usr/pgsql-16/bin/pg_basebackup -h [NODE1_IP] -U replicator -D /opt/pgsql/backup/pg_basebackup_plain -Fp -Xs -P
```

When done, exit back to ec2-user:
```bash
exit
```
</details>

---

### WAL Archiving

**6. What are the two ingredients required for PITR, and what does each provide?**

<details>
<summary>Answer</summary>

1. **Base backup** (from pg_basebackup or pgBackRest) - provides the starting state of the data directory at a specific point in time.
2. **WAL archives** (from archive_command or pgBackRest) - provide a continuous record of every change made after the base backup. Stored at `/opt/pgsql/backup/archive` (native) or `/opt/pgsql/backup/pgbackrest` (pgBackRest).

Together: restore the base backup, then replay WAL forward to any desired moment. The base backup alone only gives you the database at backup time. WAL alone is useless without a starting point. Both are required.
</details>

---

**7. What does `archive_timeout = 60` do, and how does it affect RPO?**

<details>
<summary>Answer</summary>

`archive_timeout` forces a WAL segment switch after the specified number of seconds of inactivity. Without it, a quiet database might not complete a 16MB WAL segment for hours, leaving recent changes unarchived.

With `archive_timeout = 60`, the maximum data at risk is 60 seconds of transactions (because WAL ships at most every 60 seconds). In practice, busy databases fill WAL segments faster than the timeout, so the actual RPO is often under 10 seconds. This setting primarily protects quiet periods.
</details>

---

### PITR

**8. Name the four types of PITR recovery targets and the postgresql.auto.conf parameter for each.**

<details>
<summary>Answer</summary>

1. **Time** - `recovery_target_time = '2026-04-17 10:45:00+00'` - recover to a specific timestamp
2. **Transaction ID** - `recovery_target_xid = '12345'` - recover to the end of a specific transaction
3. **LSN** - `recovery_target_lsn = '0/6000100'` - recover to a specific WAL byte position
4. **Named restore point** - `recovery_target_name = 'before_migration'` - recover to a marker created with `pg_create_restore_point()`

Named restore points are the most reliable because they are exact - no clock skew or timezone confusion. Time-based is the most commonly used in practice because operators typically know "the bad thing happened around 10:45 AM."

On CentOS with custom mount points, the `postgresql.auto.conf` lives at `/opt/pgsql/data/postgresql.auto.conf` and the `recovery.signal` file goes at `/opt/pgsql/data/recovery.signal`.
</details>

---

**9. What is recovery_target_action and what are its three options?**

<details>
<summary>Answer</summary>

`recovery_target_action` controls what PostgreSQL does when it reaches the recovery target:

- **pause** (default) - stays in recovery mode so you can inspect the data before committing. Use `pg_wal_replay_resume()` and `pg_promote()` to finalize.
- **promote** - immediately becomes a read-write primary. Use when you are confident in the target.
- **shutdown** - stops the server cleanly after reaching the target. Useful for scripted recovery where you want to inspect the data directory before starting.
</details>

---

**10. Describe the side-restore pattern. When would you use it instead of restoring over production?**

<details>
<summary>Answer</summary>

The side-restore pattern restores a backup to a separate directory and runs it as a temporary PostgreSQL instance on a different port (e.g., 5433). You extract the needed data from the scratch instance and pipe it back into the live production database.

Steps:
1. Copy base backup to a scratch directory (e.g., `/opt/pgsql/backup/pitr_scratch`)
2. Configure recovery target in the scratch directory's `postgresql.auto.conf`
3. Set a different port (e.g., `port = 5433`)
4. Switch to the postgres user:
   ```bash
   sudo -iu postgres
   ```
5. Start the scratch instance:
   ```bash
   /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/backup/pitr_scratch start
   ```
6. Extract data from the scratch instance and load it into production:
   ```bash
   /usr/pgsql-16/bin/pg_dump -p 5433 -d dbname -t tablename | /usr/pgsql-16/bin/psql -d dbname
   ```
7. Stop and remove the scratch instance, then exit back to ec2-user:
   ```bash
   exit
   ```

Use it when you need to recover specific data (a dropped table, deleted rows) without taking production offline. It preserves any new data written after the incident.
</details>

---

### pgBackRest

**11. What is the difference between full, differential, and incremental backups in pgBackRest?**

<details>
<summary>Answer</summary>

- **Full** (`--type=full`) - copies every file in the data directory. Self-contained, no dependencies. With the 5GB labdb dataset, the full backup repo size is ~1.1GB.
- **Differential** (`--type=diff`) - copies only files that changed since the last full backup. Depends on one full backup.
- **Incremental** (`--type=incr`) - copies only files that changed since the last backup of any type (full, diff, or incr). Depends on the entire chain.

Size comparison: full is largest, differential is medium, incremental is smallest. Restore speed: all three restore at similar speed because pgBackRest assembles the chain automatically. Risk: a corrupted backup in the middle of an incremental chain breaks all subsequent restores.
</details>

---

**12. What is a pgBackRest stanza and why does it exist?**

<details>
<summary>Answer</summary>

A stanza is pgBackRest's term for a backup configuration that maps to a specific PostgreSQL cluster. It defines the database path (`/opt/pgsql/data`), backup repository location (`/opt/pgsql/backup/pgbackrest`), retention settings, and other parameters for that cluster.

It exists because a single pgBackRest installation can manage backups for multiple PostgreSQL clusters. Each cluster gets its own stanza with independent settings. The stanza name is used in every pgBackRest command (`--stanza=main`) to specify which cluster you are operating on.

Common commands: `pgbackrest --stanza=main stanza-create` (initialize), `pgbackrest --stanza=main check` (verify configuration and WAL archiving), `pgbackrest --stanza=main info` (list backups).

The stanza configuration lives in `/etc/pgbackrest/pgbackrest.conf` on CentOS Stream 9.
</details>

---

### Strategy and Concepts

**13. A company says "we have a replica, so we do not need backups." Why are they wrong?**

<details>
<summary>Answer</summary>

A streaming replica replicates every operation - including destructive ones. If someone runs `DROP TABLE users;` or `DELETE FROM orders;` on the primary, the replica executes the same statement within milliseconds. The data is gone from both nodes.

Replicas protect against hardware failure (disk dies, server crashes). Backups protect against logical errors (human mistakes, application bugs, SQL injection). These are different failure modes that require different solutions. You need both.

Additionally, replicas do not provide historical recovery. You cannot go back to "how the database looked 3 hours ago" with a replica. Only PITR with backups can do that.
</details>

---

**14. How do you verify that a backup is actually valid and restorable?**

<details>
<summary>Answer</summary>

Three levels of verification:

1. **Checksum verification** - `pgbackrest verify` checks every file against its stored checksum. Detects corruption and bit rot. Does not prove the backup can actually start a PostgreSQL instance.

2. **Automated restore test** - restore the backup to a scratch instance and start PostgreSQL. Verify it accepts connections and you can query data. This is the only way to prove a backup is truly restorable. On CentOS, remember to recreate the pg_wal symlink to `/opt/pgsql/wal` and set correct ownership during restore.

3. **Data integrity check** - after a test restore, compare row counts, run `pg_catalog` checks, and verify critical application queries return expected results.

A backup that has only passed checksum verification is better than untested, but a backup that has been restored and queried is the gold standard. Schedule automated restore tests weekly at minimum.
</details>

---

**15. You need to design a backup strategy. The database is 500GB, RPO is 5 minutes, RTO is 30 minutes. Outline your approach.**

<details>
<summary>Answer</summary>

**Tool:** pgBackRest (handles full/diff/incr, compression, PITR, verification)

**Schedule:**
- Full backup: weekly (Sunday)
- Differential: daily (Mon-Sat)
- Incremental: every 4 hours
- WAL archiving: continuous with `archive_timeout = 60`

**RPO (5 minutes):** Met by continuous WAL archiving. With `archive_timeout = 60`, WAL ships at most every 60 seconds. Actual RPO is typically under 1 minute for an active database.

**RTO (30 minutes):** Met by delta restore from local storage. A 500GB delta restore takes 15-20 minutes on SSD. WAL replay adds 5-10 minutes. Total under 30 minutes. For faster RTO, maintain a streaming replica and promote it (takes seconds).

**Storage:** Local repo at `/opt/pgsql/backup/pgbackrest` on backup server (for speed) + S3 (for disaster resilience). Estimated 2.5TB for 90-day retention.

**Monitoring:** Alert on backup age > 8 hours, WAL archive lag > 5 minutes, repo disk > 80%.

**Testing:** Automated weekly restore to scratch instance. Monthly timed restore drill.

**Supplement:** Weekly `/usr/pgsql-16/bin/pg_dump -Fc` of each database for selective restore capability and cross-version migration safety.

**CentOS-specific:** Service is `postgresql-16` (not `postgresql`). Config files live in `/opt/pgsql/data/`. pg_wal is symlinked from `/opt/pgsql/data/pg_wal` to `/opt/pgsql/wal`. All restores must recreate this symlink and set `postgres:postgres` ownership.
</details>

---

## Scoring

- **15/15 correct** - You are ready for Phase 3 (SURVIVE). Proceed with confidence.
- **12-14 correct** - Review the exercises for the questions you missed, then re-test yourself.
- **Below 12** - Repeat the full USE phase. Mastery comes from repetition, not from rushing forward.

---

## What Phase 3 Expects From You

Phase 3 (SURVIVE) will test your ability to handle backup and recovery scenarios without step-by-step instructions. You will face:

- Accidental table drops requiring fast PITR
- Corrupted dump files requiring alternate recovery paths
- Missing WAL segments that prevent PITR
- Backup repository failures during active incidents
- Recovery decisions under time pressure

If you cannot perform the USE phase tasks from memory, Phase 3 will be frustrating rather than educational. Take the time now.

---

**Next:** Phase 3 - SURVIVE exercises
