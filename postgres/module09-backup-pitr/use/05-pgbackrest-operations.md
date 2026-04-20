# Exercise 05 - pgBackRest Operations

**Time estimate:** 25-35 minutes
**Prerequisites:** Exercise 04 complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9, pgBackRest installed and configured on both nodes. pgBackRest repo at `/opt/pgsql/backup/pgbackrest`.

---

## Objective

Master pgBackRest backup types, verification, restore modes, and retention management. By the end of this exercise, you should be able to operate pgBackRest confidently for any production backup scenario.

---

## Step 1 - Take a Full Backup

On **NODE2** (pg-backup) or wherever pgBackRest is configured to run:

Switch to the postgres user. All pgBackRest commands run as postgres.

```bash
sudo -iu postgres
```

Take a full backup:

```bash
pgbackrest --stanza=main --type=full backup
```

**Expected:**

```
INFO: backup command end: completed successfully
```

Examine the backup info:

```bash
pgbackrest --stanza=main info
```

**Expected:**

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000008

        full backup: 20260417-104500F
            timestamp start/stop: 2026-04-17 10:45:00+00 / 2026-04-17 10:47:30+00
            wal start/stop: 000000010000000000000007 / 000000010000000000000008
            database size: 5.6GB, database backup size: 5.6GB
            repo1: backup size: 1.1GB
```

> **Concept:** A full backup copies every file in the PostgreSQL data directory. The `info` output shows two sizes: `database size` (uncompressed original, ~5.6GB with the pgbench scale-330 data) and `repo1: backup size` (compressed in the repository, ~1.1GB). pgBackRest compresses and checksums every file by default. The full backup is the foundation - differential and incremental backups reference it.

---

## Step 2 - Insert Data and Take a Differential Backup

On **NODE1** (pg-primary):

```bash
psql -d labdb -c "
INSERT INTO employees (name, department, hired_at)
SELECT
    'diff_test_' || generate_series(1, 500),
    'Engineering',
    NOW();
"
```

Force a checkpoint to flush changes to disk:

```bash
psql -d labdb -c "CHECKPOINT;"
```

Take a differential backup:

```bash
pgbackrest --stanza=main --type=diff backup
```

Check info:

```bash
pgbackrest --stanza=main info
```

**Expected:** Two backups listed - the full and the new differential. The differential should be significantly smaller:

```
        diff backup: 20260417-104500F_20260417-105000D
            timestamp start/stop: ...
            database size: 5.6GB, database backup size: 48MB
            repo1: backup size: 6.2MB
            backup reference list: 20260417-104500F
```

> **Concept:** A differential backup only copies files that changed since the last full backup. The `backup reference list` shows which full backup it depends on. To restore from a differential, pgBackRest needs both the differential and the referenced full backup. Differentials grow over time as more files change since the full.

---

## Step 3 - Insert More Data and Take an Incremental Backup

On **NODE1**:

```bash
psql -d labdb -c "
INSERT INTO employees (name, department, hired_at)
SELECT
    'incr_test_' || generate_series(1, 200),
    'Sales',
    NOW();
"
```

```bash
psql -d labdb -c "CHECKPOINT;"
```

Take an incremental backup:

```bash
pgbackrest --stanza=main --type=incr backup
```

Check info:

```bash
pgbackrest --stanza=main info
```

**Expected:** Three backups listed. The incremental is the smallest:

```
        incr backup: 20260417-104500F_20260417-105500I
            timestamp start/stop: ...
            database size: 5.6GB, database backup size: 24MB
            repo1: backup size: 3.1MB
            backup reference list: 20260417-104500F, 20260417-104500F_20260417-105000D
