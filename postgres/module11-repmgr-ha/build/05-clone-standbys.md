# Build 05: Clone Standbys

Clone NODE2 and NODE3 from the primary using `repmgr standby clone` and
register them as standbys.

---

## NODE2 - Clone and Register

### 1. Create repmgr.conf on NODE2

```bash
cat > /etc/repmgr.conf <<'EOF'
node_id=2
node_name='pg-repmgr-2'
conninfo='host=pg-repmgr-2 user=repmgr dbname=repmgr connect_timeout=2'
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

use_replication_slots=true

monitor_interval_secs=2
reconnect_attempts=6
reconnect_interval=10
EOF
```

### 2. Stop PostgreSQL on NODE2

```bash
sudo systemctl stop postgresql
```

### 3. Dry-run the clone

Always dry-run first to catch config issues:

```bash
sudo -iu postgres repmgr -h pg-repmgr-1 -U repmgr -d repmgr \
  -f /etc/repmgr.conf standby clone --dry-run
```

Expected:
```
NOTICE: destination directory "/var/lib/postgresql/16/main" provided
INFO: connecting to source node
DETAIL: connection string is: host=pg-repmgr-1 user=repmgr dbname=repmgr
NOTICE: checking for available walsenders on the source node (2 required)
INFO: sufficient walsenders available on the source node
NOTICE: standby will attach to upstream node 1
INFO: all prerequisites for "standby clone" are met
```

> **Concept - Always dry-run**: `repmgr standby clone --dry-run` validates
> connectivity, pg_hba.conf rules, WAL sender availability, and disk space
> before touching any data. This prevents discovering a misconfiguration
> halfway through a multi-gigabyte base backup.

### 4. Run the actual clone

```bash
sudo -iu postgres repmgr -h pg-repmgr-1 -U repmgr -d repmgr \
  -f /etc/repmgr.conf standby clone
```

Expected:
```
NOTICE: destination directory "/var/lib/postgresql/16/main" provided
INFO: connecting to source node
NOTICE: checking for available walsenders on the source node
INFO: sufficient walsenders available on the source node
NOTICE: starting backup (using pg_basebackup)...
HINT: this may take some time; consider using the -c/--fast-checkpoint option
INFO: executing:
  pg_basebackup -l "repmgr base backup" -D /var/lib/postgresql/16/main -h pg-repmgr-1 -U repmgr -X stream -S repmgr_slot_2
NOTICE: standby clone (using pg_basebackup) complete
NOTICE: you can now start your PostgreSQL server
```

> **Concept - What repmgr standby clone does under the hood**: It runs
> `pg_basebackup` against the primary, creates a replication slot
> (repmgr_slot_2 for node_id=2), writes `standby.signal` and
> `primary_conninfo` to `postgresql.auto.conf`, and copies the pg_hba.conf
> from the primary. This is equivalent to the manual base backup process
> from the streaming-replication lab, but automated.

### 5. Start PostgreSQL on NODE2

```bash
sudo systemctl start postgresql
```

Verify it is streaming:
```bash
sudo -iu postgres psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t`.

### 6. Register NODE2 as a standby

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf standby register
```

Expected:
```
INFO: connecting to local node "pg-repmgr-2" (ID: 2)
INFO: connecting to primary database
INFO: standby registration complete
NOTICE: standby node "pg-repmgr-2" (ID: 2) successfully registered
```

### 7. Verify the cluster now shows 2 nodes

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf cluster show
```

Expected:
```
 ID | Name         | Role    | Status    | Upstream    | Location | Priority | Timeline | Connection string
----+--------------+---------+-----------+-------------+----------+----------+----------+-------------------------------------------
 1  | pg-repmgr-1  | primary | * running |             | default  | 100      | 1        | host=pg-repmgr-1 user=repmgr dbname=repmgr
 2  | pg-repmgr-2  | standby |   running | pg-repmgr-1 | default  | 100      | 1        | host=pg-repmgr-2 user=repmgr dbname=repmgr
```

### 8. Verify data replicated to NODE2

```bash
sudo -iu postgres psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: `10000`.

---

## NODE3 - Clone and Register

### 9. Create repmgr.conf on NODE3

```bash
cat > /etc/repmgr.conf <<'EOF'
node_id=3
node_name='pg-repmgr-3'
conninfo='host=pg-repmgr-3 user=repmgr dbname=repmgr connect_timeout=2'
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

use_replication_slots=true

monitor_interval_secs=2
reconnect_attempts=6
reconnect_interval=10
EOF
```

### 10. Stop PostgreSQL, clone, start

```bash
sudo systemctl stop postgresql

sudo -iu postgres repmgr -h pg-repmgr-1 -U repmgr -d repmgr \
  -f /etc/repmgr.conf standby clone --dry-run

sudo -iu postgres repmgr -h pg-repmgr-1 -U repmgr -d repmgr \
  -f /etc/repmgr.conf standby clone

sudo systemctl start postgresql
```

### 11. Register NODE3 as a standby

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf standby register
```

### 12. Verify the cluster shows 3 nodes

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
```

### 13. Verify data on NODE3

```bash
sudo -iu postgres psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: `10000`.

> **Concept - Replication slots per standby**: repmgr creates a dedicated
> replication slot for each standby (repmgr_slot_2, repmgr_slot_3, etc.).
> This prevents the primary from recycling WAL that any standby still needs.
> You can see the slots on the primary:

Verify slots on NODE1:
```bash
sudo -iu postgres psql -c "SELECT slot_name, active FROM pg_replication_slots;"
```

Expected: two slots, both active.

---

## Checkpoint

NODE2 and NODE3 have:
- [x] `/etc/repmgr.conf` with unique node_id (2 and 3)
- [x] Cloned from primary using `repmgr standby clone`
- [x] PostgreSQL running in recovery mode
- [x] Registered as standbys with `repmgr standby register`
- [x] Data matches primary (10,000 rows)

The cluster shows:
- [x] 3 nodes in `repmgr cluster show`
- [x] 1 primary + 2 standbys, all `running`
- [x] Replication slots active on primary

Proceed to `06-configure-witness.md`.
