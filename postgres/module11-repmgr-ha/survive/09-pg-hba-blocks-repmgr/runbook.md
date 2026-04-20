# Runbook 09 - pg_hba Blocks repmgr

**Severity:** Critical - Primary down, new primary cannot accept replication connections
**Time to resolve:** 10-20 minutes

---

## Fix Path

### Step 1: Wait for repmgrd auto-failover

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

Monitor the repmgr log on the standbys:

```bash
tail -f /var/log/postgresql/repmgr.log
```

A standby should be promoted within 60-90 seconds. If repmgrd is not running
or auto-failover does not trigger, promote manually:

```bash
repmgr -f /etc/repmgr.conf standby promote
```

### Step 2: Verify the new primary is accepting writes

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f`.

```sql
INSERT INTO employees(name, department) VALUES ('hba_test', 'SRE');
```

Writes should succeed locally on the new primary.

### Step 3: Diagnose replication failure

Check if standbys are streaming:

```bash
psql -c "
SELECT client_addr, state FROM pg_stat_replication;"
```

Expected: EMPTY or no streaming entries. Standbys cannot connect.

Check the PostgreSQL log on a standby for connection errors:

```bash
tail -20 /var/log/postgresql/postgresql-16-main.log
```

Look for messages like:
```
FATAL: no pg_hba.conf entry for replication connection from host "..."
```

> **Concept - pg_hba.conf and replication**: PostgreSQL requires explicit
> pg_hba.conf entries for replication connections. Without a line like
> `host replication repmgr 10.0.0.0/8 md5`, standbys cannot establish
> WAL streaming connections even if the repmgr database user exists.

### Step 4: Examine the broken pg_hba.conf

On the new primary:

```bash
cat /etc/postgresql/16/main/pg_hba.conf
```

Notice the missing entries for `repmgr` user and `replication` database.

### Step 5: Restore pg_hba.conf from backup

On the new primary:

```bash
cp /etc/postgresql/16/main/pg_hba.conf.backup /etc/postgresql/16/main/pg_hba.conf
```

If no backup exists, add the required entries manually:

```bash
cat >> /etc/postgresql/16/main/pg_hba.conf <<'HBAEOF'
# repmgr connections
host    repmgr       repmgr    0.0.0.0/0    md5
host    replication   repmgr    0.0.0.0/0    md5
HBAEOF
```

### Step 6: Fix pg_hba.conf on ALL other data nodes

The broken config was replicated to all nodes. Fix each one:

Run this on each data node one at a time:

```bash
ssh root@pg-repmgr-1 "cp /etc/postgresql/16/main/pg_hba.conf.backup /etc/postgresql/16/main/pg_hba.conf"
```

```bash
ssh root@pg-repmgr-2 "cp /etc/postgresql/16/main/pg_hba.conf.backup /etc/postgresql/16/main/pg_hba.conf"
```

```bash
ssh root@pg-repmgr-3 "cp /etc/postgresql/16/main/pg_hba.conf.backup /etc/postgresql/16/main/pg_hba.conf"
```

### Step 7: Reload PostgreSQL on the new primary and standbys

```bash
psql -c "SELECT pg_reload_conf();"
```

Do this on EVERY data node where pg_hba.conf was changed. No restart needed -
pg_hba.conf changes take effect on reload.

> **Concept - pg_reload_conf vs restart**: pg_hba.conf changes only need a
> reload (SIGHUP), not a full restart. This means you can fix authentication
> issues without disrupting existing connections or causing downtime.

### Step 8: Verify standbys reconnect

Wait 10-20 seconds, then check replication on the new primary:

```bash
psql -c "
SELECT client_addr, state, sent_lsn, replay_lsn
FROM pg_stat_replication;"
```

Standbys should transition from disconnected to streaming. If they do not
reconnect automatically, restart PostgreSQL on each standby:

```bash
sudo systemctl restart postgresql
```

### Step 9: Rejoin the old primary as a standby

On the old primary, restore pg_hba.conf first:

```bash
cp /etc/postgresql/16/main/pg_hba.conf.backup /etc/postgresql/16/main/pg_hba.conf
```

Then rejoin:

```bash
repmgr -f /etc/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

If rejoin fails:

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

### Step 10: Restart repmgrd and verify

Restart repmgrd on each node one at a time:

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

Verify:

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

All 4 nodes running, replication streaming, pg_hba.conf correct on all nodes.

---

## Key Concepts for Revision

- **pg_hba.conf is the firewall for PostgreSQL connections**: Every client
  connection (including replication) is checked against pg_hba.conf rules in
  order. If no rule matches, the connection is rejected. A missing replication
  entry blocks all WAL streaming without affecting local queries.

- **Replication requires its own HBA entry**: The `replication` pseudo-database
  in pg_hba.conf is special. It does not match normal database connections.
  You need both a `repmgr` database entry (for repmgr metadata queries) and a
  `replication` entry (for WAL streaming).

- **Config inheritance during failover**: When a standby is promoted, it keeps
  its existing configuration files - including pg_hba.conf. If the standby had
  a broken pg_hba.conf, the new primary inherits that broken config. This is
  why configuration must be consistent across all nodes.

- **Reload vs restart for HBA changes**: pg_hba.conf is re-read on SIGHUP
  (pg_reload_conf()). Existing connections are NOT affected - only new
  connections are checked against the updated rules. This means a broken
  pg_hba.conf does not kill existing replication, only prevents new connections.

- **Configuration management prevents this class of failure**: Tools like
  Ansible ensure pg_hba.conf is identical across all nodes. Manual edits to
  pg_hba.conf should be avoided in production - all changes should go through
  configuration management and be applied to all nodes simultaneously.

- **pg_hba.conf order matters**: Rules are evaluated top to bottom. The first
  matching rule wins. A broad REJECT rule placed before a replication ALLOW
  rule would block replication even though the ALLOW exists.

---

## Interview Discussion Points

1. **Debugging authentication failures**: Walk through how you diagnose a
   replication connection failure. What logs do you check? What is the
   difference between "no pg_hba.conf entry" and "password authentication
   failed"?

2. **pg_hba.conf best practices**: How do you structure pg_hba.conf for a
   repmgr cluster? Discuss least-privilege access, network CIDR restrictions,
   separate entries for replication vs database connections, and the use of
   scram-sha-256 vs md5.

3. **Configuration consistency**: How do you ensure pg_hba.conf is identical
   across all nodes? Discuss configuration management tools, gitops for PG
   config, and automated drift detection.

4. **Failover config inheritance**: What other configuration files might cause
   problems when a standby is promoted? Discuss postgresql.conf differences
   (hot_standby settings), recovery.conf / standby.signal, and SSL certificate
   paths.

5. **Security vs availability tradeoff**: Tight pg_hba.conf rules improve
   security but increase the risk of self-inflicted outages. How do you
   balance this? Discuss the principle of least privilege applied to database
   authentication.

6. **Testing HBA changes safely**: How do you test pg_hba.conf changes before
   applying them in production? Discuss pg_hba_file_rules view (PG 15+),
   dry-run tools, and staging environment validation.

7. **Incident response for auth failures**: If replication breaks due to a
   pg_hba.conf change during a maintenance window, what is your escalation
   path? How quickly can you roll back? Should pg_hba.conf changes go through
   change management?
