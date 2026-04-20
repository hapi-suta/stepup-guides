# Scenario 06 - Restore Wrong Target

**Severity:** HIGH
**Expected Recovery Time:** 15-20 minutes
**Single Server**

---

## Alert

```
HIGH: PITR recovery completed but data verification shows missing records.
May have recovered to wrong point in time.
```

---

## Symptoms

- Database is running after a PITR restore
- Some data exists but other expected records are missing
- Marker rows T2 and T3 are missing - only T1 is present
- employees table is empty, departments table is gone

---

## Impact

- Business data is partially missing
- Recovery was to a point BEFORE critical transactions occurred
- Must re-recover to the correct point without losing the backup chain
- Each incorrect recovery attempt creates a new timeline

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **PITR (Point-in-Time Recovery)** - Restoring a database to a specific moment by replaying WAL records from a base backup up to a target timestamp, transaction ID, or named restore point. The target must fall within the WAL archive window.
- **Timeline** - Each time PostgreSQL recovers, it creates a new timeline (incrementing the timeline ID in WAL file names). This prevents confusion between pre-recovery and post-recovery WAL. pgBackRest tracks timelines and can restore across them.
- **--delta restore** - Instead of wiping PGDATA and restoring everything, pgBackRest compares checksums and only replaces files that differ. Critical for re-recovery because it is much faster than a full restore.
- **--target-action=promote** - Tells PostgreSQL what to do when it reaches the recovery target. `promote` ends recovery and opens the database for read-write. `pause` keeps it in recovery (read-only) so you can verify before promoting. `shutdown` stops PostgreSQL at the target point.
- **Recovery target types** - `--type=time` recovers to a timestamp. `--type=xid` recovers to a transaction ID. `--type=name` recovers to a named restore point created with `pg_create_restore_point()`. `--type=lsn` recovers to a WAL position.

---

## Layer 1 - Quick Fix

### Step 1 - Check what data exists

Log in and look at the current state of the database.

```bash
sudo -i -u postgres
```

The `-p 5432` flag tells psql to connect on port 5432 (the default PostgreSQL port).

```bash
/usr/pgsql-16/bin/psql -p 5432 -d appdb
```

Check the marker rows.

```sql
SELECT * FROM pitr_markers ORDER BY id;
```

Expected output (yours will differ):

```
 id |  label   |          created_at
----+----------+-------------------------------
  1 | MARKER_T1 | 2026-04-20 10:00:00.123456+00
(1 row)
```

Only MARKER_T1 is present. MARKER_T2 and MARKER_T3 are missing - the recovery target was too early.

### Step 2 - Check employees and departments

```sql
SELECT count(*) FROM employees;
```

Expected output (yours will differ):

```
 count
-------
     0
(0 rows)
```

```sql
SELECT count(*) FROM departments;
```

Expected output (yours will differ):

```
ERROR:  relation "departments" does not exist
```

The employees were deleted and departments was dropped AFTER all 3 markers were inserted. We need to recover to a point after T3 but before the destructive commands.

> **Concept: Choosing the right PITR target** - The most common PITR mistake is picking the wrong target. Too early and you lose data that was committed after your target. Too late and you include the destructive event you are trying to undo. Always verify timestamps carefully and consider using `--target-action=pause` first to check before promoting.

### Step 3 - Find the correct target timestamp

The state file from the injection contains the correct target.

```
\q
```

```bash
exit
```

Read the state file to find the correct timestamp.

```bash
cat /tmp/chaos-06-state.env
```

Expected output (yours will differ):

```
MARKER_T1=2026-04-20 10:00:00.123456+00
MARKER_T2=2026-04-20 10:00:10.234567+00
MARKER_T3=2026-04-20 10:00:20.345678+00
CORRECT_TARGET=2026-04-20 10:00:21.345678+00
INJECT_TIMESTAMP=1745146821
```

The `CORRECT_TARGET` is 1 second after MARKER_T3 - this captures all 3 markers and the original employee/department data, but stops before the destructive DELETE and DROP.

### Step 4 - Stop PostgreSQL

```bash
sudo systemctl stop postgresql-16
```

Verify it is stopped. The `|` (pipe) sends the output of the first command as input to the second.

```bash
sudo systemctl status postgresql-16 | head -5
```

Expected output (yours will differ):

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded
     Active: inactive (dead)
...
```

> **Concept: Why stop before re-restore** - pgBackRest's `--delta` restore modifies files in PGDATA. PostgreSQL must be stopped or it will detect the changes and crash. Always stop PostgreSQL before running a restore.

### Step 5 - Re-restore with the correct PITR target

Use the CORRECT_TARGET timestamp from the state file. Replace the timestamp below with the actual value from your state file.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main --delta --type=time --target="2026-04-20 10:00:21.345678+00" --target-action=promote restore
```

Expected output (yours will differ):

```
...
P00   INFO: restore command end: completed successfully
```

> **Concept: --delta for re-recovery** - The `--delta` flag is critical when re-restoring. Without it, pgBackRest requires PGDATA to be empty. With `--delta`, it checksums existing files and only replaces those that differ from the backup. This makes re-recovery much faster - especially on large databases where most data files have not changed.

```bash
exit
```

### Step 6 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

Wait a few seconds for recovery replay to complete.

