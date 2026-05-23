# Exercise 01 - Check Cluster Status (CentOS Stream 9)

**Time estimate:** 15-20 minutes
**Prerequisites:** BUILD phase complete - 4-node repmgr cluster running (1 primary + 2 standbys + 1 witness)

---

## Objective

Learn every repmgr monitoring command. By the end of this exercise, you should be able to assess cluster health from any node without referencing this guide.

---

## Step 1 - repmgr cluster show

This is the single most important command. Run it from any node.

Switch to the postgres user. All commands in this exercise run as the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for all steps in this exercise.**

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

**Expected output (yours will differ):**
```
 ID | Name         | Role    | Status    | Upstream    | Location | Priority | Timeline | Connection string
----+--------------+---------+-----------+-------------+----------+----------+----------+-------------------------------------------
 1  | pg-repmgr-1  | primary | * running |             | default  | 100      | 1        | host=pg-repmgr-1 user=repmgr dbname=repmgr
 2  | pg-repmgr-2  | standby |   running | pg-repmgr-1 | default  | 100      | 1        | host=pg-repmgr-2 user=repmgr dbname=repmgr
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-1 | default  | 100      | 1        | host=pg-repmgr-3 user=repmgr dbname=repmgr
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-1 | default  | 0        | 1        | host=pg-repmgr-w user=repmgr dbname=repmgr
```

**Understand the status indicators:**
- `* running` = repmgr verified the node is active and performing its registered role
- `running` (no asterisk) = node is reachable but repmgr has not verified its exact role
- `! running` = node is running but not performing its registered role (role mismatch)
- `- failed` = node is unreachable

> **Concept - cluster show reads repmgr.nodes**: This command queries the
> `repmgr.nodes` table (which exists on every node through replication) and
> then actively connects to each node to verify its status. The combination
> of stored metadata + live checks gives you a complete cluster picture.

---

## Step 2 - repmgr node check

Run a detailed health check on the local node:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node check
```

**Expected output (on a standby, yours will differ):**
```
Node "pg-repmgr-2":
    Server role: OK (node is standby)
    Replication lag: OK (0 seconds)
    WAL archiving: OK (0 pending archive ready files)
    Upstream connection: OK (node "pg-repmgr-2" (ID: 2) is attached to expected upstream node "pg-repmgr-1" (ID: 1))
    Downstream servers: OK (this node has no downstream nodes)
    Replication slots: OK (node has no physical replication slots)
    Missing physical replication slots: OK (node has no missing physical replication slots)
    Configured data directory: OK (configured value matches actual data directory)
```

Run it on each node to verify all health checks pass.

> **Concept - node check vs cluster show**: `cluster show` gives you the
> bird's-eye view of all nodes. `node check` gives you a deep health check
> of a single node. Use `cluster show` for quick status, `node check` for
> troubleshooting a specific node.

---

## Step 3 - repmgr cluster event

View the event log:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster event --limit 20
```

**Expected:** Events like `primary_register`, `standby_register`, `witness_register`, `repmgrd_start`.

Filter for specific event types:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster event --event=standby_register
```

Filter for a specific node:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster event --node-id=2 --limit 5
```

> **Concept - repmgr.events as audit trail**: Every significant cluster
> operation (registration, promotion, failover, follow) is logged as an event.
> This is your audit trail for understanding what happened during an incident.
> In production, you can also configure `event_notification_command` to send
> events to your alerting system.

---

## Step 4 - repmgr cluster crosscheck

Test connectivity between all node pairs:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster crosscheck
```

**Expected output (yours will differ):**
```
 Name         | ID | 1 | 2 | 3 | 4
--------------+----+---+---+---+---
 pg-repmgr-1  |  1 | * | * | * | *
 pg-repmgr-2  |  2 | * | * | * | *
 pg-repmgr-3  |  3 | * | * | * | *
 pg-repmgr-w  |  4 | * | * | * | *
```

Any `x` in the matrix indicates a connectivity problem between those two nodes.

---

## Step 5 - Check replication lag with repmgr

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node status
```

This shows the node's current replication lag, received LSN, and replayed LSN.

Also check native PostgreSQL replication views.

On the primary:

```sql
SELECT
    client_addr, state, sync_state,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

**Expected:** Two rows (NODE2 and NODE3), both `streaming`, lag near zero.

---

## Step 6 - Check replication slots

On the primary:

```sql
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots;
```

**Expected:** Two active physical slots (repmgr_slot_2 and repmgr_slot_3).

> **Concept - repmgr-managed replication slots**: When `use_replication_slots=true`
> in repmgr.conf, repmgr creates and manages a slot per standby. The naming
> convention is `repmgr_slot_<node_id>`. These slots prevent WAL recycling
> while a standby is catching up, but also mean abandoned slots can fill
> the primary's disk.

---

## Step 7 - Check monitoring history

On the primary:

```sql
SELECT
    node_id, last_monitor_time,
    replication_lag, last_wal_primary_location, last_wal_standby_location
FROM repmgr.monitoring_history
ORDER BY last_monitor_time DESC
LIMIT 10;
```

**Expected:** Recent rows for node_id 2 and 3 with low replication_lag values.

---

## Step 8 - Build a combined health check

Run each of these commands one at a time. You should still be the postgres user.

Check cluster topology:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Check replication status:

```bash
psql -c "
SELECT client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;"
```

Check replication slots:

```bash
psql -c "
SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS slot_lag
FROM pg_replication_slots;"
```

Check recent events:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster event --limit 5
```

When done with this exercise, exit the postgres user:

```bash
exit
```

**You are now back to ec2-user.**

---

## Checkpoint

Before continuing, confirm:
- [ ] You can read `repmgr cluster show` and identify each node's role and status
- [ ] You checked `repmgr node check` on at least two nodes
- [ ] You viewed the event log with `repmgr cluster event`
- [ ] You ran `repmgr cluster crosscheck` and all nodes show `*`
- [ ] You checked replication lag using both repmgr and native PG views
- [ ] You verified replication slots are active

---

**Next:** [02 - Manual Switchover](02-manual-switchover.md)
