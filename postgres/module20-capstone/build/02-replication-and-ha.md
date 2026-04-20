# Build 02: Replication and High Availability

Set up streaming replication, synchronous commit, pgBouncer connection pooling, and automatic failover. By the end of this guide, you will have a production HA cluster that can survive a primary failure.

This guide requires **two servers**: primary (pg-prod-primary) and standby (pg-prod-standby).

Complete [Build 01](01-production-deployment.md) on the primary before starting.

---

## Prerequisites

- Primary server running PostgreSQL 16 from Build 01
- Second server (standby) with the same OS prep (sections 1-3 of Build 01)
- PostgreSQL 16 installed on the standby (section 3 of Build 01)
- Network connectivity between both servers on port 5432
- SSH access between both servers

---

## 1. Prepare the Primary for Replication

### 1.1 Verify WAL level

Log into the **primary** server.

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

Expected output:
```
 wal_level
-----------
 replica
```

If it shows `minimal`, you need to update postgresql.conf and restart. We set this in Build 01.

### 1.2 Create a replication slot

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_create_physical_replication_slot('standby_slot_1');"
```

Expected output:
```
 pg_create_physical_replication_slot
--------------------------------------
 (standby_slot_1,)
```

A replication slot guarantees that the primary retains WAL segments the standby has not yet consumed. Without a slot, the primary might delete WAL segments before the standby catches up, breaking replication.

### 1.3 Verify pg_hba.conf allows replication

```bash
grep replication /opt/pgsql/data/pg_hba.conf
```

Expected output:
```
hostssl replication     replicator      0.0.0.0/0               scram-sha-256
```

This was configured in Build 01. The `replicator` role can connect for replication over SSL.

### 1.4 Set the replicator password

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE replicator WITH PASSWORD 'R3pl!cat0r_2026';"
```

If you already set this in Build 01, this is a no-op (same password).

```bash
exit
```

---

## 2. Take a Base Backup for the Standby

### 2.1 Run pg_basebackup from the standby

Log into the **standby** server.

First, make sure the data directory is empty:

```bash
ls /opt/pgsql/data/
```

It should be empty or not exist. If it has files from a previous initdb, clear them:

```bash
rm -rf /opt/pgsql/data/*
```

```bash
rm -rf /opt/pgsql/wal/*
```

Now take the base backup. Switch to the postgres user:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/pg_basebackup -h [PRIMARY_IP] -U replicator -D /opt/pgsql/data --waldir=/opt/pgsql/wal -X stream -P -R -S standby_slot_1
```

When prompted, enter the replicator password: `R3pl!cat0r_2026`

- `-h [PRIMARY_IP]` - Connect to the primary server. Replace with your primary's IP address.
- `-U replicator` - Connect as the replication user.
- `-D /opt/pgsql/data` - Write the backup to the standby's data directory.
- `--waldir=/opt/pgsql/wal` - Put WAL files in the separate WAL directory.
- `-X stream` - Stream WAL during the backup so it is consistent without needing to archive.
- `-P` - Show progress percentage.
- `-R` - Automatically create standby.signal and configure primary_conninfo in postgresql.auto.conf.
- `-S standby_slot_1` - Use the replication slot we created.

Expected output (yours will differ):
```
Password:
30318/30318 kB (100%), 1/1 tablespace
```

### 2.2 Verify the standby configuration

```bash
cat /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):
```
primary_conninfo = 'user=replicator password=R3pl!cat0r_2026 channel_binding=prefer host=[PRIMARY_IP] port=5432 sslmode=prefer ...'
primary_slot_name = 'standby_slot_1'
```

```bash
ls -la /opt/pgsql/data/standby.signal
```

Expected output:
```
-rw------- 1 postgres postgres 0 Apr 19 ... /opt/pgsql/data/standby.signal
```

The `standby.signal` file tells PostgreSQL to start in standby (recovery) mode.

### 2.3 Configure the standby's postgresql.conf

```bash
vi /opt/pgsql/data/postgresql.conf
```

Add or update these settings:

```
hot_standby = on
hot_standby_feedback = on
```

Save and exit (`:wq`).

- `hot_standby = on` - Allows read queries on the standby while it replays WAL.
- `hot_standby_feedback = on` - The standby tells the primary about its active queries. This prevents the primary from vacuuming rows the standby still needs.

```bash
exit
```

---

## 3. Start the Standby

### 3.1 Copy the systemd service

On the **standby** as root, create the same systemd service file as the primary:

