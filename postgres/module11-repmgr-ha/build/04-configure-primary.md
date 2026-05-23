# Build 04: Configure the Primary (CentOS Stream 9)

Register NODE1 as the primary in the repmgr cluster and create test data.

All steps run on NODE1 only.

---

## 1. Create repmgr.conf on NODE1

Create the repmgr configuration file:

```bash
sudo vi /etc/repmgr/16/repmgr.conf
```

> **Note**: On CentOS with the `repmgr_16` package, the config directory
> `/etc/repmgr/16/` should already exist. If it does not, create it first:
> `sudo mkdir -p /etc/repmgr/16`

Enter the following content:

```
node_id=1
node_name='pg-repmgr-1'
conninfo='host=pg-repmgr-1 user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/pgsql/16/data'

# Replication settings
use_replication_slots=true
monitoring_history=yes

# Logging
log_level=INFO
log_file='/var/lib/pgsql/16/data/log/repmgr.log'
log_status_interval=60

# Service control (CentOS Stream 9 - service is postgresql-16)
service_start_command='sudo systemctl start postgresql-16'
service_stop_command='sudo systemctl stop postgresql-16'
service_restart_command='sudo systemctl restart postgresql-16'
service_reload_command='sudo systemctl reload postgresql-16'

# Failover settings (repmgrd)
failover='automatic'
promote_command='/usr/pgsql-16/bin/repmgr standby promote -f /etc/repmgr/16/repmgr.conf --log-to-file'
follow_command='/usr/pgsql-16/bin/repmgr standby follow -f /etc/repmgr/16/repmgr.conf --log-to-file --upstream-node-id=%n'

# pg_rewind for node rejoin
use_replication_slots=true

# Monitoring
monitor_interval_secs=2
reconnect_attempts=6
reconnect_interval=10
```

Save and exit vi (`:wq`).

Verify the file was saved:

```bash
cat /etc/repmgr/16/repmgr.conf
```

Expected: the contents you just typed.

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

> **Concept - CentOS service name**: On CentOS the service is `postgresql-16`,
> not `postgresql`. The `service_*_command` entries must use the correct name
> or repmgr will fail to start/stop PostgreSQL during switchover and failover.

## 2. Make sure the log directory exists

The log file path in repmgr.conf points to `/var/lib/pgsql/16/data/log/`. This directory is created by PostgreSQL on CentOS, but let's verify:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
ls -la /var/lib/pgsql/16/data/log/
```

Expected: the directory exists and contains PostgreSQL log files.

If the directory does not exist, create it:

```bash
mkdir -p /var/lib/pgsql/16/data/log
```

## 3. Register NODE1 as primary

You should still be the postgres user from Step 2. If not, run `sudo -iu postgres`.

```bash
repmgr -f /etc/repmgr/16/repmgr.conf primary register
```

Expected output (yours will differ):
```
INFO: connecting to primary database...
NOTICE: attempting to install extension "repmgr"
NOTICE: "repmgr" extension is already installed
NOTICE: primary node record (ID: 1) registered
```

Verify:

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output (yours will differ):
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

## 4. Create a test database with sample data

You should still be the postgres user from Step 3. If not, run `sudo -iu postgres`.

```bash
psql <<SQL
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

Expected output (yours will differ):
```
CREATE DATABASE
You are now connected to database "labdb" as user "postgres".
CREATE TABLE
INSERT 0 10000
```

Verify:

```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: `10000`.

## 5. Check the repmgr metadata

You should still be the postgres user. If not, run `sudo -iu postgres`.

```bash
psql -d repmgr -c "SELECT * FROM repmgr.nodes;"
```

Expected: one row for NODE1 with `type = 'primary'` and `active = t`.

```bash
psql -d repmgr -c "SELECT * FROM repmgr.events ORDER BY event_timestamp DESC LIMIT 5;"
```

Expected: a `primary_register` event.

```bash
exit
```

**You are now back to ec2-user.**

> **Concept - repmgr metadata tables**: The `repmgr.nodes` table tracks every
> registered node, its role, connection info, and active status. The
> `repmgr.events` table logs every significant event (registrations, promotions,
> failovers). These tables replicate to all standbys through normal streaming
> replication, so every node has a copy of the cluster state.

---

## Checkpoint

NODE1 (primary) has:
- [x] `/etc/repmgr/16/repmgr.conf` created with node_id=1
- [x] Registered as primary with `repmgr primary register`
- [x] `repmgr cluster show` displays NODE1 as `* running` primary
- [x] `labdb` database with 10,000 test rows
- [x] repmgr metadata tables populated

Proceed to `05-clone-standbys.md`.
