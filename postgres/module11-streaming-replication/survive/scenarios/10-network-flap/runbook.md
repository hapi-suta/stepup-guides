# Runbook 10 - Network Flap

**Severity:** Medium - Replication interrupted, may auto-recover
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Check replication status on the primary

SSH to [NODE1] (primary) and check pg_stat_replication:

```bash
sudo -u postgres psql -c "
  SELECT client_addr, state, sent_lsn, replay_lsn,
         pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

If `state` is `streaming` and lag is small, the WAL receiver may have already reconnected automatically. If the result is empty or state is not `streaming`, proceed to diagnose.

### Step 2: Check standby logs for disconnection

SSH to [NODE2] (standby) and check the log:

```bash
sudo tail -30 /var/log/postgresql/postgresql-16-main.log
```

Look for messages like:
- "could not receive data from WAL stream"
- "connection to primary lost"
- "started streaming WAL from primary" (reconnection)

> **Concept - WAL Receiver Reconnection**: The standby's WAL receiver process automatically retries connections to the primary. The retry interval is controlled by wal_retrieve_retry_interval (default: 5 seconds). After a brief network interruption, replication should resume without manual intervention.

### Step 3: Check for dangling iptables rules

On [NODE2], verify no firewall rules are blocking PostgreSQL traffic:

```bash
sudo iptables -L -n | grep 5432
sudo iptables -L INPUT -n --line-numbers | grep 5432
sudo iptables -L OUTPUT -n --line-numbers | grep 5432
```

If any DROP rules targeting port 5432 exist, remove them:

```bash
sudo iptables -D INPUT -p tcp --sport 5432 -s [NODE1_IP] -j DROP
sudo iptables -D OUTPUT -p tcp --dport 5432 -d [NODE1_IP] -j DROP
```

Also check on the primary:

```bash
# On [NODE1]
sudo iptables -L -n | grep 5432
```

> **Concept - iptables**: iptables is the Linux kernel firewall. DROP rules silently discard packets, causing TCP connections to time out rather than receive an immediate rejection. This is why network flaps cause slow detection - the WAL receiver must wait for a TCP timeout.

### Step 4: Force WAL receiver reconnection (if needed)

If replication has not auto-recovered after the iptables rules are cleared, restart the standby:

```bash
# On [NODE2]
sudo systemctl restart postgresql
```

Or, less disruptive, kill just the WAL receiver to force a reconnect:

```bash
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE backend_type = 'walreceiver';"
```

### Step 5: Verify replication is streaming

On [NODE1]:

```bash
sudo -u postgres psql -c "
  SELECT client_addr, state,
         pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

Expected: `state` is `streaming` and `lag_bytes` is decreasing.

### Step 6: Verify standby caught up

Wait for lag to reach near-zero:

```bash
sudo -u postgres psql -c "
  SELECT pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

Expected: `lag_bytes` is under 1 MB and stable.

### Step 7: Verify data consistency

On both nodes:

```sql
SELECT count(*) FROM employees;
```

Counts should match.

### Step 8: Confirm no residual iptables rules

On both nodes:

```bash
sudo iptables -L -n | grep -c 5432
```

Expected: 0 (no rules blocking PostgreSQL traffic).

---

## Key Concepts for Revision

- **TCP keepalives** control how quickly a dead connection is detected. PostgreSQL settings: tcp_keepalives_idle, tcp_keepalives_interval, tcp_keepalives_count. Lower values detect network failures faster.
- **wal_retrieve_retry_interval** (default 5s) controls how often the standby retries connecting to the primary after a disconnection. Lowering this speeds up recovery from brief outages.
- **wal_sender_timeout** (default 60s) controls how long the primary waits for a standby to acknowledge data before disconnecting. After a network flap, the primary may drop the WAL sender connection.
- **wal_receiver_timeout** (default 60s) is the standby-side counterpart. If no data is received within this period, the WAL receiver disconnects and retries.
- **Replication slot persistence**: Even during a network outage, the replication slot on the primary continues to retain WAL. This ensures the standby can catch up when connectivity returns.
- **TCP half-open connections**: After a network disruption, TCP connections may be half-open (one side thinks it is connected, the other does not). Keepalive probes detect and clean these up.
- **iptables vs nftables**: Modern Linux distributions are migrating from iptables to nftables. The commands differ but the concepts are the same. Always verify which firewall framework is active.

---

## Interview Discussion Points

1. **Network partition handling**: How does PostgreSQL handle a network partition between primary and standby? What is the worst-case scenario for data consistency?

2. **TCP tuning for replication**: What TCP keepalive settings do you recommend for PostgreSQL replication? How do these interact with wal_sender_timeout and wal_receiver_timeout?

3. **Detection speed**: How quickly should your monitoring detect a replication disruption? What is the tradeoff between fast detection and false positives from brief network blips?

4. **Firewall management**: How do you prevent accidental firewall changes from breaking replication? Discuss change management, pre-deployment checks, and firewall rule auditing.

5. **Network flap vs network partition**: What is the difference between a brief network flap and a sustained partition? How does your response differ for each?

6. **Cloud networking**: How do cloud-provider network issues (VPC peering failures, security group changes, NIC reattachment) manifest as replication problems? What is different about diagnosing these vs on-prem network issues?

7. **Automatic failover during network issues**: Should your HA tool (Patroni) trigger a failover during a network flap? How do you prevent unnecessary failovers from transient network issues? Discuss fencing, quorum, and watchdog timers.
