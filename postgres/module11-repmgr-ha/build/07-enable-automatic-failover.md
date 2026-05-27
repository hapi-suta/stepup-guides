# Build 07: Enable Automatic Failover (CentOS Stream 9)

Configure and start the repmgrd daemon on all four nodes to enable automatic
failover detection and promotion.

Run each step on the specified node as **root**. If your prompt does not show `root@`, run `sudo su -` first.

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

## 2. Configure the repmgrd systemd service on ALL FOUR nodes

On CentOS with the `repmgr_16` package, a systemd service file for repmgrd
is included at `/usr/lib/systemd/system/repmgr-16.service`. However, we need
to verify it points to the correct config file.

Check if the service file exists:

```bash
systemctl cat repmgr-16
```

If the service exists, check that `ExecStart` references `/etc/repmgr/16/repmgr.conf`.

If the service file does NOT exist, or if you need to customize it, create one:

```bash
sudo vi /etc/systemd/system/repmgr-16.service
```

Enter the following content:

```
[Unit]
Description=repmgr 16 daemon
After=postgresql-16.service
Requires=postgresql-16.service

[Service]
Type=forking
User=postgres
Group=postgres
PIDFile=/run/repmgr/repmgrd-16.pid
ExecStart=/usr/pgsql-16/bin/repmgrd -f /etc/repmgr/16/repmgr.conf -p /run/repmgr/repmgrd-16.pid -d
ExecReload=/bin/kill -HUP $MAINPID
RuntimeDirectory=repmgr

[Install]
WantedBy=multi-user.target
```

Save and exit vi (`:wq`).

> **Important - CentOS differences**:
> - The service name is `repmgr-16`, not `repmgrd`
> - It depends on `postgresql-16.service`, not `postgresql.service`
> - The binary is at `/usr/pgsql-16/bin/repmgrd`
> - `RuntimeDirectory=repmgr` tells systemd to create `/run/repmgr/` automatically

Reload systemd and enable the service:

```bash
systemctl daemon-reload
```

This tells systemd to re-read its service files so it finds the new or updated `repmgr-16.service`.

```bash
systemctl enable repmgr-16
```

This configures repmgrd to start automatically on boot.

Expected output (yours will differ):
```
Created symlink /etc/systemd/system/multi-user.target.wants/repmgr-16.service ...
```

> **Concept - repmgrd as a systemd service**: Running repmgrd under systemd
> ensures it starts on boot and restarts on crash. The `After=postgresql-16.service`
> directive guarantees PostgreSQL is running before repmgrd starts. Without
> this dependency, repmgrd would fail to connect and exit.

## 3. Configure sudoers for the postgres user on ALL FOUR nodes

repmgr's `service_*_command` entries use `systemctl`. The postgres user
needs passwordless sudo for these specific commands. On ALL FOUR nodes:

```bash
sudo vi /etc/sudoers.d/postgres-repmgr
```

Enter the following content:

```
postgres ALL=(ALL) NOPASSWD: /bin/systemctl start postgresql-16, /bin/systemctl stop postgresql-16, /bin/systemctl restart postgresql-16, /bin/systemctl reload postgresql-16
```

Save and exit vi (`:wq`).

Set the correct permissions on the sudoers file:

```bash
sudo chmod 440 /etc/sudoers.d/postgres-repmgr
```

`440` means owner and group can read, no one can write. sudoers files must have restrictive permissions.

Verify it works:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
systemctl status postgresql-16
```

Expected: runs without asking for a password and shows `active (running)`.

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

## 4. Start repmgrd on ALL FOUR nodes

On ALL FOUR servers:

```bash
systemctl start repmgr-16
```

```bash
systemctl status repmgr-16
```

Expected: `active (running)`.

Expected output (yours will differ):
```
   Active: active (running) since ...
   ...
```

## 5. Verify repmgrd is monitoring

Wait 10-15 seconds for the first monitoring cycle, then check the log:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
tail -20 /var/lib/pgsql/16/data/log/repmgr.log
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

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

## 6. Check cluster events

From any node:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster event --limit 10
```

Expected: events showing `repmgrd_start` for all nodes.

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

## 7. Verify monitoring history is being recorded

Wait 30 seconds, then on NODE1:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql -d repmgr -c "
SELECT node_id, last_monitor_time, replication_lag
FROM repmgr.monitoring_history
ORDER BY last_monitor_time DESC
LIMIT 5;"
```

Expected output (yours will differ):
```
 node_id |     last_monitor_time      | replication_lag
---------+----------------------------+-----------------
       2 | 2026-05-22 14:30:15.123+00 |               0
       3 | 2026-05-22 14:30:15.456+00 |               0
       2 | 2026-05-22 14:30:13.123+00 |               0
       ...
```

Rows for node_id 2 and 3 with recent timestamps and low lag values.

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

> **Concept - monitoring_history**: When `monitoring_history=yes` is set in
> repmgr.conf, repmgrd writes replication lag measurements to this table on
> every monitoring cycle. This provides historical lag data for trending and
> alerting. In production, you would query this table from your monitoring
> system.

## 8. Test automatic failover detection (optional - read-only)

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

## 9. Run repmgr cluster crosscheck

This tests connectivity between all node pairs:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster crosscheck
```

Expected output (yours will differ):
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

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

> **Concept - cluster crosscheck**: This command has each node try to connect
> to every other node. It catches one-directional connectivity issues (where
> A can reach B but B cannot reach A). This is critical because repmgr
> operations like switchover require bidirectional SSH and PostgreSQL
> connectivity.

---

## What You Built

```
  NODE1 (primary)        NODE2 (standby 1)      NODE3 (standby 2)      NODE4 (witness)
 +---------------+      +---------------+      +---------------+      +---------------+
 | PostgreSQL 16 |      | PostgreSQL 16 |      | PostgreSQL 16 |      | PostgreSQL 16 |
 | repmgr 5.4    |      | repmgr 5.4    |      | repmgr 5.4    |      | repmgr 5.4    |
 | repmgrd       |      | repmgrd       |      | repmgrd       |      | repmgrd       |
 | id=1, primary |      | id=2, standby |      | id=3, standby |      | id=4, witness |
 +------+--------+      +---------------+      +---------------+      +---------------+
        |                      ^                      ^
        +-----streaming WAL----+                      |
        +-----streaming WAL---------------------------+

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
- [x] repmgrd systemd service (`repmgr-16`) created and enabled
- [x] Sudoers configured for postgres user to manage postgresql-16 service
- [x] repmgrd running and monitoring
- [x] Monitoring history being recorded
- [x] `repmgr cluster crosscheck` shows full connectivity

Run `build/verify.sh` to confirm everything before proceeding.