```bash
vi /etc/systemd/system/postgresql-16.service
```

Use the same content from Build 01 section 8.1.

Save and exit (`:wq`).

```bash
systemctl daemon-reload
```

```bash
systemctl enable postgresql-16
```

```bash
systemctl start postgresql-16
```

```bash
systemctl status postgresql-16
```

Expected output (yours will differ):
```
 postgresql-16.service - PostgreSQL 16 Production
     Active: active (running) ...
```

### 3.2 Verify replication is working

On the **standby**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output:
```
 pg_is_in_recovery
--------------------
 t
```

`t` means this server is in recovery mode (standby).

Now check on the **primary**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state, sync_state, replay_lsn, sent_lsn FROM pg_stat_replication;"
```

Expected output (yours will differ):
```
  client_addr   |   state   | sync_state | replay_lsn | sent_lsn
----------------+-----------+------------+------------+----------
 192.168.1.101  | streaming | async      | 0/5000060  | 0/5000060
```

- `state = streaming` - Replication is active.
- `sync_state = async` - Currently asynchronous. We will change this next.
- `replay_lsn = sent_lsn` - The standby has replayed everything the primary sent. No lag.

```bash
exit
```

---

## 4. Configure Synchronous Replication

### 4.1 Enable synchronous commit

On the **primary**:

```bash
su - postgres
```

```bash
vi /opt/pgsql/data/postgresql.conf
```

Add:

```
synchronous_standby_names = 'FIRST 1 (standby_slot_1)'
synchronous_commit = on
```

Save and exit (`:wq`).

- `synchronous_standby_names` - Defines which standbys must confirm writes. `FIRST 1` means the primary waits for at least one standby to flush WAL before confirming a commit.
- `synchronous_commit = on` - The default. With synchronous_standby_names set, commits wait for standby acknowledgment.

> **Concept - Synchronous replication trade-off**: Synchronous replication guarantees zero data loss (RPO = 0) because every committed transaction exists on at least two servers. The cost is higher commit latency - every write must round-trip to the standby. For most production workloads, the safety is worth the latency.

### 4.2 Reload the configuration

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_reload_conf();"
```

A reload is sufficient for this change. No restart needed.

### 4.3 Verify synchronous mode

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, sync_state FROM pg_stat_replication;"
```

Expected output:
```
  client_addr   | sync_state
----------------+------------
 192.168.1.101  | sync
```

The `sync_state` changed from `async` to `sync`.

### 4.4 Test synchronous commit

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('sync-test@example.com', 'Sync Test');"
```

If the standby is down or unreachable, this INSERT will **hang** until the standby comes back. That is the synchronous guarantee - no silent data loss.

```bash
exit
```

---

## 5. Install and Configure pgBouncer

### 5.1 Install pgBouncer on the primary

Run as root on the **primary**:

```bash
dnf install -y pgbouncer
```

### 5.2 Create the authentication file

pgBouncer needs to know user passwords. Create a userlist file:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -t -A -c "SELECT '\"' || rolname || '\" \"' || rolpassword || '\"' FROM pg_authid WHERE rolcanlogin AND rolpassword IS NOT NULL;" > /etc/pgbouncer/userlist.txt
```

This queries the password hashes from PostgreSQL and writes them in pgBouncer's format.

```bash
exit
```

```bash
chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt
```

```bash
chmod 600 /etc/pgbouncer/userlist.txt
```

### 5.3 Configure pgBouncer

```bash
vi /etc/pgbouncer/pgbouncer.ini
```

Replace the contents with:

```ini
[databases]
appdb = host=127.0.0.1 port=5432 dbname=appdb

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

pool_mode = transaction
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3

max_client_conn = 1000
max_db_connections = 150

server_idle_timeout = 300
server_lifetime = 3600
server_connect_timeout = 15

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

admin_users = postgres
stats_users = postgres, app_owner

