# Runbook 01 - pgBackRest Stanza Misconfigured

**Severity:** Critical - Backups and WAL archiving are broken
**Time to resolve:** 5-10 minutes
**Symptoms:** `pgbackrest check` fails, backup jobs fail, WAL archive errors in PostgreSQL logs
**Impact:** No new backups can be taken. WAL files pile up in pg_wal. Recovery point objective (RPO) is growing every minute.

---

## Layer 1 - Quick Fix

### Step 1: SSH to the server

Log in to your server:

```bash
ssh -i /path/to/your-key.pem ec2-user@[YOUR_SERVER_IP]
```

### Step 2: Switch to the postgres user

pgBackRest runs as the postgres OS user. Switch to that user:

```bash
sudo -i -u postgres
```

This logs you in as postgres with the correct environment variables loaded.

### Step 3: Run a stanza check

The `check` command validates the entire pgBackRest configuration - the config file, PostgreSQL connectivity, and WAL archiving:

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
ERROR: [041]: unable to load info file '/opt/pgsql/WRONG_DATA/PG_VERSION' or
       '/opt/pgsql/WRONG_DATA/PG_VERSION.copy':
       FileOpenError: unable to open file '/opt/pgsql/WRONG_DATA/PG_VERSION'
       for read: [2] No such file or directory
```

The error says pgBackRest is looking for PostgreSQL data in `/opt/pgsql/WRONG_DATA` - that directory does not exist.

### Step 4: Look at the pgBackRest config file

Exit back to ec2-user first (we need sudo to read the config):

```bash
exit
```

Now read the config file:

```bash
sudo cat /etc/pgbackrest.conf
```

Expected output (yours will differ):

```
[main]
pg1-path=/opt/pgsql/WRONG_DATA
pg1-port=5432

[global]
repo1-path=/opt/pgsql/backup/pgbackrest
repo1-retention-full=2
log-level-console=info
log-level-file=detail
```

The problem is `pg1-path=/opt/pgsql/WRONG_DATA`. This tells pgBackRest where your PostgreSQL data directory lives - but that path is wrong.

> **Concept - pg1-path**: This is the most important setting in pgbackrest.conf. It tells pgBackRest where PostgreSQL keeps its data files. If this path is wrong, pgBackRest cannot read the data it needs to back up and cannot verify that archiving works.

### Step 5: Find the correct data directory

Switch back to postgres to check:

```bash
sudo -i -u postgres
```

Ask PostgreSQL where its data directory actually is. Open psql.

```bash
psql
```

Run this query.

```sql
SHOW data_directory;
```

Expected output (yours will differ):

```
   data_directory
--------------------
 /opt/pgsql/data
(1 row)
```

Exit psql.

```
\q
```

The correct path is `/opt/pgsql/data` - not `/opt/pgsql/WRONG_DATA`.

Exit back to ec2-user for the fix:

```bash
exit
```

### Step 6: Fix the config file

Open the config file in vi:

```bash
sudo vi /etc/pgbackrest.conf
```

Find the line that says:

```
pg1-path=/opt/pgsql/WRONG_DATA
```

Change it to:

```
pg1-path=/opt/pgsql/data
```

Save and exit vi (press `Esc`, then type `:wq` and press `Enter`).

> **Concept - Config edits take effect immediately**: pgBackRest reads its config file fresh every time it runs. There is no service to restart. Your next pgbackrest command will use the updated config.

### Step 7: Verify the fix

Switch to postgres and run the check again:

```bash
sudo -i -u postgres
```

```bash
pgbackrest --stanza=main check
```

Expected output (yours will differ):

```
P00   INFO: check command end: completed successfully (205ms)
```

The check passed. pgBackRest can now see your PostgreSQL data directory.

### Step 8: Verify backup info is accessible

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000020

        full backup: 20260420-120000F
            timestamp start/stop: 2026-04-20 12:00:00 / 2026-04-20 12:05:30
            wal start/stop: 000000010000000000000010 / 000000010000000000000010
            database size: 800MB, database backup size: 800MB
            ...
```

### Step 9: Check WAL archiving is working

Force a WAL segment switch and verify it gets archived. Open psql.

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
             25 |            0 | 000000010000000000000021    | 2026-04-20 14:30:15.123+00
(1 row)
```

The `failed_count` should not be increasing and `last_archived_time` should be recent (within the last minute).

Exit psql.

```
\q
```

> **Concept - pg_stat_archiver**: This system view tracks WAL archiving health. Check `failed_count` for errors and `last_archived_time` for freshness. If archiving is broken, `failed_count` climbs and `last_archived_time` goes stale.

Return to ec2-user:

```bash
exit
```

---

## Layer 2 - Concepts

> **What is pg1-path?**
> pg1-path tells pgBackRest the filesystem path to your PostgreSQL data directory (PGDATA). pgBackRest needs this to read data files during backups, verify checksums, and confirm that the archive_command is configured correctly. If pg1-path is wrong, pgBackRest has no idea where your database lives.

> **How stanza-check validates the config**
> When you run `pgbackrest --stanza=main check`, it does several things: reads pgbackrest.conf, connects to PostgreSQL at pg1-path, confirms the PostgreSQL version matches, verifies archive_command is set, and tests that a WAL segment can be archived. It is an end-to-end health check - not just a syntax check.

> **Why config errors are dangerous**
> A wrong pg1-path does not crash PostgreSQL. Your database keeps running fine. But backups silently stop working. WAL archiving fails. You only discover the problem when you need to restore - and by then it is too late. This is why monitoring pgbackrest check output is critical.

> **Backup metadata vs actual data**
> pgBackRest stores backup metadata (manifests, info files) separately from the actual backup data. The config file tells it where to find both PostgreSQL (pg1-path) and the backup repo (repo1-path). Both must be correct.

> **Config file location**
> By default, pgBackRest looks for its config at `/etc/pgbackrest.conf`. You can override this with `--config=/path/to/file` or the `PGBACKREST_CONFIG` environment variable. In production, use configuration management (Ansible, etc.) to prevent drift.

---

## Layer 3 - Interview Discussion

1. **How do you validate pgBackRest config after changes?** Run `pgbackrest --stanza=main check` after every config edit. This is an end-to-end test - not just a syntax check. It verifies PostgreSQL connectivity, data directory access, and WAL archiving. Add it to your change management checklist.

2. **What monitoring would catch this before a human notices?** Monitor `pgbackrest check` exit code on a schedule (cron or your monitoring tool). Also monitor `pg_stat_archiver.failed_count` - if it starts climbing, archiving is broken. Alert on backup age too - if the newest backup is older than your SLA, something is wrong.

3. **What happens to WAL archiving when the stanza is misconfigured?** PostgreSQL's archive_command calls pgbackrest, which reads the config file. If pg1-path is wrong, the archive-push command fails. PostgreSQL retries archive_command every `archive_timeout` seconds (default 60s). Failed WAL files pile up in pg_wal. If pg_wal fills the disk, PostgreSQL crashes.

4. **How would you prevent this in production?** Use configuration management (Ansible/Puppet) to template pgbackrest.conf from a single source of truth. Add a post-deploy hook that runs `pgbackrest check`. Store the config in version control. Never edit production configs by hand without a review process.

5. **A new DBA accidentally changes pg1-path during a config cleanup. How long until you know?** Depends on your monitoring interval. If you check pgbackrest health every 5 minutes, you know within 5 minutes. If you only check when backups run (e.g., nightly), you might not know for 24 hours. Continuous monitoring is the difference between a 5-minute fix and a disaster.