```bash
sudo systemctl status postgresql-16 | head -5
```

Expected output (yours will differ):

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded
     Active: active (running)
...
```

### Step 7 - Verify all 3 markers exist

```bash
sudo -i -u postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d appdb
```

```sql
SELECT * FROM pitr_markers ORDER BY id;
```

Expected output (yours will differ):

```
 id |   label   |          created_at
----+-----------+-------------------------------
  1 | MARKER_T1 | 2026-04-20 10:00:00.123456+00
  2 | MARKER_T2 | 2026-04-20 10:00:10.234567+00
  3 | MARKER_T3 | 2026-04-20 10:00:20.345678+00
(3 rows)
```

All 3 markers are present. The recovery target was correct.

### Step 8 - Verify employees and departments

```sql
SELECT count(*) FROM employees;
```

Expected output (yours will differ):

```
 count
-------
    50
(1 row)
```

```sql
SELECT count(*) FROM departments;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

Both tables have their data back.

### Step 9 - Exit psql and postgres user

```
\q
```

```bash
exit
```

### Step 10 - Take a new full backup

After a PITR recovery, the database is on a new timeline. Take a fresh full backup to establish a new backup chain.

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main --type=full backup
```

Expected output (yours will differ):

```
...
P00   INFO: new backup label = 20260420-101500F
P00   INFO: full backup size = 850MB
P00   INFO: backup command end: completed successfully
```

> **Concept: Backup after recovery** - After PITR, the database is on a new timeline. Old backups are on the previous timeline. While pgBackRest can handle cross-timeline restores, taking a fresh full backup immediately after recovery gives you a clean starting point and simplifies future recovery operations.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected output (yours will differ):

```
[PASS] PostgreSQL is running
[PASS] MARKER_T1 exists in appdb
[PASS] MARKER_T2 exists in appdb
[PASS] MARKER_T3 exists in appdb
[PASS] employees table has data
[PASS] departments table exists with data
[PASS] Backup taken after recovery
Result: ALL CHECKS PASSED
```

---

## Layer 2 - Concepts

### Timeline Divergence

Every PITR recovery creates a new timeline. If you recover twice (first to the wrong target, then to the correct one), you create two new timelines. PostgreSQL tracks these in timeline history files in pg_wal/. The timeline ID is the first 8 hex characters of WAL file names (e.g., `00000002` for timeline 2).

### Multiple Recovery Attempts

You can attempt PITR multiple times from the same backup. Each attempt:
1. Stops PostgreSQL
2. Runs pgbackrest restore with `--delta`
3. Starts PostgreSQL (which replays WAL to the target)
4. Creates a new timeline

The `--delta` flag is what makes this practical. Without it, you would need to wipe PGDATA each time.

### Why --target-action Matters

- `promote` - Opens the database for writes immediately. Use when you are confident in the target.
- `pause` - Keeps the database in read-only recovery mode. You can query the data to verify it looks correct, then run `SELECT pg_wal_replay_resume()` to promote. Safest option for critical recoveries.
- `shutdown` - Stops PostgreSQL cleanly at the target point. Useful for migration scenarios.

### Pre-Recovery Checklist

Before any PITR:
1. Confirm the backup is valid: `pgbackrest info`
2. Confirm WAL archives exist for the target window
3. Double-check the target timestamp (timezone matters)
4. Consider using `--target-action=pause` first
5. Document the current timeline and backup label

---

## Layer 3 - Interview Discussion Points

1. **How do you determine the correct PITR target timestamp?** - Check application logs for the exact time of the destructive event. Use `pg_stat_activity` history if pg_stat_statements is enabled. Check PostgreSQL logs for the DDL/DML timestamps. If you have pgAudit, check the audit log. Always subtract a small margin (seconds) from the destructive event time. When in doubt, use `--target-action=pause` and verify before promoting.

2. **What is the difference between --type=time and --type=xid for PITR?** - `--type=time` uses a wall-clock timestamp and recovers to the last transaction committed before that time. `--type=xid` uses a transaction ID and recovers to include that specific transaction. XID is more precise but harder to find. Time is more practical but affected by clock skew in multi-node setups. For single-server pgBackRest, time is usually sufficient.

3. **Why is --delta important for re-recovery?** - Without `--delta`, pgBackRest requires PGDATA to be completely empty before restoring. With `--delta`, it checksums every file in PGDATA and only replaces files that differ from the backup. This means re-recovery of a 500 GB database might only transfer 50 MB of changed files instead of the full 500 GB. It turns a 2-hour operation into a 2-minute one.

4. **What happens to replication slots after PITR recovery?** - Physical replication slots are preserved in the backup but point to WAL positions on the old timeline. After recovery, standbys using those slots will likely fail to connect. You need to drop and recreate the slots, then rebuild the standbys (or use pg_rewind if the timeline divergence is small).

5. **A developer asks you to recover "to 5 minutes ago" on a 2 TB database. What questions do you ask first?** - (a) What exactly happened 5 minutes ago? We need the precise event to avoid. (b) Can we verify the target on a standby or clone first? (c) What is the acceptable downtime? (d) Are there any replication slots or standbys that will be affected? (e) When was the last backup and is the WAL chain intact? (f) Can we extract just the affected data instead of full PITR (e.g., restore to a separate instance and copy back specific tables)?