pidfile = /var/run/pgbouncer/pgbouncer.pid
logfile = /var/log/pgbouncer/pgbouncer.log
```

Save and exit (`:wq`).

Key settings:
- `pool_mode = transaction` - Connections are returned to the pool after each transaction. This is the most efficient mode and what most applications should use.
- `default_pool_size = 25` - Each user/database pair gets 25 server connections.
- `max_client_conn = 1000` - pgBouncer can accept up to 1000 client connections and multiplex them into 150 server connections.
- `max_db_connections = 150` - Total server connections to PostgreSQL, across all pools. Set this below `max_connections` in PostgreSQL (200).
- `server_idle_timeout = 300` - Close idle server connections after 5 minutes.

> **Concept - Connection pooling**: PostgreSQL forks a new process for every connection. Each process uses ~5-10 MB of RAM. With 1000 direct connections, that is 5-10 GB just for connection overhead. pgBouncer multiplexes 1000 clients into ~25 server connections, saving memory and reducing context switching.

### 5.4 Configure the firewall for pgBouncer

```bash
firewall-cmd --permanent --add-port=6432/tcp
```

```bash
firewall-cmd --reload
```

### 5.5 Start pgBouncer

```bash
systemctl enable pgbouncer
```

```bash
systemctl start pgbouncer
```

```bash
systemctl status pgbouncer
```

Expected output (yours will differ):
```
 pgbouncer.service - Connection pooler for PostgreSQL
     Active: active (running) ...
```

### 5.6 Test pgBouncer

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 6432 -U app_readwrite -d appdb -c "SELECT count(*) FROM app.customers;"
```

Expected output:
```
 count
-------
  1001
```

Check pgBouncer stats:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c "SHOW pools;"
```

Expected output (yours will differ):
```
 database |    user     | cl_active | cl_waiting | sv_active | sv_idle
----------+-------------+-----------+------------+-----------+---------
 appdb    | app_readwrite |         0 |          0 |         0 |       1
```

```bash
exit
```

---

## 6. Set Up Automatic Failover with repmgr

### 6.1 Install repmgr on both servers

Run as root on **both** servers:

```bash
dnf install -y repmgr_16
```

### 6.2 Create the repmgr database and user

On the **primary**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "CREATE ROLE repmgr WITH LOGIN SUPERUSER PASSWORD 'R3pmgr_2026';"
```

```bash
/usr/pgsql-16/bin/psql -c "CREATE DATABASE repmgr OWNER repmgr;"
```

```bash
exit
```

### 6.3 Update pg_hba.conf for repmgr

On the **primary** as root:

```bash
su - postgres
```

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Add these lines before the `hostnossl reject` line:

```
# repmgr connections
hostssl repmgr          repmgr          0.0.0.0/0               scram-sha-256
hostssl replication     repmgr          0.0.0.0/0               scram-sha-256
```

Save and exit (`:wq`).

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_reload_conf();"
```

```bash
exit
```

### 6.4 Configure repmgr on the primary

On the **primary** as root:

```bash
vi /etc/repmgr/16/repmgr.conf
```

Add:

```
node_id=1
node_name='pg-prod-primary'
conninfo='host=pg-prod-primary user=repmgr dbname=repmgr connect_timeout=5'
data_directory='/opt/pgsql/data'

failover='automatic'
promote_command='/usr/pgsql-16/bin/repmgr standby promote -f /etc/repmgr/16/repmgr.conf --log-to-file'
follow_command='/usr/pgsql-16/bin/repmgr standby follow -f /etc/repmgr/16/repmgr.conf --log-to-file --upstream-node-id=%n'

reconnect_attempts=6
reconnect_interval=10

monitoring_history=yes
monitor_interval_secs=5

log_level=INFO
log_file='/var/log/repmgr/repmgr.log'
log_status_interval=60
```

Save and exit (`:wq`).

```bash
mkdir -p /var/log/repmgr
```

```bash
chown postgres:postgres /var/log/repmgr
```

### 6.5 Register the primary

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf primary register
```

Expected output:
```
INFO: connecting to primary database...
NOTICE: attempting to install extension "repmgr"
NOTICE: "repmgr" extension successfully installed
NOTICE: primary node record (ID: 1) registered
```

```bash
exit
```

### 6.6 Configure repmgr on the standby

On the **standby** as root:

```bash
vi /etc/repmgr/16/repmgr.conf
```

Add:

```
node_id=2
node_name='pg-prod-standby'
conninfo='host=pg-prod-standby user=repmgr dbname=repmgr connect_timeout=5'
data_directory='/opt/pgsql/data'

failover='automatic'
promote_command='/usr/pgsql-16/bin/repmgr standby promote -f /etc/repmgr/16/repmgr.conf --log-to-file'
follow_command='/usr/pgsql-16/bin/repmgr standby follow -f /etc/repmgr/16/repmgr.conf --log-to-file --upstream-node-id=%n'

reconnect_attempts=6
reconnect_interval=10

monitoring_history=yes
monitor_interval_secs=5

log_level=INFO
log_file='/var/log/repmgr/repmgr.log'
log_status_interval=60
```

