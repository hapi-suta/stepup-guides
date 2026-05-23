# Build 06: Configure the Witness Node (CentOS Stream 9)

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
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -c "SELECT version();"
```

Expected output (yours will differ):
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

```bash
exit
```

**You are now back to ec2-user.**

## 3. Create repmgr.conf on NODE4

```bash
sudo vi /etc/repmgr/16/repmgr.conf
```

> **Note**: If the directory `/etc/repmgr/16/` does not exist, create it first:
> `sudo mkdir -p /etc/repmgr/16`

Enter the following content:

```
node_id=4
node_name='pg-repmgr-w'
conninfo='host=pg-repmgr-w user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/pgsql/16/data'

use_replication_slots=true
monitoring_history=yes

log_level=INFO
log_file='/var/lib/pgsql/16/data/log/repmgr.log'
log_status_interval=60

service_start_command='sudo systemctl start postgresql-16'
service_stop_command='sudo systemctl stop postgresql-16'
service_restart_command='sudo systemctl restart postgresql-16'
service_reload_command='sudo systemctl reload postgresql-16'

failover='automatic'
promote_command='/usr/pgsql-16/bin/repmgr standby promote -f /etc/repmgr/16/repmgr.conf --log-to-file'
follow_command='/usr/pgsql-16/bin/repmgr standby follow -f /etc/repmgr/16/repmgr.conf --log-to-file --upstream-node-id=%n'

monitor_interval_secs=2
reconnect_attempts=6
reconnect_interval=10
```

Save and exit vi (`:wq`).

## 4. Configure pg_hba.conf on NODE4

On NODE4, add the repmgr access rules so the witness can communicate with all nodes.

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
vi /var/lib/pgsql/16/data/pg_hba.conf
```

Add these lines at the end of the file (substitute your actual IPs for the placeholders):

```
# repmgr connections
local   repmgr        repmgr                              trust
host    repmgr        repmgr        [NODE1_IP]/32         trust
host    repmgr        repmgr        [NODE2_IP]/32         trust
host    repmgr        repmgr        [NODE3_IP]/32         trust
host    repmgr        repmgr        [NODE4_IP]/32         trust

# replication connections
local   replication   repmgr                              trust
host    replication   repmgr        [NODE1_IP]/32         trust
host    replication   repmgr        [NODE2_IP]/32         trust
host    replication   repmgr        [NODE3_IP]/32         trust
host    replication   repmgr        [NODE4_IP]/32         trust
```

Save and exit vi (`:wq`).

```bash
exit
```

**You are now back to ec2-user.**

Reload PostgreSQL to apply the new pg_hba.conf:

```bash
sudo systemctl reload postgresql-16
```

## 5. Register NODE4 as a witness

On NODE4:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
repmgr -f /etc/repmgr/16/repmgr.conf \
  -h pg-repmgr-1 -U repmgr -d repmgr \
  witness register
```

Expected output (yours will differ):
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

You should still be the postgres user from Step 5.

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output (yours will differ):
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

You should still be the postgres user.

```bash
repmgr -f /etc/repmgr/16/repmgr.conf node check
```

Expected: all checks should pass.

```bash
exit
```

**You are now back to ec2-user.**

## 8. Verify the witness is NOT replicating

On NODE1 (primary), check replication connections:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
psql -c "SELECT client_addr, state FROM pg_stat_replication;"
```

Expected output (yours will differ):
```
  client_addr   |   state
----------------+-----------
 [NODE2_IP]     | streaming
 [NODE3_IP]     | streaming
(2 rows)
```

Two rows (NODE2 and NODE3). NODE4 should NOT appear - it does not stream WAL.

```bash
exit
```

**You are now back to ec2-user.**

---

## Checkpoint

NODE4 (witness) has:
- [x] `/etc/repmgr/16/repmgr.conf` with node_id=4
- [x] pg_hba.conf allows repmgr connections from all nodes
- [x] Registered as witness with `repmgr witness register`
- [x] Shows as `* running` witness in `repmgr cluster show`
- [x] NOT streaming WAL (not in pg_stat_replication)

Full cluster:
- [x] 4 nodes visible in `repmgr cluster show`
- [x] 1 primary + 2 standbys + 1 witness
- [x] All nodes show `running` status

Proceed to `07-enable-automatic-failover.md`.
