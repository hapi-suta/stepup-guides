# Build 08: pgBackRest Operations

Take full, differential, and incremental backups. Restore databases. Perform PITR
through pgBackRest. By the end of this guide you can operate pgBackRest for any
production backup scenario.

All backup commands run on NODE1 (the pg host initiates backups). Restore
commands run on NODE2 unless noted otherwise.

---

## Backup Types Overview

Before you run any backups, here is what each type does:

- **Full backup**: A complete copy of your entire database. Takes the most time and space, but is self-contained.
- **Differential backup**: Only the data that changed since the last FULL backup. Faster and smaller than full, but needs the full backup to restore.
- **Incremental backup**: Only the data that changed since the last backup of ANY type. Fastest and smallest, but needs the full backup plus all incremental backups in the chain to restore.

---

## 1. Take a full backup

**Run on NODE1 (pg-primary):**

A full backup copies the entire data directory.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Run the full backup. The `--stanza=main` flag tells pgBackRest which configuration stanza to use. The `--type=full` flag requests a complete copy of the database:

```bash
pgbackrest --stanza=main --type=full backup
```

Expected: progress output showing compression and transfer, completing with
`INFO: backup command end: completed successfully`.

```
Expected output (yours will differ):
INFO: backup command begin 2.54.2: ...
INFO: execute backup start: backup begins after the requested immediate checkpoint completes
INFO: backup start archive = 000000010000000100000028, lsn = 1/28000028
...
INFO: new backup label = 20260419-012618F
INFO: full backup size = 4.9GB, file total = 1899
INFO: backup command end: completed successfully (95209ms)
```

Check the backup details. The `info` command shows all backups stored in the repository:

```bash
pgbackrest --stanza=main info
```

Expected: one full backup listed with size, duration, and WAL range.

```
Expected output (yours will differ):
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000100000028/000000010000000100000029

        full backup: 20260419-012618F
            timestamp start/stop: 2026-04-19 01:26:18+00 / 2026-04-19 01:27:53+00
            wal start/stop: 000000010000000100000028 / 000000010000000100000029
            database size: 4.9GB, database backup size: 4.9GB
            repo1: backup set size: 272MB, backup size: 272MB
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Full backup**: A full backup is a complete, standalone copy of
> your database. It does not depend on any other backup. Restoring from a full
> backup is the fastest recovery path because no other backups need to be
> combined. The tradeoff - it takes the longest and uses the most storage.
> Schedule full backups weekly in most production environments.

## 2. Generate data changes for differential/incremental testing

**Run on NODE1 (pg-primary):**

We insert data between backups so the differential and incremental backups have changes to capture. In production, database changes happen naturally from your application.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Insert 50,000 rows. This generates test data that the next backup types can detect as changes:

```bash
psql -d labdb -c "
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime)
SELECT (random() * 32)::int + 1,
       (random() * 32)::int + 1,
       (random() * 32999999)::int + 1,
       (random() * 10000)::int,
       now()
FROM generate_series(1, 50000) g;
"
```

Force a WAL switch to ensure changes are archived. This command tells PostgreSQL to finish the current WAL file and start a new one, triggering archiving:

```bash
psql -c "SELECT pg_switch_wal();"
```

Wait for archiving. This gives pgBackRest time to pick up the new WAL file:

```bash
sleep 3
```

## 3. Take a differential backup

**Run on NODE1 (pg-primary):**

A differential backup captures all changes since the last full backup.

Still as postgres, run the diff backup. The `--type=diff` flag tells pgBackRest to only capture changes since the last full backup:

```bash
pgbackrest --stanza=main --type=diff backup
```

Check the result:

```bash
pgbackrest --stanza=main info
```

Expected: the full backup plus one differential backup. The diff should be
significantly smaller and faster than the full.

```
Expected output (yours will differ):
        diff backup: 20260419-012618F_20260419-012810D
            timestamp start/stop: 2026-04-19 01:28:10+00 / 2026-04-19 01:28:50+00
            wal start/stop: 00000001000000010000002B / 00000001000000010000002C
            database size: 4.9GB, database backup size: 4.1MB
            repo1: backup set size: 272.6MB, backup size: 1MB
            backup reference total: 1 full
```

> **Concept - Differential backup**: A differential backup stores every page
> (8 KB block) that changed since the last full backup. Each diff is
> independent of other diffs - to restore, you need only the full + one diff.
> Diffs grow over time as more pages change. If your diff approaches the size
> of a full backup, it is time for a new full.

## 4. Generate more changes

**Run on NODE1 (pg-primary):**

We insert more data so the incremental backup has additional changes to capture beyond what the differential already recorded.

Still as postgres, insert another 30,000 rows:

```bash
psql -d labdb -c "
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime)
SELECT (random() * 32)::int + 1,
       (random() * 32)::int + 1,
       (random() * 32999999)::int + 1,
       (random() * 10000)::int,
       now()
