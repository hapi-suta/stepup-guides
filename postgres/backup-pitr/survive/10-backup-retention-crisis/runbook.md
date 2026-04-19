# Runbook 10 - Backup Retention Crisis

**Severity:** Critical - No valid backups exist, zero recovery capability
**Time to resolve:** 15-25 minutes

---

## Fix Path

### Step 1: Assess the damage

SSH to [NODE1] and check pgBackRest status:

```bash
sudo -u postgres pgbackrest --stanza=main info
sudo -u postgres pgbackrest --stanza=main verify
```

Expected: No valid backups, errors about corrupt or missing data.

> **Concept - Single Point of Failure**: Having only one backup method with retention of 1 means a single corruption event can eliminate all your backups. This is why the 3-2-1 rule exists: 3 copies, 2 media types, 1 offsite.

### Step 2: Verify the database is still running

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready -p 5432
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM employees;"
```

The database is still alive - this is your only source of data. Protect it.

### Step 3: Take an immediate pg_basebackup

Since pgBackRest is broken, fall back to pg_basebackup:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_basebackup \
  -p 5432 \
  -D /opt/pgsql/backup/basebackup-emergency \
  -Ft -z \
  -P --checkpoint=fast
```

This creates a tar-format, compressed base backup of the entire cluster.

Verify the backup:

```bash
ls -lh /opt/pgsql/backup/basebackup-emergency/
```

Expected: base.tar.gz and pg_wal.tar.gz files.

> **Concept - pg_basebackup**: This is PostgreSQL's built-in physical backup tool. It copies the entire data directory over a replication connection. It does not require pgBackRest and works with any PostgreSQL installation. It is slower and less feature-rich than pgBackRest but is always available.

### Step 4: Take logical dumps of all databases

```bash
# labdb with custom format
sudo -u postgres /usr/pgsql-16/bin/pg_dump -p 5432 -d labdb -Fc -f /opt/pgsql/backup/dumps/labdb.custom

# appdb
sudo -u postgres /usr/pgsql-16/bin/pg_dump -p 5432 -d appdb -Fc -f /opt/pgsql/backup/dumps/appdb.custom

# blobdb
sudo -u postgres /usr/pgsql-16/bin/pg_dump -p 5432 -d blobdb -Fc -f /opt/pgsql/backup/dumps/blobdb.custom

# Full cluster dump (roles, tablespaces, etc.)
sudo -u postgres /usr/pgsql-16/bin/pg_dumpall -p 5432 -f /opt/pgsql/backup/dumps/full-cluster.sql
```

Verify each dump:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/labdb.custom | head -10
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/appdb.custom | head -10
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/blobdb.custom | head -10
```

Expected: Clean table-of-contents output for each dump.

### Step 5: Fix pgBackRest retention and take a fresh backup

Fix the retention setting:

```bash
sudo nano /etc/pgbackrest.conf
# Set repo1-retention-full=2 (or higher)
```

Clean up the corrupted backup:

```bash
# Remove corrupt backup entries
sudo rm -rf /opt/pgsql/backup/pgbackrest/backup/main/*

# Recreate the stanza
sudo -u postgres pgbackrest --stanza=main stanza-create
```

Take a new full backup:

```bash
sudo -u postgres pgbackrest --stanza=main --type=full backup
```

Verify:

```bash
sudo -u postgres pgbackrest --stanza=main info
sudo -u postgres pgbackrest --stanza=main check
```

Expected: One valid full backup, check passes.

> **Concept - stanza-create vs stanza-upgrade**: `stanza-create` initializes a new stanza in the repository. Use it when starting fresh. `stanza-upgrade` updates an existing stanza after a PostgreSQL major version upgrade.

### Step 6: Verify WAL archiving is working

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -c "SELECT pg_switch_wal();"
sleep 5
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -c "
  SELECT last_archived_wal, last_archived_time, failed_count
  FROM pg_stat_archiver;
"
```

Expected: Recent archive time, failed_count stable.

### Step 7: Document the backup inventory

Verify you now have multiple backup methods working:

```bash
# pgBackRest
sudo -u postgres pgbackrest --stanza=main info

# pg_basebackup
ls -lh /opt/pgsql/backup/basebackup-emergency/

# Logical dumps
ls -lh /opt/pgsql/backup/dumps/
```

All three should show valid, recent backups.

---

## Key Concepts for Revision

- **3-2-1 backup rule**: 3 copies, 2 different media/methods, 1 offsite. This scenario demonstrates why relying on a single backup method is dangerous.
- **retention-full=1** is the minimum and most dangerous setting. A single corruption or failed backup leaves you with zero recovery capability.
- **pg_basebackup** is always available as a fallback. It does not need any external tools - just a replication connection. Every DBA should know how to use it.
- **pg_dump/pg_dumpall** provides logical backups that are independent of the physical backup chain. They can restore individual databases or tables and are portable across PostgreSQL versions.
- **Defense in depth**: Physical backups (pgBackRest, pg_basebackup) + logical backups (pg_dump) + WAL archiving provide overlapping recovery capabilities. Each covers failure modes the others do not.
- **stanza-create** reinitializes the pgBackRest repository. This is necessary after manually removing all backup data from the repository.
- **Backup verification** after creation is not optional. Every backup should be verified (pg_restore --list for dumps, pgbackrest verify for physical backups) immediately after creation.

---

## Interview Discussion Points

1. **Backup strategy design**: If you were designing a backup strategy from scratch for a 1 TB production database, what methods would you use? What retention would you set? How would you verify backups?

2. **Retention policy tradeoffs**: What factors determine backup retention? (Compliance requirements, storage cost, recovery point objectives, recovery time objectives.) How do you justify the cost of keeping more backups?

3. **Backup method comparison**: Compare pgBackRest, pg_basebackup, and pg_dump across these dimensions: speed, restore time, granularity, portability, complexity, storage efficiency.

4. **Disaster recovery vs backup**: What is the difference between a backup and a disaster recovery plan? How does this scenario highlight the gap between "having backups" and "being able to recover"?

5. **Single point of failure analysis**: Walk through all the single points of failure in a typical backup pipeline. Where can a single failure eliminate all recovery capability?

6. **Backup monitoring and alerting**: What alerts would have prevented this scenario from becoming a crisis? (Backup count < 2, backup age > 24h, verification failures, retention changes.)

7. **Compliance and audit**: In a SOC 2 or PCI-DSS environment, how do you prove your backup strategy is adequate? What evidence do auditors want to see?

8. **Cost of downtime**: The database is running but you have zero backups. What is the business risk? How do you communicate this to management? What is the cost of NOT having backups vs the cost of maintaining them?
