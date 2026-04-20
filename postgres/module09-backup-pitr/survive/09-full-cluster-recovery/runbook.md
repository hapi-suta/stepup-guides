# Runbook 09 - Full Cluster Recovery

**Severity:** Critical - Complete database outage, all data unavailable
**Time to resolve:** 20-30 minutes

---

## Fix Path

### Step 1: Assess the damage

SSH to [NODE1] and confirm PostgreSQL is down.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Check if PostgreSQL is responding:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected: "no response" or connection refused.

Check if the data directory exists:

```bash
ls -la /opt/pgsql/data/
```

Expected: Directory does not exist or is empty.

### Step 2: Verify pgBackRest backups are available

```bash
pgbackrest --stanza=main info
```

Expected: At least one valid full backup is listed. Note the most recent backup timestamp.

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000008

        full backup: 20260419-140000F
            timestamp start/stop: 2026-04-19 14:00:00 / 2026-04-19 14:05:32
            wal start/stop: 000000010000000000000003 / 000000010000000000000003
            database size: 45.2MB, database backup size: 45.2MB
            ...
```

If pgbackrest info fails because the config references the missing data directory:

```bash
# Check the config
cat /etc/pgbackrest/pgbackrest.conf
```

```bash
# pgBackRest info should still work since it reads from the repo
pgbackrest --stanza=main info --output=json
```

> **Concept - Backup Independence**: pgBackRest stores backups independently of the PostgreSQL data directory. Even if the entire data directory is destroyed, backups in the repo are unaffected. This is why the repo should always be on a separate filesystem or remote storage.

### Step 3: Create the empty data directory

PostgreSQL needs the data directory to exist with correct ownership before restore.

Exit the postgres user to run commands as root:

```bash
exit
```

Create the data directory:

```bash
sudo mkdir -p /opt/pgsql/data
```

Set the correct ownership so postgres can access it:

```bash
sudo chown postgres:postgres /opt/pgsql/data
```

Set permissions to 700 - PostgreSQL refuses to start if the data directory is world-readable:

```bash
sudo chmod 700 /opt/pgsql/data
```

Switch back to the postgres user:

```bash
sudo -iu postgres
```

### Step 4: Restore from pgBackRest

```bash
pgbackrest --stanza=main \
  --delta \
  restore
```

The `--delta` flag tells pgBackRest to restore files that are missing or different. Since the directory is empty, it will restore everything.

This will take several minutes depending on database size. Monitor:

```bash
# In another terminal
sudo tail -f /var/log/pgbackrest/main-restore.log
```

> **Concept - pgBackRest Restore Types**: `--type=default` restores to the latest consistent point. `--type=time` restores to a specific timestamp. `--type=immediate` stops at the first consistent point after backup. For full cluster recovery, `default` is usually correct - it replays all available WAL.

### Step 5: Start PostgreSQL

Exit the postgres user to run systemctl:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

Check the logs for any errors during startup:

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Switch back to the postgres user:

```bash
sudo -iu postgres
```

Verify PostgreSQL is running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

### Step 6: Verify all databases exist

```bash
/usr/pgsql-16/bin/psql -p 5432 -c "\l"
```

Confirm all expected databases are listed (stepup_store, postgres, and any others that existed before).

Expected output (yours will differ):

```
                                                   List of databases
     Name      |  Owner   | Encoding | Locale Provider |   Collate   |    Ctype    | Access privileges
---------------+----------+----------+-----------------+-------------+-------------+-------------------
 postgres      | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |
 stepup_store  | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |
 template0     | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 | =c/postgres      +
               |          |          |                 |             |             | postgres=CTc/postgres
 template1     | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 | =c/postgres      +
               |          |          |                 |             |             | postgres=CTc/postgres
(4 rows)
```

### Step 7: Verify data integrity

Check the employees table row count:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT count(*) FROM employees;"
```

Check all public tables:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "\dt"
```

Run a sample query to verify data is readable:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT * FROM employees LIMIT 5;"
```

### Step 8: Reconfigure pgBackRest and take a fresh backup

After recovery, ensure pgBackRest is properly configured:

```bash
pgbackrest --stanza=main check
```

If the stanza needs updating:

```bash
pgbackrest --stanza=main stanza-upgrade
```

Take a fresh backup to protect the recovered state:

```bash
pgbackrest --stanza=main --type=full backup
```

### Step 9: Verify archiving works

```bash
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT pg_switch_wal();"
```

Wait a few seconds, then check:

```bash
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT * FROM pg_stat_archiver;"
```

Confirm last_archived_time is recent and no new failures.

### Step 10: Clean up destroyed directory

Exit the postgres user:

```bash
exit
```

Once you have confirmed the recovery is complete:

```bash
sudo rm -rf /opt/pgsql/data.destroyed
```

---

## Key Concepts for Revision

- **Full cluster recovery** is the worst-case scenario. Every DBA should practice this regularly so they can execute it under pressure at 3 AM.
- **Data directory permissions**: PostgreSQL requires the data directory to be owned by the postgres user with mode 700. Incorrect permissions prevent startup.
- **pgBackRest --delta** restores only files that are missing or changed. On an empty directory, it restores everything. On a partially damaged directory, it replaces only the damaged files.
- **WAL replay during recovery**: After restoring the base backup, PostgreSQL replays archived WAL segments to bring the cluster to the latest consistent state. This is automatic.
- **stanza-upgrade** is needed after a PostgreSQL major version upgrade or when the catalog version changes. For a same-version recovery, it is usually not required.
- **Recovery timeline**: After recovery, PostgreSQL starts a new timeline. This is important for replication - standbys may need to be rebuilt.
- **Post-recovery backup**: Always take a fresh full backup immediately after recovery. The restored cluster is now your baseline.

---

## Interview Discussion Points

1. **Recovery time estimation**: Your production database is 500 GB with 100 GB of WAL to replay. How long will a full cluster recovery take? What hardware factors affect this?

2. **Parallel recovery**: How does pgBackRest's `--process-max` option speed up restores? What is the bottleneck - network, disk I/O, or CPU?

3. **Standby rebuild after recovery**: After recovering the primary, what happens to standbys? Can they reconnect automatically or must they be rebuilt?

4. **Recovery testing**: How often should you test full cluster recovery? What does a recovery drill look like? Do you do it in production or in a staging environment?

5. **Split-brain prevention**: During recovery, how do you prevent the old primary (if it comes back) from accepting writes? How do you handle fencing?

6. **Multi-database clusters**: If a cluster has 10 databases but only one is critical, can you restore just that one? What are the tradeoffs of single-database vs full-cluster restore?

7. **Cloud DR scenarios**: In AWS, your EBS volume dies. You have pgBackRest backups in S3. Walk through the full recovery process - launch new instance, install PG, configure pgBackRest, restore.