FROM generate_series(1, 30000) g;
"
```

Force a WAL switch:

```bash
psql -c "SELECT pg_switch_wal();"
```

Wait for archiving:

```bash
sleep 3
```

## 5. Take an incremental backup

**Run on NODE1 (pg-primary):**

An incremental backup captures changes since the last backup of any type
(full, diff, or incr).

Still as postgres, run the incremental backup. The `--type=incr` flag tells pgBackRest to only capture changes since the last backup (regardless of type):

```bash
pgbackrest --stanza=main --type=incr backup
```

Check all backups:

```bash
pgbackrest --stanza=main info
```

Expected: full + diff + incr. The incremental should be the smallest.

```
Expected output (yours will differ):
        incr backup: 20260419-012618F_20260419-012853I
            timestamp start/stop: 2026-04-19 01:28:53+00 / 2026-04-19 01:29:34+00
            database size: 4.9GB, database backup size: 5.5MB
            repo1: backup set size: 272.9MB, backup size: 1.4MB
            backup reference total: 1 full, 1 diff
```

> **Concept - Incremental backup**: An incremental backup stores only the pages
> changed since the last backup (whether full, diff, or incr). This creates a
> chain: full -> diff -> incr -> incr -> incr. To restore from the last incr,
> pgBackRest must combine the full + diff + all incrs in the chain. Incremental
> backups are the fastest and smallest but create longer restore chains.

## 6. Compare backup sizes

**Run on NODE1 (pg-primary):**

Still as postgres, get JSON output and parse it to show backup sizes. This command pipes pgBackRest's JSON output through a Python script that extracts the label, type, sizes, and compression ratio for each backup:

```bash
pgbackrest --stanza=main info --output=json | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
for backup in data[0]['backup']:
    name = backup['label']
    btype = backup['type']
    size = backup['info']['size']
    repo_size = backup['info']['repository']['size']
    ratio = (1 - repo_size/size) * 100 if size > 0 else 0
    print(f'{name}  type={btype}  db_size={size}  repo_size={repo_size}  compression={ratio:.1f}%')
"
```

```
Expected output (yours will differ):
20260419-012618F  type=full  db_size=5232182999  repo_size=285162156  compression=94.5%
20260419-012618F_20260419-012810D  type=diff  db_size=5234788056  repo_size=285812798  compression=94.5%
20260419-012618F_20260419-012853I  type=incr  db_size=5236360920  repo_size=286203159  compression=94.5%
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Full vs diff vs incr - when to use each**:
>
> | Type | Speed | Size | Restore chain | Best for |
> | ---- | ----- | ---- | ------------- | -------- |
> | Full | Slowest | Largest | Self-contained | Weekly baseline |
> | Diff | Medium | Medium | Full + 1 diff | Daily backups |
> | Incr | Fastest | Smallest | Full + diff + all incrs | Hourly backups |
>
> A common production schedule:
> - Sunday: full backup
> - Daily: differential backup
> - Hourly: incremental backup
>
> This gives you hourly recovery points with manageable storage. The worst-case
> restore chain: full + 1 diff + 23 incrs (end of Saturday).

## 7. List and inspect backups

**Run on NODE1 (pg-primary):**

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

List all backups with details:

```bash
pgbackrest --stanza=main info
```

Get JSON output for scripting (useful for monitoring integrations). The `--output=json` flag produces machine-readable output, and `python3 -m json.tool` pretty-prints it. The `head -40` limits output to the first 40 lines:

```bash
pgbackrest --stanza=main info --output=json | python3 -m json.tool | head -40
```

List the backup labels stored in the repository. The `repo-ls` command lists files and directories inside the pgBackRest repository:

```bash
pgbackrest --stanza=main repo-ls backup/main
```

