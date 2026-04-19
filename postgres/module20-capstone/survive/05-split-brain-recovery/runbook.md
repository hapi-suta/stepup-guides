# Runbook 05 - Split Brain Recovery

**Severity:** Critical - Two primaries accepting writes, data divergence
**Time to resolve:** 15-25 minutes
**Skills tested:** Replication (Module 11), timeline understanding (Module 09), pg_rewind (Module 11)

---

## Fix Path

### Step 1: Identify both nodes are primary

Check each node:

On **NODE1**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

```bash
exit
```

On **NODE2**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

```bash
exit
```

Both return `f`. This confirms split-brain.

### Step 2: Determine the true primary

The true primary is the node that was primary before the split. Compare timelines and LSNs.

On **each node**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT timeline_id, checkpoint_lsn FROM pg_control_checkpoint();"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_current_wal_lsn();"
```

```bash
exit
```

Decision rules:
- **Lower timeline** = the original primary (it never changed timelines)
- **Higher timeline** = the promoted standby (promotion increments the timeline)
- If timelines are the same, the node with the **more advanced LSN** has more data

In this scenario, the original primary (NODE1) has the lower timeline. The promoted standby (NODE2) has a higher timeline.

**Decision**: Choose the original primary (lower timeline) as the true primary, because it was never intentionally promoted and has the most consistent data lineage.

> **Note**: In production, the decision depends on context. If the original primary had a hardware failure and the standby was intentionally promoted, keep the promoted node as primary.

### Step 3: Stop the false primary

On the node you chose as the **false primary**:

```bash
systemctl stop postgresql-16
```

### Step 4: Rebuild the false primary as a standby

Option A - pg_rewind (faster, if WAL is available):

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/pg_rewind --target-pgdata=/opt/pgsql/data --source-server="host=[TRUE_PRIMARY_IP] port=5432 user=postgres dbname=postgres"
```

If pg_rewind succeeds, create the standby.signal file:

```bash
touch /opt/pgsql/data/standby.signal
```

Configure recovery:

```bash
vi /opt/pgsql/data/postgresql.auto.conf
```

Add or update:

```
primary_conninfo = 'host=[TRUE_PRIMARY_IP] port=5432 user=replicator password=R3pl!cat0r_2026'
primary_slot_name = 'standby_slot_1'
```

Save and exit (`:wq`).

```bash
exit
```

Option B - Full base backup (if pg_rewind fails):

```bash
su - postgres
```

```bash
rm -rf /opt/pgsql/data/*
```

```bash
rm -rf /opt/pgsql/wal/*
```

```bash
/usr/pgsql-16/bin/pg_basebackup -h [TRUE_PRIMARY_IP] -U replicator -D /opt/pgsql/data --waldir=/opt/pgsql/wal -X stream -P -R -S standby_slot_1
```

```bash
exit
```

### Step 5: Start the rebuilt standby

```bash
systemctl start postgresql-16
```

Verify:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t`

### Step 6: Verify replication

On the **true primary**:

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

Expected: One standby, state = streaming.

### Step 7: Restart repmgrd on both nodes

```bash
exit
```

On **both nodes** as root:

```bash
systemctl start repmgrd
```

On either node:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected: One primary, one standby, both running.

### Step 8: Clean up split-brain artifacts

On the true primary, remove the conflicting data:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DELETE FROM app.customers WHERE email LIKE '%@splitbrain.lab';"
```

```bash
exit
```

### Step 9: Re-register the standby if needed

If repmgr shows the old registration:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register --force
```

```bash
exit
```

---

## Revision Concepts

**Q: How does split-brain happen in production?**
A: Common causes: (1) Network partition - standby cannot reach primary but assumes it is down, (2) Fencing failure - the old primary is not shut down before promotion, (3) Manual error - someone promotes the standby without stopping the primary, (4) repmgrd misconfiguration - too aggressive failover settings.

**Q: Why does timeline matter?**
A: When a standby is promoted, it starts a new timeline (e.g., timeline 1 becomes timeline 2). This is how PostgreSQL tracks divergent history. Two nodes on different timelines have incompatible WAL - you cannot simply reconnect them.

**Q: What data is lost in split-brain recovery?**
A: The data written to the false primary after the split is lost. In this scenario, the row `standby-only@splitbrain.lab` (or `primary-only@splitbrain.lab`, depending on your choice) is lost. This is unavoidable - two divergent data paths cannot be automatically merged.

**Q: How to prevent split-brain?**
A: (1) Use fencing (STONITH) to guarantee the old primary is dead before promotion, (2) Use synchronous replication with `synchronous_standby_names`, (3) Never promote manually unless you have confirmed the primary is stopped, (4) Use a witness node in repmgr to break ties.
