# Runbook 04 - Backup Expiry Crisis

**Severity:** High - Only 1 backup exists with WAL archive gaps, recovery window is dangerously narrow
**Time to resolve:** 15-20 minutes (includes time for a new full backup)
**Symptoms:** `pgbackrest info` shows only 1 backup, retention is set to 1, WAL archive has gaps
**Impact:** If the single remaining backup is corrupted or the database fails, you may not be able to recover. WAL gaps mean PITR (point-in-time recovery) is impossible for parts of the timeline.

---

## Layer 1 - Quick Fix

### Step 1: SSH to the server

Log in to your server:

```bash
ssh -i /path/to/your-key.pem ec2-user@[YOUR_SERVER_IP]
```

### Step 2: Switch to the postgres user

```bash
sudo -i -u postgres
```

### Step 3: Check the current backup situation

List all backups:

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 00000001000000000000001A/000000010000000000000025

        full backup: 20260420-141000F
            timestamp start/stop: 2026-04-20 14:10:00 / 2026-04-20 14:12:30
            wal start/stop: 000000010000000000000022 / 000000010000000000000022
            database size: 800MB, database backup size: 800MB
            repo1: backup set size: 120MB, backup size: 120MB
```

Notice there is only 1 full backup. If this backup is bad, you have nothing to fall back on.

> **Concept - Recovery window**: Your recovery window is the time range you can restore to. With 1 backup and WAL gaps, you can only restore to the exact moment of that backup - no point-in-time recovery. With 2+ backups and continuous WAL, you can restore to any point in time between your oldest backup and now.

### Step 4: Check the retention setting

Exit to ec2-user to read the config:

```bash
exit
```

```bash
sudo cat /etc/pgbackrest.conf
```

Expected output (yours will differ):

```
[main]
pg1-path=/opt/pgsql/data
pg1-port=5432

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=1
log-level-console=info
log-level-file=detail
```

The problem: `repo1-retention-full=1`. This means pgBackRest keeps only 1 full backup. Every time a new full backup completes, the previous one is deleted. You are always one bad backup away from zero protection.

> **Concept - Retention count**: `repo1-retention-full=1` means "keep 1 full backup and delete all older ones." When a new full backup finishes, the old one is expired (deleted). If the new backup is corrupted, you have nothing. Production systems should use at least `repo1-retention-full=2` so you always have a fallback.

### Step 5: Fix the retention setting

```bash
sudo vi /etc/pgbackrest.conf
```

Change:

```
repo1-retention-full=1
```

To:

```
repo1-retention-full=2
```

Save and exit vi (press `Esc`, then type `:wq` and press `Enter`).

This tells pgBackRest to keep at least 2 full backups. The oldest full backup is only deleted when a third full backup completes.

### Step 6: Verify the config change

```bash
sudo grep repo1-retention-full /etc/pgbackrest.conf
```

Expected output (yours will differ):

```
repo1-retention-full=2
```

### Step 7: Take a new full backup immediately

Switch to postgres:

```bash
sudo -i -u postgres
```

Take a full backup right now. This is urgent - you need a second backup:

```bash
pgbackrest --stanza=main --type=full backup
```

Expected output (yours will differ):

```
P00   INFO: backup command begin 2.53: ...
P00   INFO: execute non-exclusive backup start: backup begins after ...
P00   INFO: backup stop: ...
P00   INFO: new backup label = 20260420-143000F
P00   INFO: full backup size = 800MB, file total = 1234
P00   INFO: backup command end: completed successfully (125000ms)
```

This takes a few minutes. Wait for it to complete.

> **Concept - Why take a full backup now?** The existing backup may have WAL gaps that prevent PITR. A fresh full backup establishes a new clean baseline. With retention=2, this new backup and the old one will both be kept, giving you redundancy.

### Step 8: Verify you now have 2 backups

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 00000001000000000000001A/00000001000000000000002A

        full backup: 20260420-141000F
            timestamp start/stop: 2026-04-20 14:10:00 / 2026-04-20 14:12:30
            ...

        full backup: 20260420-143000F
            timestamp start/stop: 2026-04-20 14:30:00 / 2026-04-20 14:32:05
            ...
```

You should now see 2 full backups listed.

### Step 9: Verify WAL archiving is continuous from the new backup

Force a WAL switch. Open psql.

```bash
psql
```

Run this query.

```sql
SELECT pg_switch_wal();
```

Wait 5 seconds, then check.

```sql
SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;
```

Expected output (yours will differ):