```
Expected output (yours will differ):
20260419-012618F
20260419-012618F_20260419-012810D
20260419-012618F_20260419-012853I
backup.history
backup.info
backup.info.copy
latest
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Monitoring backups**: In production, parse the JSON output with
> your monitoring system. Alert if: no full backup in the last 8 days, no
> diff in the last 2 days, last backup failed, or repository size exceeds
> threshold. pgBackRest's structured output makes this straightforward.

## 8. Restore with pgBackRest - full database

**Run on NODE2 (pg-backup):**

The `--delta` flag tells pgBackRest to check existing files and only restore what is different, instead of requiring an empty data directory. Without `--delta`, pgBackRest would refuse to restore if the data directory contains any files. We clear the data directory first in this section for a clean demo, but `--delta` is still useful because it verifies file integrity during the restore.

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup).**

Stop PostgreSQL. The `systemctl stop` command gracefully shuts down the database service:

```bash
sudo systemctl stop postgresql-16
```

Clear the data directory. This removes all database files so we can do a clean restore:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Switch to the postgres user:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Run the restore. The `--delta` flag compares existing files with the backup and only restores what differs:

```bash
pgbackrest --stanza=main --delta restore
```

Expected: pgBackRest pulls the backup from the repository and reconstructs
the data directory.

```
Expected output (yours will differ):
INFO: restore command begin 2.54.2: ...
INFO: repo1: restore backup set 20260419-012618F_20260419-012853I, recovery will start at ...
INFO: write updated /opt/pgsql/data/postgresql.auto.conf
INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
INFO: restore size = 4.9GB, file total = 1899
INFO: restore command end: completed successfully (41183ms)
```

Verify the restore created a full data directory. The `ls -la` command lists all files with permissions and ownership:

```bash
ls -la /opt/pgsql/data/
```

Expected: full data directory structure.

Exit back to ec2-user:

```bash
exit
```

Start PostgreSQL:

```bash
sudo systemctl start postgresql-16
```

Switch to postgres and verify the data:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Check that all rows are present. The `count(*)` function returns the total number of rows in the table:

```bash
psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"
```

Expected: `33000000` (all rows present from the initial pgbench load).

```
Expected output:
  count
----------
 33000000
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

Exit back to NODE1:

```bash
exit
```

**You are now back on NODE1 (pg-primary).**

> **Concept - Delta restore**: The `--delta` flag tells pgBackRest to compare
> existing files with the backup and only restore files that differ. Without
> `--delta`, pgBackRest requires an empty target directory. Delta is useful
> for refreshing a standby or fixing a partially corrupted data directory
> without re-transferring everything.

## 9. PITR with pgBackRest

**Run on NODE2 (pg-backup) first, then NODE1 (pg-primary), then back to NODE2.**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup).**

Stop PostgreSQL:

```bash
sudo systemctl stop postgresql-16
```

Clear the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Exit back to NODE1:

```bash
exit
```

**You are now back on NODE1 (pg-primary).**

Record the current time on NODE1. This is your "safe" timestamp:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

```bash
psql -c "SELECT now() AS pitr_target_time;"
```

**Write this timestamp down.**

Wait a few seconds, then insert "post-target" data that should not survive the PITR:

```bash
sleep 3
```

Insert rows into the employees table. These rows represent a "mistake" that we want to undo with PITR:

```bash
psql -d appdb -c "
INSERT INTO employees (name, department)
VALUES ('pgbr_should_not_exist_1', 'mistake'),
       ('pgbr_should_not_exist_2', 'mistake');
"
```

Force a WAL switch so the changes are archived:

```bash
psql -c "SELECT pg_switch_wal();"
```

Exit back to ec2-user:

```bash
exit
```

Wait for archiving to complete:

```bash
sleep 5
```

SSH into NODE2 and restore to the target time:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup).**

Switch to postgres:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Run the PITR restore. Replace the `--target` value with the timestamp you recorded above. The `+00` means UTC timezone.

**Use the actual timestamp from YOUR output above - do not copy this example.**

```bash
pgbackrest --stanza=main \
    --delta \
    --type=time \
    --target="2026-04-17 15:30:00+00" \
    --target-action=promote \
    --target-timeline=current \
    restore
```

What each flag means:
- `--delta` = compare existing files and only restore what differs (handles leftover files)
- `--type=time` = recover to a specific point in time
- `--target-timeline=current` = recover along the same timeline as the backup (prevents confusion if earlier PITR exercises created new timelines)
- `--target` = the timestamp to recover to
- `--target-action=promote` = automatically promote to writable after recovery

Exit back to ec2-user:

```bash
exit
```

Start PostgreSQL:

```bash
sudo systemctl start postgresql-16
```

Switch to postgres and verify the recovery:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Check that the "mistake" data does not exist. This query filters for rows with department = 'mistake' - if PITR worked correctly, none should be found:

```bash
psql -d appdb -c "SELECT * FROM employees WHERE department = 'mistake';"
```

Expected: 0 rows. The post-target inserts do not exist.

```
Expected output:
 id | name | department | hired_at
----+------+------------+----------
(0 rows)
```

