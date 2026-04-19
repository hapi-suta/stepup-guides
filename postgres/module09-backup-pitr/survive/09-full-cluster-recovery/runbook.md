# Runbook 09 - Full Cluster Recovery

**Severity:** Critical - Complete database outage, all data unavailable
**Time to resolve:** 20-30 minutes

---

## Fix Path

### Step 1: Assess the damage

SSH to [NODE1] and confirm PostgreSQL is down:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready -p 5432
```

Expected: "no response" or connection refused.

Check if the data directory exists:

```bash
ls -la /opt/pgsql/data/
```

Expected: Directory does not exist or is empty.

### Step 2: Verify pgBackRest backups are available

```bash
sudo -u postgres pgbackrest --stanza=main info
```

Expected: At least one valid full backup is listed. Note the most recent backup timestamp.

If pgbackrest info fails because the config references the missing data directory:

```bash
# Check the config
cat /etc/pgbackrest.conf

# pgBackRest info should still work since it reads from the repo
sudo -u postgres pgbackrest --stanza=main info --output=json
```

> **Concept - Backup Independence**: pgBackRest stores backups independently of the PostgreSQL data directory. Even if the entire data directory is destroyed, backups in the repo are unaffected. This is why the repo should always be on a separate filesystem or remote storage.

### Step 3: Create the empty data directory

PostgreSQL needs the data directory to exist with correct ownership before restore:

```bash
sudo mkdir -p /opt/pgsql/data
sudo chown postgres:postgres /opt/pgsql/data
sudo chmod 700 /opt/pgsql/data
```

### Step 4: Restore from pgBackRest

```bash
sudo -u postgres pgbackrest --stanza=main \
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

```bash
sudo systemctl start postgresql-16
```

Check the logs for any errors during startup:

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Verify PostgreSQL is running:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready -p 5432
```

### Step 6: Verify all databases exist

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -c "\l"
```

Confirm all expected databases are listed (labdb, postgres, and any others that existed before).

### Step 7: Verify data integrity

```bash
# Check employees table
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM employees;"

# Check all public tables
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "\dt"

# Run a sample query to verify data is readable
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT * FROM employees LIMIT 5;"
```

### Step 8: Reconfigure pgBackRest and take a fresh backup

After recovery, ensure pgBackRest is properly configured:

```bash
sudo -u postgres pgbackrest --stanza=main check
```

If the stanza needs updating:

```bash
sudo -u postgres pgbackrest --stanza=main stanza-upgrade
```

Take a fresh backup to protect the recovered state:

```bash
sudo -u postgres pgbackrest --stanza=main --type=full backup
```

### Step 9: Verify archiving works

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -c "SELECT pg_switch_wal();"
```

Wait a few seconds, then check:

```sql
SELECT * FROM pg_stat_archiver;
```

Confirm last_archived_time is recent and no new failures.

### Step 10: Clean up destroyed directory

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
