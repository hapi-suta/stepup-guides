# Runbook 01 - Accidental Table Drop

**Severity:** Critical - Data loss, application errors on every query hitting employees
**Time to resolve:** 10-20 minutes

---

## Fix Path

### Step 1: Confirm the table is gone

SSH to [NODE1] and verify the table no longer exists:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "\dt employees"
```

Expected: "Did not find any relation named employees."

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: ERROR - relation "employees" does not exist.

### Step 2: Check what backups are available

List pgBackRest backups:

```bash
sudo -u postgres pgbackrest --stanza=main info
```

Look for the most recent full or incremental backup taken BEFORE the drop. Note the backup timestamp.

> **Concept - Backup Types**: pgBackRest supports full, differential, and incremental backups. For a single-table restore, any backup type works as long as it contains the table data. The key is that the backup was taken BEFORE the DROP happened.

Also check if a logical dump exists on [NODE2]:

```bash
ssh [NODE2] "ls -lh /opt/pgsql/backup/dumps/labdb*"
```

### Step 3: Choose your recovery strategy

You have two options:

**Option A - Selective pg_restore from logical dump (preferred for single table)**

If a custom-format dump exists on [NODE2]:

```bash
# On NODE2, extract just the employees table
/usr/pgsql-16/bin/pg_restore --list /opt/pgsql/backup/dumps/labdb.custom | grep employees > /tmp/employees-toc.txt

# Review what will be restored
cat /tmp/employees-toc.txt

# Restore just the employees table to the primary
/usr/pgsql-16/bin/pg_restore -h [NODE1] -p 5432 -U postgres -d labdb \
  --use-list=/tmp/employees-toc.txt \
  /opt/pgsql/backup/dumps/labdb.custom
```

**Option B - PITR side-restore (when no logical dump is available)**

Restore the entire cluster to a scratch location, extract the table, copy it back:

```bash
# On NODE2 or a scratch server, restore to a temporary directory
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/tmp/pg-scratch \
  --type=time \
  --target="[TIMESTAMP_BEFORE_DROP]" \
  --target-action=promote \
  restore

# Start a temporary PG instance on a different port
sudo -u postgres /usr/pgsql-16/bin/pg_ctl \
  -D /tmp/pg-scratch -o "-p 5433" start

# Wait for recovery to complete
sudo -u postgres /usr/pgsql-16/bin/psql -p 5433 -d labdb -c "SELECT count(*) FROM employees;"

# Dump just the employees table from the scratch instance
sudo -u postgres /usr/pgsql-16/bin/pg_dump -p 5433 -d labdb -t employees -Fc -f /tmp/employees-only.dump

# Restore to the real primary
/usr/pgsql-16/bin/pg_restore -h [NODE1] -p 5432 -U postgres -d labdb /tmp/employees-only.dump

# Clean up scratch instance
sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /tmp/pg-scratch stop
rm -rf /tmp/pg-scratch
```

> **Concept - PITR Side-Restore**: A side-restore creates a temporary PG instance from backup at a specific point in time. You extract what you need, copy it to production, and discard the scratch instance. This avoids restoring the entire production cluster just for one table.

### Step 4: Verify the table is restored

On [NODE1]:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: >= 10000 rows (matching the pre-drop count from the state file).

### Step 5: Verify other tables are unaffected

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "\dt"
```

Confirm all other tables still exist and have their data intact.

### Step 6: Take a fresh backup

After confirming the restore is clean, take a new backup so this recovered state is protected:

```bash
sudo -u postgres pgbackrest --stanza=main --type=diff backup
```

---

## Key Concepts for Revision

- **DROP TABLE is not in WAL replay** in the sense that you can undo it - once dropped and WAL advances, the table is gone. Recovery requires restoring from backup to a point before the drop.
- **Selective restore** with pg_restore --use-list lets you extract individual tables from a custom-format dump without restoring the entire database. This is the fastest recovery for single-object loss.
- **PITR side-restore** is a pattern where you restore to a scratch location at a specific timestamp, extract what you need, and copy it back. It avoids disrupting the running production cluster.
- **recovery_target_time** must be set to a time BEFORE the destructive operation. Use the injection timestamp from monitoring or logs to find the correct target.
- **pg_dump custom format (-Fc)** stores the dump in a table-of-contents format that supports selective restore. Always prefer this over plain SQL dumps for production backups.
- **Backup verification** should be done immediately after restore - check row counts, run sample queries, and compare against known baselines.
- **Post-recovery backup** is essential - take a fresh backup immediately after restoring data so you do not have a gap in your backup chain.

---

## Interview Discussion Points

1. **Recovery strategy selection**: When would you choose a selective pg_restore over a full PITR? What factors influence this decision (table count, data volume, acceptable downtime, whether you have logical dumps)?

2. **DROP vs TRUNCATE recovery**: How does recovering from DROP TABLE differ from recovering from TRUNCATE? (Hint: TRUNCATE is WAL-logged and can be undone with PITR, but DROP removes the relfilenode entirely.)

3. **Recovery time estimation**: A customer dropped a critical table at 3:00 AM. Your most recent backup is from midnight. How do you estimate how long the recovery will take? What variables affect this?

4. **Prevention strategies**: What mechanisms can prevent accidental DROP TABLE in production? Discuss: revoke DDL privileges, event triggers that block DROP, pg_stat_user_tables monitoring, and mandatory change-management processes.

5. **Logical vs physical backup tradeoffs**: Why should you maintain both logical (pg_dump) and physical (pgBackRest) backups? When does each shine? What are the failure modes unique to each?

6. **Side-restore resource planning**: A PITR side-restore needs disk space, a free port, and CPU/memory. How do you plan for this in your infrastructure? Do you keep a dedicated recovery server?

7. **Multi-tenant impact**: If labdb, appdb, and blobdb share the same cluster, how does a full PITR affect the other databases? Why is selective restore preferred when only one object is affected?
