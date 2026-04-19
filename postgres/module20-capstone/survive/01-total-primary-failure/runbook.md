# Runbook 01 - Total Primary Failure

**Severity:** Critical - All writes blocked, data directory corrupted
**Time to resolve:** 15-30 minutes
**Skills tested:** Failover (Module 11), base backup (Module 09), repmgr (Module 11)

---

## Fix Path

### Step 1: Confirm the primary is down

SSH to the original primary:

```bash
systemctl status postgresql-16
```

Try to start it:

```bash
systemctl start postgresql-16
```

It will fail because the data directory is corrupted. Check the log:

```bash
tail -20 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

You should see errors about pg_control or corrupted pages. The primary cannot be recovered in place.

### Step 2: Check the standby

SSH to the standby server:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

It should return `t` (still in standby mode). Check what data it has:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT email FROM app.customers WHERE email = 'pre-crash-marker@capstone.lab';"
```

The marker row should be present - synchronous replication guaranteed it was flushed to the standby before the crash.

### Step 3: Promote the standby

If repmgrd auto-promoted, skip to Step 4. Otherwise, manually promote:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby promote
```

Expected output:
```
NOTICE: promoting standby to primary
NOTICE: STANDBY PROMOTE successful
```

Verify:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f` (now a primary).

### Step 4: Verify data integrity on the new primary

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.orders;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.customers;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT email FROM app.customers WHERE email = 'pre-crash-marker@capstone.lab';"
```

Compare counts with the pre-failure values (from the state file at /tmp/stepup-capstone-01-state.env). Customers should be +1 (the marker row).

### Step 5: Test writes on the new primary

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('post-failover@capstone.lab', 'Post Failover');"
```

Should succeed without error.

```bash
exit
```

### Step 6: Rebuild the old primary as a standby

SSH to the old primary as root. The corrupted data directory must be replaced entirely.

Clean the data directory:

```bash
su - postgres
```

```bash
rm -rf /opt/pgsql/data/*
```

```bash
rm -rf /opt/pgsql/wal/*
```

Take a base backup from the new primary:

```bash
/usr/pgsql-16/bin/pg_basebackup -h [NEW_PRIMARY_IP] -U replicator -D /opt/pgsql/data --waldir=/opt/pgsql/wal -X stream -P -R -S standby_slot_1
```

```bash
exit
```

Start PostgreSQL:

```bash
systemctl start postgresql-16
```

### Step 7: Register the rebuilt node as standby

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register --force
```

The `--force` flag overwrites the old registration for this node.

### Step 8: Verify the cluster

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected: Two nodes, one primary and one standby, both running.

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t` (this node is now a standby).

```bash
exit
```

---

## Revision Concepts

**Q: Why can't we just fix the corrupted files instead of rebuilding?**
A: pg_control is the single source of truth for the cluster state (checkpoint location, timeline, system identifier). A corrupted pg_control means PostgreSQL cannot determine where recovery should start. Even if you restored pg_control, the corrupted relation files and missing WAL segments make the data directory untrustworthy. Rebuilding from a known-good source (the standby) is the only safe path.

**Q: What if we didn't have synchronous replication?**
A: With asynchronous replication, the standby might be a few transactions behind the primary at the time of the crash. Those in-flight transactions would be lost (RPO > 0). Synchronous replication guarantees that every committed transaction is on at least two nodes.

**Q: What if both nodes are corrupted?**
A: That is when your pgBackRest backups save you. You would restore from the most recent backup and replay WAL archives to the latest possible point. This is why offsite backup copies are critical.
