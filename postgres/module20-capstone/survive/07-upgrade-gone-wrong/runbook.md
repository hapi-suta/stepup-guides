# Runbook 07 - Upgrade Gone Wrong

**Severity:** Critical - Database down, old cluster damaged, new cluster incomplete
**Time to resolve:** 20-30 minutes
**Skills tested:** Backup/restore (Module 09), upgrade process (Module 13), pg_controldata, PITR

---

## Fix Path

### Step 1: Assess the damage

Try to start PostgreSQL with the existing data directory:

```bash
systemctl start postgresql-16
```

Check the status:

```bash
systemctl status postgresql-16
```

It will likely fail. Check the log:

```bash
tail -30 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Check if the pg_wal symlink is intact:

```bash
ls -la /opt/pgsql/data/pg_wal
```

If you see `pg_wal.broken` instead of `pg_wal`, the WAL path is broken.

Check pg_controldata:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data
```

If this shows errors or garbage data, the control file is damaged.

```bash
exit
```

### Step 2: Fix the pg_wal symlink (if broken)

```bash
su - postgres
```

```bash
ls -la /opt/pgsql/data/pg_wal.broken
```

If it exists, restore it:

```bash
mv /opt/pgsql/data/pg_wal.broken /opt/pgsql/data/pg_wal
```

```bash
exit
```

Try starting again:

```bash
systemctl start postgresql-16
```

If it still fails due to corrupted pg_internal.init, proceed to backup restore.

### Step 3: Restore from the pre-upgrade backup

The injection script took a backup before the simulated upgrade. Use it.

```bash
su - postgres
```

Check available backups:

```bash
pgbackrest --stanza=prod info
```

The most recent backup should be from just before the upgrade attempt.

```bash
exit
```

Stop any PostgreSQL processes:

```bash
systemctl stop postgresql-16
```

Restore:

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod --delta --type=immediate --target-action=promote restore
```

- `--delta` - Only restores files that differ. Faster than a full restore.
- `--type=immediate` - Recover to the end of the backup (consistent point).
- `--target-action=promote` - Promote to primary after recovery.

If the WAL symlink issue persists after restore, verify:

```bash
ls -la /opt/pgsql/data/pg_wal
```

It should be a symlink to `/opt/pgsql/wal` or the WAL files should be present.

```bash
exit
```

### Step 4: Start PostgreSQL

```bash
systemctl start postgresql-16
```

```bash
systemctl status postgresql-16
```

Should show `active (running)`.

### Step 5: Verify data integrity

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.orders;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.customers;"
```

Compare with the values in the state file (`/tmp/stepup-capstone-07-state.env`).

```bash
/usr/pgsql-16/bin/psql -c "SELECT version();"
```

Should show PostgreSQL 16 (the original version, since the upgrade failed).

### Step 6: Clean up failed upgrade artifacts

```bash
rm -rf /opt/pgsql/data_new
```

This removes the incomplete new cluster directory.

```bash
exit
```

### Step 7: Verify replication (if applicable)

If the standby was also affected, you may need to rebuild it:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state FROM pg_stat_replication;"
```

If replication is broken, rebuild the standby from the restored primary (see Runbook 01, Step 6).

### Step 8: Take a fresh backup

```bash
pgbackrest --stanza=prod --type=full backup
```

```bash
pgbackrest --stanza=prod info
```

```bash
exit
```

---

## Revision Concepts

**Q: Why did the upgrade fail?**
A: pg_upgrade with `--link` modifies the old cluster in place (hard links). If the process crashes midway, both the old and new clusters can be in an inconsistent state. This is why you ALWAYS take a backup before running pg_upgrade.

**Q: What is the difference between --link and --copy in pg_upgrade?**
A: `--link` uses hard links (fast, but old cluster is unusable after). `--copy` copies files (slower, but old cluster remains intact as a rollback). For critical databases, `--copy` is safer even though it is slower and uses more disk space.

**Q: How to prevent this in production?**
A: (1) Always take a full backup before pg_upgrade, (2) Run `pg_upgrade --check` first to catch issues before modifying anything, (3) Use `--copy` instead of `--link` for safety, (4) Test the upgrade on a replica first, (5) Have a documented rollback plan before starting.

**Q: Can pg_rewind fix a partially upgraded cluster?**
A: No. pg_rewind works for diverged timelines (failover scenarios), not for catalog-level corruption from a failed upgrade. The only safe recovery is restoring from backup.
