# Build 06: Configure the Witness Node

Set up NODE4 as a witness server. The witness does NOT replicate data - it
exists solely to participate in failover elections and prevent split-brain.

All steps run on NODE4 unless noted.

---

## 1. Understand the witness role

> **Concept - Why a witness node exists**: Consider a 2-node cluster (1 primary
> + 1 standby). If the standby loses network connectivity to the primary, it
> cannot tell whether the primary crashed or the network between them is down.
> Without additional information, promoting the standby risks split-brain. A
> witness on a separate network segment provides a tiebreaker vote. If the
> standby can reach the witness but not the primary, and the witness also cannot
> reach the primary, it is likely the primary is actually down. If the standby
> cannot reach the witness either, the problem is probably the standby's own
> network - and promotion should be blocked.

> **Concept - Witness does NOT replicate**: The witness runs PostgreSQL, but it
> does not stream WAL from the primary. It has its own independent copy of the
> repmgr metadata (created during registration). This is intentional - the witness
> must be on a separate failure domain from the data nodes.

## 2. Verify PostgreSQL is running on NODE4

```bash
sudo -iu postgres psql -c "SELECT version();"
```

Expected: PostgreSQL 16.x running.

## 3. Create repmgr.conf on NODE4

```bash
cat > /etc/repmgr.conf <<'EOF'
node_id=4
node_name='pg-repmgr-w'
conninfo='host=pg-repmgr-w user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/16/main'

use_replication_slots=true
monitoring_history=yes

log_level=INFO
log_file='/var/log/postgresql/repmgr.log'
log_status_interval=60

service_start_command='sudo systemctl start postgresql'
service_stop_command='sudo systemctl stop postgresql'
service_restart_command='sudo systemctl restart postgresql'
service_reload_command='sudo systemctl reload postgresql'

failover='automatic'
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'

monitor_interval_secs=2
reconnect_attempts=6
reconnect_interval=10
EOF
```

## 4. Configure pg_hba.conf on NODE4

On NODE4, add the same repmgr access rules:

```bash
cat >> /etc/postgresql/16/main/pg_hba.conf <<EOF

# repmgr connections
local   repmgr        repmgr                              trust
host    repmgr        repmgr        [NODE1_IP]/32         trust
host    repmgr        repmgr        [NODE2_IP]/32         trust
host    repmgr        repmgr        [NODE3_IP]/32         trust
host    repmgr        repmgr        [NODE4_IP]/32         trust

local   replication   repmgr                              trust
host    replication   repmgr        [NODE1_IP]/32         trust
host    replication   repmgr        [NODE2_IP]/32         trust
host    replication   repmgr        [NODE3_IP]/32         trust
host    replication   repmgr        [NODE4_IP]/32         trust
EOF

sudo systemctl reload postgresql
```

## 5. Register NODE4 as a witness

On NODE4:

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf \
  -h pg-repmgr-1 -U repmgr -d repmgr \
  witness register
```

Expected:
```
INFO: connecting to witness node "pg-repmgr-w" (ID: 4)
INFO: connecting to primary node
NOTICE: attempting to install extension "repmgr"
NOTICE: witness registration complete
NOTICE: witness node "pg-repmgr-w" (ID: 4) successfully registered
```

> **Concept - What witness register does**: This command connects to the primary,
> copies the repmgr metadata tables to the witness's local PostgreSQL instance,
> and registers the witness in the cluster. The witness now has its own copy of
> `repmgr.nodes` and `repmgr.events`. Unlike standbys, the witness does NOT
> stream WAL - its metadata is periodically synced by repmgrd.

## 6. Verify the full 4-node cluster

From any node:

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf cluster show
```

Expected:
```
 ID | Name         | Role    | Status    | Upstream    | Location | Priority | Timeline | Connection string
----+--------------+---------+-----------+-------------+----------+----------+----------+-------------------------------------------
 1  | pg-repmgr-1  | primary | * running |             | default  | 100      | 1        | host=pg-repmgr-1 user=repmgr dbname=repmgr
 2  | pg-repmgr-2  | standby |   running | pg-repmgr-1 | default  | 100      | 1        | host=pg-repmgr-2 user=repmgr dbname=repmgr
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-1 | default  | 100      | 1        | host=pg-repmgr-3 user=repmgr dbname=repmgr
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-1 | default  | 0        | 1        | host=pg-repmgr-w user=repmgr dbname=repmgr
```

Note: the witness has `Priority = 0` because it should never be promoted.
Its upstream is the primary because it syncs its metadata from the primary.

## 7. Run repmgr node check on the witness

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf node check
```

Expected: all checks should pass.

## 8. Verify the witness is NOT replicating

On NODE1 (primary), check replication connections:

```bash
sudo -iu postgres psql -c "SELECT client_addr, state FROM pg_stat_replication;"
```

Expected: two rows (NODE2 and NODE3). NODE4 should NOT appear - it does not
stream WAL.

---

## Checkpoint

NODE4 (witness) has:
- [x] `/etc/repmgr.conf` with node_id=4
- [x] pg_hba.conf allows repmgr connections from all nodes
- [x] Registered as witness with `repmgr witness register`
- [x] Shows as `* running` witness in `repmgr cluster show`
- [x] NOT streaming WAL (not in pg_stat_replication)

Full cluster:
- [x] 4 nodes visible in `repmgr cluster show`
- [x] 1 primary + 2 standbys + 1 witness
- [x] All nodes show `running` status

Proceed to `07-enable-automatic-failover.md`.