Save and exit (`:wq`).

```bash
mkdir -p /var/log/repmgr
```

```bash
chown postgres:postgres /var/log/repmgr
```

### 6.7 Register the standby

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register
```

Expected output:
```
INFO: connecting to local node "pg-prod-standby" (ID: 2)
INFO: connecting to primary database...
NOTICE: standby node "pg-prod-standby" (ID: 2) successfully registered
```

### 6.8 Verify cluster status

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output:
```
 ID | Name             | Role    | Status    | Upstream          | Location | ...
----+------------------+---------+-----------+-------------------+----------+
 1  | pg-prod-primary  | primary | * running |                   | default  |
 2  | pg-prod-standby  | standby |   running | pg-prod-primary   | default  |
```

```bash
exit
```

### 6.9 Start repmgrd daemon

On **both** servers as root:

```bash
vi /etc/systemd/system/repmgrd.service
```

Add:

```ini
[Unit]
Description=repmgr daemon
After=postgresql-16.service
Requires=postgresql-16.service

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/pgsql-16/bin/repmgrd -f /etc/repmgr/16/repmgr.conf --pid-file=/var/run/repmgr/repmgrd.pid
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/repmgr/repmgrd.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Save and exit (`:wq`).

```bash
mkdir -p /var/run/repmgr
```

```bash
chown postgres:postgres /var/run/repmgr
```

```bash
systemctl daemon-reload
```

```bash
systemctl enable repmgrd
```

```bash
systemctl start repmgrd
```

```bash
systemctl status repmgrd
```

Expected output (yours will differ):
```
 repmgrd.service - repmgr daemon
     Active: active (running) ...
```

---

## 7. Test Failover

### 7.1 Verify repmgrd is monitoring

On either server:

```bash
su - postgres
```

```bash
tail -5 /var/log/repmgr/repmgr.log
```

Expected output (yours will differ):
```
[INFO] monitoring primary node "pg-prod-primary" (ID: 1) in normal state
```

```bash
exit
```

### 7.2 Simulate primary failure

On the **primary** as root:

```bash
systemctl stop postgresql-16
```

This simulates a primary crash. Do NOT stop repmgrd - it will detect the failure.

### 7.3 Watch the failover

On the **standby**:

```bash
su - postgres
```

```bash
tail -f /var/log/repmgr/repmgr.log
```

Watch for messages like:

```
[WARNING] unable to ping "host=pg-prod-primary user=repmgr dbname=repmgr"
[NOTICE] this node is the winner, will now promote self
[NOTICE] STANDBY PROMOTE successful
```

Press Ctrl+C when you see the promotion message.

### 7.4 Verify the new primary

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output:
```
 ID | Name             | Role    | Status    | ...
----+------------------+---------+-----------+
 1  | pg-prod-primary  | primary | - failed  |
 2  | pg-prod-standby  | primary | * running |
```

### 7.5 Test writes on the new primary

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('failover-test@example.com', 'Failover Test');"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.customers;"
```

```bash
exit
```

### 7.6 Rejoin the old primary as a standby

Start PostgreSQL on the old primary:

```bash
systemctl start postgresql-16
```

On the **old primary**, rejoin as a standby:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin -d 'host=pg-prod-standby user=repmgr dbname=repmgr' --force-rewind=/usr/pgsql-16/bin/pg_rewind
```

- `node rejoin` - Reattaches a failed node to the cluster.
- `--force-rewind` - Uses pg_rewind to resynchronize the data directory instead of doing a full base backup.

Expected output (yours will differ):
```
NOTICE: pg_rewind: servers diverged at WAL location ...
NOTICE: NODE REJOIN successful
```

### 7.7 Verify the cluster is healthy again

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output:
```
 ID | Name             | Role    | Status    | Upstream          |
----+------------------+---------+-----------+-------------------+
 1  | pg-prod-primary  | standby |   running | pg-prod-standby   |
 2  | pg-prod-standby  | primary | * running |                   |
```

Both nodes are running. The old primary is now a standby.

```bash
exit
```

---

## Summary

You now have a complete HA setup:

- Streaming replication with synchronous commit (zero data loss)
- pgBouncer connection pooling (1000 clients into 150 server connections)
- repmgr automatic failover (60-90 second detection + promotion)
- Tested failover and rejoin

Next: [Build 03 - Backup Strategy](03-backup-strategy.md)
