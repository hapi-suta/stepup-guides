# Build 07: Enable Automatic Failover

Configure and start the repmgrd daemon on all four nodes to enable automatic
failover detection and promotion.

Run each step on the specified node.

---

## 1. Understand the repmgrd daemon

> **Concept - What repmgrd does**: The repmgrd daemon runs as a background
> process on every node. On standbys, it periodically checks whether the
> primary is reachable (using the `monitor_interval_secs` setting). If the
> primary becomes unreachable, repmgrd waits for `reconnect_attempts *
> reconnect_interval` seconds before declaring the primary dead. It then
> runs an election among the standbys, and the winner executes
> `promote_command`. All losers execute `follow_command` to attach to the
> new primary.

> **Concept - Election mechanism**: repmgr uses a voting algorithm where
> each standby and the witness participate. The standby with the lowest
> replication lag and highest priority wins. The witness provides quorum -
> it does not compete for promotion but helps determine whether the primary
> is truly down or if the standby has a network issue.

## 2. Create the repmgrd systemd service on ALL FOUR nodes

On ALL FOUR servers:

```bash
cat > /etc/systemd/system/repmgrd.service <<'EOF'
[Unit]
Description=repmgr daemon
After=postgresql.service
Requires=postgresql.service

[Service]
Type=forking
User=postgres
Group=postgres
PIDFile=/run/repmgrd.pid
ExecStart=/usr/bin/repmgrd -f /etc/repmgr.conf -p /run/repmgrd.pid -d
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
```

Reload systemd and enable the service:

```bash
systemctl daemon-reload
```

This tells systemd to re-read its service files so it finds the new `repmgrd.service`.

```bash
systemctl enable repmgrd
```

This configures repmgrd to start automatically on boot.

> **Concept - repmgrd as a systemd service**: Running repmgrd under systemd
> ensures it starts on boot and restarts on crash. The `After=postgresql.service`
> directive guarantees PostgreSQL is running before repmgrd starts. Without
> this dependency, repmgrd would fail to connect and exit.

## 3. Start repmgrd on ALL FOUR nodes

On ALL FOUR servers:

```bash
systemctl start repmgrd
```

```bash
systemctl status repmgrd
```

Expected: `active (running)`.

## 4. Verify repmgrd is monitoring

Wait 10-15 seconds for the first monitoring cycle, then check the log:

```bash
tail -20 /var/log/postgresql/repmgr.log
```

On standbys (NODE2, NODE3), you should see:
```
[INFO] monitoring primary node "pg-repmgr-1" (ID: 1) in normal state
```

On the primary (NODE1):
```
[INFO] monitoring cluster primary "pg-repmgr-1" (ID: 1)
```

On the witness (NODE4):
```
[INFO] monitoring primary node "pg-repmgr-1" (ID: 1) in normal state
```

## 5. Check cluster events

From any node:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
repmgr -f /etc/repmgr.conf cluster event --limit 10
```

```bash
exit
```

**You are now back to root.**

Expected: events showing `repmgrd_start` for all nodes.

## 6. Verify monitoring history is being recorded

Wait 30 seconds, then on NODE1:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -d repmgr -c "
SELECT node_id, last_monitor_time, replication_lag
FROM repmgr.monitoring_history
ORDER BY last_monitor_time DESC
LIMIT 5;"
```

```bash
exit
```

**You are now back to root.**

Expected: rows for node_id 2 and 3 with recent timestamps and low lag values.

> **Concept - monitoring_history**: When `monitoring_history=yes` is set in
> repmgr.conf, repmgrd writes replication lag measurements to this table on
> every monitoring cycle. This provides historical lag data for trending and
> alerting. In production, you would query this table from your monitoring
> system.

## 7. Test automatic failover detection (optional - read-only)

Do NOT actually stop the primary yet. Instead, understand what would happen:

1. repmgrd on NODE2 and NODE3 detects the primary is unreachable
2. Each standby tries to reconnect `reconnect_attempts` times (6 times, every
   10 seconds = 60 seconds)
3. After exhausting retries, the standbys initiate an election
4. The witness votes but does not compete
5. The standby with the lowest lag and highest priority wins
6. The winner executes `promote_command` (becomes the new primary)
7. The loser executes `follow_command` (starts streaming from the new primary)

You will test this in Phase 3 (SURVIVE).

## 8. Run repmgr cluster crosscheck

This tests connectivity between all node pairs:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
repmgr -f /etc/repmgr.conf cluster crosscheck
```

```bash
exit
```

**You are now back to root.**

Expected:
```
 Name         | ID | 1 | 2 | 3 | 4
--------------+----+---+---+---+---
 pg-repmgr-1  |  1 | * | * | * | *
 pg-repmgr-2  |  2 | * | * | * | *
 pg-repmgr-3  |  3 | * | * | * | *
 pg-repmgr-w  |  4 | * | * | * | *
```

Each `*` means that node can connect to the column node. Any `x` indicates
a connectivity problem.

> **Concept - cluster crosscheck**: This command has each node try to connect
> to every other node. It catches one-directional connectivity issues (where
> A can reach B but B cannot reach A). This is critical because repmgr
> operations like switchover require bidirectional SSH and PostgreSQL
> connectivity.

---

## What You Built

```
  NODE1 (primary)        NODE2 (standby 1)      NODE3 (standby 2)      NODE4 (witness)
 ┌───────────────┐      ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
 │ PostgreSQL 16 │      │ PostgreSQL 16 │      │ PostgreSQL 16 │      │ PostgreSQL 16 │
 │ repmgr 5.4    │      │ repmgr 5.4    │      │ repmgr 5.4    │      │ repmgr 5.4    │
 │ repmgrd       │      │ repmgrd       │      │ repmgrd       │      │ repmgrd       │
 │ id=1, primary │      │ id=2, standby │      │ id=3, standby │      │ id=4, witness │
 └──────┬────────┘      └───────────────┘      └───────────────┘      └───────────────┘
        │                      ^                      ^
        ├─────streaming WAL────┘                      │
        └─────streaming WAL───────────────────────────┘

 repmgrd on each node monitors the primary. If the primary fails:
 - Standbys hold an election (witness votes but does not compete)
 - Winner promotes itself, losers follow the new primary
 - Target failover time: ~60 seconds (configurable)
```

You now understand:
- How repmgr registers and tracks nodes
- What repmgr.conf settings control failover behavior
- How the repmgrd daemon monitors and automates failover
- The witness role in preventing split-brain decisions
- How `cluster crosscheck` validates bidirectional connectivity

Proceed to `use/01-check-cluster-status.md` for Phase 2.

---

## Checkpoint

All four nodes have:
- [x] repmgrd systemd service created and enabled
- [x] repmgrd running and monitoring
- [x] Monitoring history being recorded
- [x] `repmgr cluster crosscheck` shows full connectivity

Run `build/verify.sh` to confirm everything before proceeding.
