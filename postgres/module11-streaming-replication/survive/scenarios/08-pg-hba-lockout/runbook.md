# Runbook 08 - pg_hba Lockout

**Severity:** High - Standby cannot replicate, increasing data loss risk
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Confirm replication is down

SSH to [NODE1] (primary) and check for active replication:

```bash
sudo -u postgres psql -c "SELECT client_addr, state FROM pg_stat_replication;"
```

Expected: Empty result set (no connected standbys).

### Step 2: Check the standby log for connection errors

SSH to [NODE2] (standby) and check the log:

```bash
sudo tail -30 /var/log/postgresql/postgresql-16-main.log
```

Look for:

```
FATAL: no pg_hba.conf entry for replication connection from host "X.X.X.X"
```

This tells you the primary is rejecting the standby's replication connection due to a missing pg_hba.conf entry.

> **Concept - pg_hba.conf and replication**: Replication connections require a specific entry in pg_hba.conf with the database field set to `replication`. Without this entry, the primary rejects all WAL streaming connections, even if the standby has valid credentials.

### Step 3: Inspect pg_hba.conf on the primary

SSH to [NODE1] and check the file:

```bash
sudo -u postgres psql -c "SHOW hba_file;"
sudo cat /etc/postgresql/16/main/pg_hba.conf | grep -i replication
```

Expected: No lines with `replication` in the database column.

### Step 4: Add the replication entry back

On [NODE1], add the replication line. Use the standby's IP or a CIDR range:

```bash
echo "host    replication     replicator      0.0.0.0/0               md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
```

Or for more restrictive access (preferred in production):

```bash
echo "host    replication     replicator      [NODE2_IP]/32            md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
```

Verify the line was added:

```bash
sudo cat /etc/postgresql/16/main/pg_hba.conf | grep replication
```

> **Concept - pg_hba.conf reload**: Changes to pg_hba.conf take effect after a reload (SIGHUP), not a restart. The file is processed top-to-bottom and the first matching rule wins. Order matters - a reject rule above a replication allow rule will block connections.

### Step 5: Reload PostgreSQL configuration

On [NODE1]:

```bash
sudo -u postgres psql -c "SELECT pg_reload_conf();"
```

Or:

```bash
sudo systemctl reload postgresql
```

### Step 6: Wait for standby to reconnect

The standby's WAL receiver will automatically retry the connection. Wait 10-15 seconds, then verify on [NODE1]:

```bash
sudo -u postgres psql -c "
  SELECT client_addr, state,
         pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

Expected: `state` is `streaming`.

If the standby does not reconnect within 30 seconds, restart it:

```bash
# On [NODE2]
sudo systemctl restart postgresql
```

### Step 7: Verify data consistency

On both nodes:

```sql
SELECT count(*) FROM employees;
```

Counts should match.

### Step 8: Clean up backup file

On [NODE1]:

```bash
sudo rm -f /etc/postgresql/16/main/pg_hba.conf.bak
```

---

## Key Concepts for Revision

- **pg_hba.conf** controls client authentication. The `replication` keyword in the database column is special - it matches physical and logical replication connections, not regular database connections.
- **Connection type fields**: `local` (Unix socket), `host` (TCP with or without SSL), `hostssl` (SSL only), `hostnossl` (plaintext only). Replication connections over the network must use `host`, `hostssl`, or `hostnossl`.
- **Authentication methods**: `md5`, `scram-sha-256`, `cert`, `trust`, `reject`. Production replication should use `scram-sha-256` or `cert`. Never use `trust` for replication in production.
- **First-match wins**: pg_hba.conf is processed top to bottom. The first line that matches the connection type, database, user, and address is used. A `reject` line for all connections placed before a replication allow line will block replication.
- **WAL receiver retry**: When the standby loses connection, the WAL receiver process exits and the startup process periodically retries (controlled by `wal_retrieve_retry_interval`, default 5s). No manual restart is usually needed once the cause is fixed.
- **pg_hba_file_rules view** (PG 15+): Shows the parsed contents of pg_hba.conf with line numbers and any errors, making it easier to debug authentication issues without reading the raw file.
- **Monitoring**: Alert on `pg_stat_replication` showing zero connected standbys when you expect one. Also monitor the standby side via `pg_stat_wal_receiver` for connection status.

---

## Interview Discussion Points

1. **Diagnosing auth failures**: A standby stops replicating and the log shows "no pg_hba.conf entry." Walk through your diagnostic steps. How do you confirm it is a pg_hba issue and not a network or password issue?

2. **Least-privilege pg_hba**: How do you write pg_hba.conf entries that allow replication from specific hosts only? Discuss CIDR notation, separate replication users, and SSL requirements.

3. **pg_hba.conf management**: How do you manage pg_hba.conf across multiple PostgreSQL instances? Discuss configuration management (Ansible), templating, and version control for pg_hba.conf.

4. **Reload vs restart**: Which PostgreSQL configuration changes require a reload vs a full restart? Where does pg_hba.conf fall? What about postgresql.conf parameters like shared_buffers vs work_mem?

5. **scram-sha-256 vs md5**: Explain the differences between these authentication methods. Why is scram-sha-256 preferred? What migration challenges exist when upgrading from md5?

6. **Certificate authentication for replication**: How do you set up mutual TLS for replication connections? What are the operational benefits and challenges compared to password-based authentication?

7. **Split-brain from auth misconfiguration**: If pg_hba.conf changes lock out the replication user AND the superuser, how do you recover access? Discuss local socket access, pg_hba.conf `local` lines, and emergency recovery.