```
 archived_count | failed_count |     last_archived_wal      |     last_archived_time
----------------+--------------+----------------------------+----------------------------
             35 |            0 | 00000001000000000000002B    | 2026-04-20 14:35:10.123+00
(1 row)
```

Exit psql.

```
\q
```

`last_archived_time` should be within the last minute and `failed_count` should not be increasing.

### Step 10: Run a stanza check

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00   INFO: check command end: completed successfully (205ms)
```

### Step 11: Discuss - what retention is appropriate for production?

This depends on your recovery requirements:

- **Minimum safe**: `repo1-retention-full=2` (always have a fallback)
- **Typical production**: `repo1-retention-full=4` with weekly full backups (1 month of coverage)
- **Regulated industries**: `repo1-retention-full-type=time` with `repo1-retention-full=30` (30 days, regardless of count)

> **Concept - Count vs time-based retention**: Count-based (`repo1-retention-full=2`) keeps a fixed number of backups. Time-based (`repo1-retention-full-type=time` with `repo1-retention-full=30`) keeps all backups within a time window (e.g., 30 days). Time-based is better for compliance because it guarantees a minimum retention period regardless of backup frequency.

Return to ec2-user:

```bash
exit
```

---

## Layer 2 - Concepts

> **Retention policy - count vs time**
> Count-based retention (`repo1-retention-full=2`) is simple: keep N full backups, delete anything older. Time-based retention (`repo1-retention-full-type=time` and `repo1-retention-full=30`) keeps all backups newer than N days. Time-based is safer for production because it adapts to backup schedule changes.

> **WAL continuity and gaps**
> pgBackRest archives WAL segments to the repo alongside backups. For PITR to work, you need an unbroken chain of WAL from the backup's start point to the target recovery time. If WAL files are missing (a "gap"), you can only recover to the exact backup point - not to any arbitrary time. Gaps are silent and deadly.

> **The danger of retention=1**
> With retention=1, you have exactly one backup at any given time. If that backup is corrupted, if the backup disk fails, if someone accidentally deletes it - you have zero protection. There is no fallback. One bad backup means total data loss risk.

> **Monitoring backup age and count**
> Monitor three things: (1) number of full backups in the repo - alert if < 2, (2) age of the newest backup - alert if older than your backup schedule (e.g., > 25 hours for a daily backup), (3) WAL archive continuity - use `pgbackrest verify` to detect gaps.

> **Differential and incremental retention**
> pgBackRest also has `repo1-retention-diff` and `repo1-retention-incr` settings. A typical schedule: weekly full, daily differential, and keep 2 fulls plus 7 diffs. This balances storage cost with recovery granularity.

---

## Layer 3 - Interview Discussion

1. **What retention policy would you recommend for a production database with 1TB of data?** It depends on RPO/RTO requirements, but a common starting point: weekly full backups, daily differentials, retention-full=4 (4 weeks of full backups), retention-diff=7 (7 days of diffs). For the 1TB size, consider compression (pgBackRest compresses by default) and whether the repo can hold 4x 1TB. If storage is tight, use time-based retention with a minimum of 14 days.

2. **How do you monitor that your retention policy is actually being enforced?** Query `pgbackrest info --output=json` on a schedule and parse the backup count and ages. Alert if the count drops below your minimum. Alert if the oldest backup is being retained longer than expected (which might mean new backups are failing). Add `pgbackrest verify` to catch WAL gaps.

3. **A developer sets retention-full=1 because they want to save disk space. How do you explain the risk?** Retention=1 means one bad backup equals total data loss. Ask: "If your next backup is corrupted, how do you recover?" With retention=1, the answer is "you cannot." The cost of storing one extra backup (a few hundred GB) is nothing compared to the cost of losing the entire database. Frame it as insurance.

4. **What is the difference between WAL retention and backup retention?** Backup retention controls how many backup sets are kept. WAL retention (repo1-retention-archive-type, repo1-retention-archive) controls how many WAL archives are kept. By default, pgBackRest keeps WAL for all retained backups. If you expire a backup, its WAL is also eligible for expiry.

5. **Your backup repo is on a single disk. It fails. What is your disaster recovery plan?** This is why multi-repo is critical. Configure repo2 on S3 or a remote server. pgBackRest writes to both repos simultaneously. If repo1 dies, restore from repo2. If you do not have multi-repo, you need to rebuild from scratch: take a new full backup immediately, accept that you have zero PITR coverage until it completes, and implement multi-repo before this happens again.