```

> **Concept:** An incremental backup only copies files that changed since the last backup of any type (full, differential, or incremental). The reference list includes all prior backups in the chain. Incrementals are the fastest and smallest, but they create a longer dependency chain. If any backup in the chain is corrupted, the restore fails. This is why production strategies combine all three types.

---

## Step 4 - Compare Backup Sizes

```bash
pgbackrest --stanza=main info
```

Summarize what you see:

| Backup Type | Database Backup Size | Repo Size | Reference Chain |
|---|---|---|---|
| Full | 5.6GB | 1.1GB | None |
| Differential | 48MB | 6.2MB | Full |
| Incremental | 24MB | 3.1MB | Full + Diff |

> **Concept:** The tradeoff is clear: full backups are large but self-contained, differentials are medium and depend on one full, incrementals are tiny but depend on the entire chain. A common production schedule is: weekly full, daily differential, hourly incremental. This balances storage cost against restore reliability.

---

## Step 5 - Verify Backup Integrity

```bash
pgbackrest --stanza=main verify
```

**Expected:**

```
INFO: verify command end: completed successfully
```

If there are issues, pgBackRest will report them:

```
WARN: backup '20260417-104500F' file '/path/to/file' checksum mismatch
```

> **Concept:** `pgbackrest verify` checks every file in every backup against its stored checksum. It also verifies the WAL archive for gaps. This is not a quick operation on large repositories, but it should be part of your weekly maintenance. A backup you have never verified is a backup you cannot trust. Many organizations have discovered during a real disaster that their backups were silently corrupted for months.

---

## Step 6 - Restore a Full Backup to a Clean Directory

Exit back to ec2-user to stop PostgreSQL on **NODE1**:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

Wipe the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Wipe the WAL directory:

```bash
sudo rm -rf /opt/pgsql/wal/*
```

Switch back to postgres:

```bash
sudo -iu postgres
```

Restore the latest backup set:

```bash
pgbackrest --stanza=main --delta restore
```

Wait - the data directory is empty, so `--delta` will copy everything. This is equivalent to a full restore when starting from nothing. pgBackRest knows about the custom mount points from its configuration and will restore PGDATA to `/opt/pgsql/data` and recreate the pg_wal symlink to `/opt/pgsql/wal`.

Exit back to ec2-user to start PostgreSQL:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

Switch back to postgres to verify:

```bash
sudo -iu postgres
```

Check total employee count:

```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

Check diff_test rows were restored:

```bash
psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'diff_test_%';"
```

Check incr_test rows were restored:

```bash
psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'incr_test_%';"
```

**Expected:** All data from the full, differential, and incremental backups is present. pgBackRest automatically assembles the chain.

> **Concept:** pgBackRest handles backup chain assembly automatically. You do not need to restore the full, then the differential, then the incremental separately. pgBackRest reads the dependency chain and pulls the correct version of each file from the appropriate backup. This is a major advantage over manual pg_basebackup + WAL replay.

---

## Step 7 - PITR With pgBackRest

Exit back to ec2-user to stop PostgreSQL:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

Wipe the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Wipe the WAL directory:

```bash
sudo rm -rf /opt/pgsql/wal/*
```

Switch back to postgres:

```bash
sudo -iu postgres
```

Restore to a specific point in time:

```bash
pgbackrest --stanza=main \
  --type=time \
  --target="2026-04-17 10:50:00+00" \
  --target-action=promote \
  restore
```

Replace the timestamp with a time between your differential and incremental backups.

Exit back to ec2-user to start PostgreSQL:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

Switch back to postgres to verify:

```bash
sudo -iu postgres
```

diff_test rows should exist (inserted before the target time):

```bash
psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'diff_test_%';"
```

incr_test rows should NOT exist (inserted after the target time):

```bash
psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'incr_test_%';"
```

**Expected:**
- diff_test count: `500`
- incr_test count: `0`

> **Concept:** pgBackRest PITR works the same as native PostgreSQL PITR but handles the restore_command configuration automatically. It selects the right base backup, restores it, and configures WAL replay to stop at your target. The `--target-action=promote` flag makes the server come up as a primary immediately.

---

## Step 8 - Delta Restore

Delta restore is for when the data directory is not empty - it only replaces files that differ from the backup.

First, restore the full latest backup normally. Exit back to ec2-user to stop PostgreSQL:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

Switch back to postgres:

```bash
sudo -iu postgres
```

Instead of wiping, restore with delta directly over the existing data directory:

```bash
pgbackrest --stanza=main --delta restore
```

**Expected:** pgBackRest reports which files it replaced and which it skipped:

```
INFO: restore file ... (exists and matches backup, skip)
INFO: restore file ... (does not match backup, replace)
```

Exit back to ec2-user to start PostgreSQL:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

Switch back to postgres to verify:

```bash
sudo -iu postgres
```

Verify:

```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

> **Concept:** Delta restore is dramatically faster than a full restore when most files are unchanged - for example, after minor corruption or after a failed upgrade rollback. pgBackRest checksums each existing file against the backup and only replaces mismatches. On a 1TB database where only 10GB changed, delta restore finishes in minutes instead of hours.

---

## Step 9 - Selective Database Restore

Restore only labdb from the backup (skip appdb and blobdb). Exit back to ec2-user to stop PostgreSQL:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

Wipe the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Wipe the WAL directory:

```bash
sudo rm -rf /opt/pgsql/wal/*
```

Switch back to postgres:

```bash
sudo -iu postgres
```

Restore with only labdb included:

```bash
pgbackrest --stanza=main \
  --db-include=labdb \
  restore
```

Exit back to ec2-user to start PostgreSQL:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

Switch back to postgres to verify:

```bash
sudo -iu postgres
```

Verify:

```bash
psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"
```

**Expected:** labdb is fully functional with ~33M pgbench_accounts rows.

```bash
psql -d appdb -c "SELECT 1;"
```

**Expected:** Error or empty database - appdb data was not restored (the database entry exists in the catalog but tables are empty).

> **Concept:** Selective database restore is a middle ground between "restore everything" and "use pg_dump for one database." pgBackRest restores the system catalog (pg_global) and only the specified database's files. Other databases will appear in `\l` but will be non-functional. This is useful when you only need one database and want to minimize restore time.

---

## Step 10 - Expire Old Backups

Check current retention settings:

```bash
pgbackrest --stanza=main info
```

Set retention to keep only 2 full backups (in `/etc/pgbackrest/pgbackrest.conf`):

```ini
[main]
repo1-retention-full=2
```

Run expire:

```bash
pgbackrest --stanza=main expire
```

Check info again:

```bash
pgbackrest --stanza=main info
```

**Expected:** Old backups beyond the retention window are removed. WAL archives that are no longer needed by any remaining backup are also cleaned up.

> **Concept:** Without expiration, your backup repository grows without bound. `repo1-retention-full` controls how many full backup sets to keep. Each full backup and its chain of differentials/incrementals counts as one set. WAL archives are automatically expired when no remaining backup needs them. In production, set retention based on your compliance requirements and storage budget. Common settings: `repo1-retention-full=4` (keep 4 weekly fulls = 1 month of recovery history).

---

## Step 11 - Think: What Retention Strategy Would You Use in Production?

Consider a 500GB production database:

| Strategy | Full Schedule | Diff Schedule | Incr Schedule | Retention | Estimated Storage |
|---|---|---|---|---|---|
| Conservative | Weekly (Sun) | Daily | Hourly | 4 full | ~2.5TB repo |
| Balanced | Weekly (Sun) | Daily | Every 4 hours | 2 full | ~1.2TB repo |
| Aggressive | Biweekly | Daily | None | 2 full | ~600GB repo |

Factors to consider:
- RPO requirement (how much data can you afford to lose?)
- RTO requirement (how fast must you restore?)
- Storage budget
- Compliance/audit requirements for backup retention
- Network bandwidth for offsite replication

---

## Checkpoint

Before continuing, confirm:
- [ ] You took a full backup and examined pgbackrest info output
- [ ] You took a differential backup and understand its dependency on the full
- [ ] You took an incremental backup and understand the chain
- [ ] You compared sizes across all three backup types
- [ ] You ran pgbackrest verify successfully
- [ ] You restored a full backup and verified all data
- [ ] You performed PITR with pgBackRest
- [ ] You used delta restore and understand when it saves time
- [ ] You performed a selective database restore with `--db-include`
- [ ] You expired old backups and understand retention settings

When you are done, exit back to ec2-user:

```bash
exit
```

---

**Next:** [06 - Backup Strategy Design](06-backup-strategy-design.md)