Verify the instance was automatically promoted. The `pg_is_in_recovery()` function returns `t` (true) if the server is in recovery mode, or `f` (false) if it is a writable primary:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f` (false - promoted automatically because of `--target-action=promote`).

```
Expected output:
 pg_is_in_recovery
-------------------
 f
(1 row)
```

Exit back to ec2-user:

```bash
exit
```

Exit back to NODE1:

```bash
exit
```

**You are now back on NODE1 (pg-primary).**

> **Concept - pgBackRest PITR vs manual PITR**: pgBackRest handles everything
> you did manually in Build 06 - restoring the base backup, configuring
> restore_command, setting recovery targets, and creating recovery.signal. A
> single command replaces a dozen manual steps. The restore_command is
> automatically set to use `pgbackrest archive-get`, which pulls WAL from the
> repository with checksum verification. This is why production environments
> use pgBackRest.

## 10. Restore a specific backup

**Run on NODE1 (pg-primary) first, then NODE2 (pg-backup).**

Switch to postgres on NODE1 to get the backup labels:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

```bash
pgbackrest --stanza=main info
```

Note the full backup label (e.g., `20260417-143000F`).

**Use the actual backup label from YOUR output above - do not copy this example.**

Exit back to ec2-user:

```bash
exit
```

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup).**

Stop PostgreSQL:

```bash
sudo systemctl stop postgresql-16
```

Clear the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Switch to postgres:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Restore from the specific full backup. The `--set` flag tells pgBackRest which backup to restore from instead of using the latest one. The `--target-action=promote` flag makes the server writable after recovery.

**Use the actual backup label from YOUR output above - do not copy this example.**

```bash
pgbackrest --stanza=main \
    --set=20260417-143000F \
    --target-action=promote \
    restore
```

Exit back to ec2-user:

```bash
exit
```

Exit back to NODE1:

```bash
exit
```

**You are now back on NODE1 (pg-primary).**

> **Concept - Backup selection**: By default, pgBackRest restores from the most
> recent backup. The `--set` flag lets you pick a specific backup by label.
> This is useful when the most recent backup is suspected to be corrupted or
> when you need to restore to a point before the latest full backup.

## 11. Verify retention policy

**Run on NODE1 (pg-primary):**

Switch to postgres on NODE1:

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Check what pgBackRest currently retains:

```bash
pgbackrest --stanza=main info
```

The retention settings from `/etc/pgbackrest/pgbackrest.conf`:
- `repo1-retention-full=2` - keep 2 full backups
- `repo1-retention-diff=4` - keep 4 diffs per full

When you take a third full backup, pgBackRest automatically expires the oldest
full and its associated diffs/incrs:

```bash
pgbackrest --stanza=main --type=full backup
```

Check again - the oldest full should be expired:

```
Expected output (yours will differ):
INFO: repo1: 16-1 remove archive, start = 00000001000000010000001B, stop = 000000010000000100000027
INFO: expire command end: completed successfully (2ms)
```

```bash
pgbackrest --stanza=main info
```

Exit back to ec2-user:

```bash
exit
```

> **Concept - Retention management**: pgBackRest automatically enforces
> retention policies. When a full backup expires, all its dependent diffs and
> incrs also expire. WAL segments that are no longer needed by any backup are
> also removed. This prevents unbounded repository growth. Set retention based
> on your RPO (Recovery Point Objective) and compliance requirements.

## 12. Clean up NODE2 for verify script

**Run on NODE2 (pg-backup):**

SSH into NODE2:

```bash
ssh ec2-user@pg-backup
```

**You are now on NODE2 (pg-backup).**

Stop PostgreSQL:

```bash
sudo systemctl stop postgresql-16
```

Clear the data directory:

```bash
sudo rm -rf /opt/pgsql/data/*
```

Exit back to NODE1:

```bash
exit
```

**You are now back on NODE1 (pg-primary).**

Do NOT remove the pgBackRest repository - the verify script checks it.

---

## Checkpoint

- [x] Took a full backup with pgBackRest
- [x] Took a differential backup
- [x] Took an incremental backup
- [x] Understand full vs diff vs incr tradeoffs
- [x] Listed and inspected backups with `pgbackrest info`
- [x] Restored a full database with `--delta`
- [x] Performed PITR with `--type=time --target=...`
- [x] Restored a specific backup with `--set=...`
- [x] Verified retention policy works
- [x] Understand pgBackRest PITR vs manual PITR differences

---

## BUILD COMPLETE

You've built a full PostgreSQL backup and recovery environment from scratch.

**Next step:** Message Happy to let him know you're done with the BUILD phase. He will review your setup and assign you the next exercises.
