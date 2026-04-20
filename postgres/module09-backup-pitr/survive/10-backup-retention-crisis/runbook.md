# Runbook 10 - Backup Retention Crisis

**Severity:** Critical - No valid backups exist, zero recovery capability
**Time to resolve:** 15-25 minutes

---

## Fix Path

### Step 1: Assess the damage

SSH to [NODE1] and check pgBackRest status.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Check the current backup inventory:

```bash
pgbackrest --stanza=main info
```

Verify backup integrity:

```bash
pgbackrest --stanza=main verify
```

Expected: No valid backups, errors about corrupt or missing data.

> **Concept - Single Point of Failure**: Having only one backup method with retention of 1 means a single corruption event can eliminate all your backups. This is why the 3-2-1 rule exists: 3 copies, 2 media types, 1 offsite.

### Step 2: Verify the database is still running

Check if PostgreSQL is responding:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Confirm data is still accessible:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT count(*) FROM employees;"
```

The database is still alive - this is your only source of data. Protect it.

### Step 3: Take an immediate pg_basebackup

Since pgBackRest is broken, fall back to pg_basebackup:

```bash
/usr/pgsql-16/bin/pg_basebackup \
  -p 5432 \
  -D /opt/pgsql/backup/basebackup-emergency \
  -Ft -z \
  -P --checkpoint=fast
```

Flag breakdown:
- `-Ft` - Output in tar format (one .tar file per tablespace, easier to store and transfer)
- `-z` - Compress the tar files with gzip (saves disk space)
- `-P` - Show progress during the backup (percentage complete and throughput)
- `--checkpoint=fast` - Request an immediate checkpoint instead of waiting for the next scheduled one (starts the backup faster but causes a brief I/O spike)

Expected output (yours will differ):

```
89522/89522 kB (100%), 1/1 tablespace
```

This creates a tar-format, compressed base backup of the entire cluster.

Verify the backup:

```bash
ls -lh /opt/pgsql/backup/basebackup-emergency/
```

Expected: base.tar.gz and pg_wal.tar.gz files.

> **Concept - pg_basebackup**: This is PostgreSQL's built-in physical backup tool. It copies the entire data directory over a replication connection. It does not require pgBackRest and works with any PostgreSQL installation. It is slower and less feature-rich than pgBackRest but is always available.

### Step 4: Take logical dumps of all databases

Dump stepup_store in custom format (supports selective restore of individual tables):

```bash
/usr/pgsql-16/bin/pg_dump -p 5432 -d stepup_store -Fc -f /opt/pgsql/backup/dumps/stepup_store.custom
```

Dump the appdb database:

```bash
/usr/pgsql-16/bin/pg_dump -p 5432 -d appdb -Fc -f /opt/pgsql/backup/dumps/appdb.custom
```

Dump the blobdb database:

```bash
/usr/pgsql-16/bin/pg_dump -p 5432 -d blobdb -Fc -f /opt/pgsql/backup/dumps/blobdb.custom
```

Dump the full cluster including roles, tablespaces, and all databases:

```bash
/usr/pgsql-16/bin/pg_dumpall -p 5432 -f /opt/pgsql/backup/dumps/full-cluster.sql
```

Verify the stepup_store dump by listing its table of contents:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/stepup_store.custom | head -10
```

Verify the appdb dump:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/appdb.custom | head -10
```

Verify the blobdb dump:

```bash
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/blobdb.custom | head -10
```

Expected: Clean table-of-contents output for each dump.

### Step 5: Fix pgBackRest retention and take a fresh backup

Exit the postgres user to edit the config as root:

```bash
exit
```

Fix the retention setting:

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
# Set repo1-retention-full=2 (or higher)
```

Clean up the corrupted backup:

```bash
# Remove corrupt backup entries
sudo rm -rf /opt/pgsql/backup/pgbackrest/backup/main/*
```

Switch back to the postgres user:

```bash
sudo -iu postgres
```

Recreate the stanza:

```bash
pgbackrest --stanza=main stanza-create
```

Take a new full backup:

```bash
pgbackrest --stanza=main --type=full backup
```

Verify the backup exists:

```bash
pgbackrest --stanza=main info
```

Expected output (yours will differ):

```
stanza: main
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000010/000000010000000000000012

        full backup: 20260419-160000F
            timestamp start/stop: 2026-04-19 16:00:00 / 2026-04-19 16:04:18
            wal start/stop: 000000010000000000000011 / 000000010000000000000011
            database size: 45.2MB, database backup size: 45.2MB
            ...
```

Verify the backup passes integrity checks:

```bash
pgbackrest --stanza=main check
```

Expected: One valid full backup, check passes.

> **Concept - stanza-create vs stanza-upgrade**: `stanza-create` initializes a new stanza in the repository. Use it when starting fresh. `stanza-upgrade` updates an existing stanza after a PostgreSQL major version upgrade.

### Step 6: Verify WAL archiving is working

Force a WAL segment switch so there is something new to archive:

```bash
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT pg_switch_wal();"
```

Wait 5 seconds for the archiver process to pick up the new WAL segment and send it to the repo:

```bash
sleep 5
```

Check the archiver status to confirm the new segment was archived:

```bash
/usr/pgsql-16/bin/psql -p 5432 -c "
  SELECT last_archived_wal, last_archived_time, failed_count
  FROM pg_stat_archiver;
"
```

Expected: Recent archive time, failed_count stable.

### Step 7: Document the backup inventory

Verify you now have multiple backup methods working.

Check pgBackRest:

```bash
pgbackrest --stanza=main info
```

Check the emergency pg_basebackup:

```bash
ls -lh /opt/pgsql/backup/basebackup-emergency/
```

Check the logical dumps:

```bash
ls -lh /opt/pgsql/backup/dumps/
```

All three should show valid, recent backups.

Exit the postgres user:

```bash
exit
```

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
