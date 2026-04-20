# Runbook 05 - repmgrd Stuck (No Auto-Failover)

**Severity:** Critical - Primary down, no automatic failover, manual intervention required
**Time to resolve:** 10-20 minutes

---

## Fix Path

### Step 1: Diagnose the situation

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

Check if PostgreSQL is running on each node, one at a time:

```bash
pg_isready -h pg-repmgr-1 -p 5432
```

```bash
pg_isready -h pg-repmgr-2 -p 5432
```

```bash
pg_isready -h pg-repmgr-3 -p 5432
```

```bash
pg_isready -h pg-repmgr-w -p 5432
```

Check repmgrd status on each node:

```bash
ssh root@pg-repmgr-1 "systemctl is-active repmgrd"
```

```bash
ssh root@pg-repmgr-2 "systemctl is-active repmgrd"
```

```bash
ssh root@pg-repmgr-3 "systemctl is-active repmgrd"
```

```bash
ssh root@pg-repmgr-w "systemctl is-active repmgrd"
```

### Step 2: Try to start repmgrd and diagnose why it fails

On any standby:

```bash
sudo systemctl start repmgrd
```

```bash
sudo systemctl status repmgrd
```

If repmgrd fails to start, check the config:

```bash
cat /etc/repmgr.conf
```

If the config is corrupt or empty, you will see the problem immediately.

### Step 3: Restore repmgr.conf from backup

The original config was backed up:

```bash
ls -la /etc/repmgr.conf.backup
```

Restore it:

```bash
cp /etc/repmgr.conf.backup /etc/repmgr.conf
```

Verify:

```bash
cat /etc/repmgr.conf | head -5
```

Should show valid repmgr configuration (node_id, conninfo, etc.).

Do this on ALL standbys where repmgr.conf was corrupted.

### Step 4: Manually promote a standby

With repmgr.conf restored, promote the best standby. First, check WAL positions:

On each standby:

```bash
psql -c "
SELECT pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn();"
```

Promote the standby with the highest LSN:

```bash
repmgr -f /etc/repmgr.conf standby promote
```

Verify:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f`.

### Step 5: Redirect the other standby

On the standby that was NOT promoted:

```bash
repmgr -f /etc/repmgr.conf standby follow \
  --upstream-node-id=<NEW_PRIMARY_NODE_ID>
```

### Step 6: Verify writes

On the new primary:

```sql
INSERT INTO employees(name, department) VALUES ('repmgrd_stuck_test', 'engineering');
SELECT count(*) FROM employees;
```

### Step 7: Rejoin the old primary

On the old primary, restore repmgr.conf if needed:

Restore the config if it was corrupted:

```bash
cp /etc/repmgr.conf.backup /etc/repmgr.conf
```

Rejoin:

```bash
repmgr -f /etc/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

If rejoin fails, do a full reclone:

```bash
sudo systemctl stop postgresql
```

```bash
repmgr -f /etc/repmgr.conf \
  -h <NEW_PRIMARY_HOSTNAME> -U repmgr -d repmgr \
  standby clone --force
```

```bash
sudo systemctl start postgresql
```

```bash
repmgr -f /etc/repmgr.conf standby register --force
```

### Step 8: Re-register the witness

On NODE4:

Restore config if needed:

```bash
cp /etc/repmgr.conf.backup /etc/repmgr.conf
```

```bash
sudo systemctl start postgresql
```

```bash
repmgr -f /etc/repmgr.conf witness register --force \
  -h <NEW_PRIMARY_HOSTNAME> -U repmgr -d repmgr
```

### Step 9: Restart repmgrd on ALL nodes

Run this on each node one at a time:

```bash
ssh root@pg-repmgr-1 "systemctl start repmgrd"
```

```bash
ssh root@pg-repmgr-2 "systemctl start repmgrd"
```

```bash
ssh root@pg-repmgr-3 "systemctl start repmgrd"
```

```bash
ssh root@pg-repmgr-w "systemctl start repmgrd"
```

### Step 10: Verify full cluster health

```bash
repmgr -f /etc/repmgr.conf cluster show
```

Expected output (yours will differ):
```
 ID | Name         | Role    | Status    | Upstream    | ...
----+--------------+---------+-----------+-------------+----
 1  | pg-repmgr-1  | standby |   running | pg-repmgr-2 | ...
 2  | pg-repmgr-2  | primary | * running |             | ...
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-2 | ...
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-2 | ...
```

```bash
repmgr -f /etc/repmgr.conf cluster crosscheck
```

All 4 nodes running, repmgrd active on all nodes.

---

## Key Concepts for Revision

- **repmgrd is not PostgreSQL**: PostgreSQL and repmgrd are separate processes.
  If repmgrd crashes or stops, PostgreSQL continues running normally. Replication
  continues streaming. The only thing lost is automatic failover detection. This
  is why you can recover manually - the data plane is intact.

- **Configuration file integrity**: repmgr.conf is a critical configuration file.
  If it is corrupted, missing, or has incorrect node_id/conninfo values, repmgrd
  will not start and repmgr commands will fail. Always keep backups of this file,
  and consider configuration management (Ansible, Puppet) to prevent drift.

- **Manual failover workflow**: Without repmgrd, the failover sequence is:
  1. Identify the best standby (highest LSN)
  2. Promote it with `repmgr standby promote`
  3. Redirect other standbys with `repmgr standby follow`
  4. Rejoin the old primary with `repmgr node rejoin`
  This is the same workflow repmgrd automates via promote_command and follow_command.

- **repmgr vs pg_ctl promote**: `repmgr standby promote` wraps `pg_promote()` with
  metadata updates. It records the promotion in `repmgr.events` and updates
  `repmgr.nodes`. If repmgr.conf is broken, you can still promote with
  `pg_ctl promote` or `SELECT pg_promote()`, but the repmgr metadata will be
  inconsistent until you fix it.

- **Defense in depth**: repmgrd should be monitored. If repmgrd stops, an alert
  should fire immediately - even though nothing breaks right away. The risk
  is that the NEXT failure (primary crash) will not be handled automatically.

---

## Interview Discussion Points

1. **Monitoring the monitor**: How do you monitor repmgrd itself? Discuss
   systemd watchdog, process monitoring (monit, supervisor), and health check
   endpoints. What is the alert priority for "repmgrd is down"?

2. **Configuration management**: How do you prevent repmgr.conf from being
   corrupted or drifting between nodes? Discuss Ansible templates, etcd-backed
   configuration, and configuration checksums.

3. **Graceful degradation**: The cluster continued functioning (reads on standbys,
   replication streaming) even with repmgrd down. What other components have this
   "graceful degradation" property? What components do NOT (single points of
   failure)?

4. **Recovery without tools**: If both repmgr.conf AND repmgr.conf.backup were
   destroyed, how would you recover? Can you promote using native PostgreSQL
   tools (pg_ctl promote) and rebuild repmgr from scratch?

5. **Daemon restart strategies**: When repmgrd crashes, should systemd auto-restart
   it? What are the risks of aggressive restart policies (rapid restart loops,
   stale state causing double promotion)?

6. **Operational procedures**: This scenario required restoring config files,
   manual promotion, and multiple node reconfigurations. How do you ensure your
   team can execute this under pressure at 3 AM? Discuss runbooks, drills, and
   pair on-call.

7. **repmgr vs Patroni resilience**: Compare how repmgr handles daemon failure
   vs how Patroni handles a DCS outage. Which approach provides more safety
   guarantees? Which is simpler to operate?
