# Build 04: Configure the Primary

Register NODE1 as the primary in the repmgr cluster and create test data.

All steps run on NODE1 only.

---

## 1. Create repmgr.conf on NODE1

Create the repmgr configuration file:

```bash
cat > /etc/repmgr.conf <<'EOF'
node_id=1
node_name='pg-repmgr-1'
conninfo='host=pg-repmgr-1 user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/16/main'

# Replication settings
use_replication_slots=true
monitoring_history=yes

# Logging
log_level=INFO
log_file='/var/log/postgresql/repmgr.log'
log_status_interval=60

# Service control (Debian/Ubuntu)
service_start_command='sudo systemctl start postgresql'
service_stop_command='sudo systemctl stop postgresql'
service_restart_command='sudo systemctl restart postgresql'
service_reload_command='sudo systemctl reload postgresql'

# Failover settings (repmgrd)
failover='automatic'
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'

# pg_rewind for node rejoin
use_replication_slots=true

# Monitoring
monitor_interval_secs=2
reconnect_attempts=6
reconnect_interval=10
EOF
```

Verify the file:
```bash
cat /etc/repmgr.conf
```

> **Concept - repmgr.conf is per-node**: Each node gets its own repmgr.conf with
> a unique `node_id` and `node_name`. The `conninfo` tells other nodes how to
> reach this one. The `service_*_command` entries let repmgr control PostgreSQL
> through systemd. The `failover`, `promote_command`, and `follow_command` drive
> automatic failover when the repmgrd daemon detects a primary failure.

> **Concept - promote_command and follow_command**: When repmgrd detects the
> primary is down, the election winner executes `promote_command` to become the
> new primary. All other standbys execute `follow_command` with `%n` replaced
> by the new primary's node_id, so they automatically start following the new
> primary. This is the core of repmgr's automatic failover.

> **Concept - reconnect_attempts and reconnect_interval**: These control how
> repmgrd behaves before declaring the primary dead. With `reconnect_attempts=6`
> and `reconnect_interval=10`, repmgrd tries to reach the primary 6 times at
> 10-second intervals (60 seconds total) before triggering failover. Tune these
> based on your tolerance for downtime vs false failovers.

## 2. Register NODE1 as primary

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf primary register
```

Expected:
```
INFO: connecting to primary database...
NOTICE: attempting to install extension "repmgr"
NOTICE: "repmgr" extension is already installed
NOTICE: primary node record (ID: 1) registered
```

Verify:
```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf cluster show
```

Expected:
```
 ID | Name         | Role    | Status    | Upstream | Location | Priority | Timeline | Connection string
----+--------------+---------+-----------+----------+----------+----------+----------+-------------------------------------------
 1  | pg-repmgr-1  | primary | * running |          | default  | 100      | 1        | host=pg-repmgr-1 user=repmgr dbname=repmgr
```

> **Concept - repmgr cluster show**: This is the single most important command
> for understanding your cluster's topology. It reads the `repmgr.nodes` table
> and actively tests each node's connectivity. The `*` next to a role means
> repmgr confirmed that node is actually performing that role (not just registered
> as it). A `!` would indicate a problem - the node is registered but not
> behaving as expected.

## 3. Create a test database with sample data

```bash
sudo -iu postgres psql <<SQL
CREATE DATABASE labdb;
\c labdb
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    department TEXT NOT NULL,
    hired_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO employees (name, department)
SELECT 'employee_' || g,
       (ARRAY['engineering','sales','support','ops'])[1 + (g % 4)]
FROM generate_series(1, 10000) g;
SQL
```

Verify:
```bash
sudo -iu postgres psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: `10000`.

## 4. Check the repmgr metadata

```bash
sudo -iu postgres psql -d repmgr -c "SELECT * FROM repmgr.nodes;"
```

Expected: one row for NODE1 with `type = 'primary'` and `active = t`.

```bash
sudo -iu postgres psql -d repmgr -c "SELECT * FROM repmgr.events ORDER BY event_timestamp DESC LIMIT 5;"
```

Expected: a `primary_register` event.

> **Concept - repmgr metadata tables**: The `repmgr.nodes` table tracks every
> registered node, its role, connection info, and active status. The
> `repmgr.events` table logs every significant event (registrations, promotions,
> failovers). These tables replicate to all standbys through normal streaming
> replication, so every node has a copy of the cluster state.

---

## Checkpoint

NODE1 (primary) has:
- [x] `/etc/repmgr.conf` created with node_id=1
- [x] Registered as primary with `repmgr primary register`
- [x] `repmgr cluster show` displays NODE1 as `* running` primary
- [x] `labdb` database with 10,000 test rows
- [x] repmgr metadata tables populated

Proceed to `05-clone-standbys.md`.
