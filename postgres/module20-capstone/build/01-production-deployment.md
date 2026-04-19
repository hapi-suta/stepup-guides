# Build 01: Production PostgreSQL 16 Deployment

Deploy a production-grade PostgreSQL 16 instance from scratch. This guide covers OS hardening, filesystem layout, installation, configuration, SSL, roles, schema migration, and logging.

Run all steps on your **primary server** unless noted otherwise.

---

## Prerequisites

- CentOS Stream 9 server with root access
- Minimum 4 GB RAM, 2 vCPUs, 50 GB disk
- A separate data volume mounted at /opt/pgsql (preferred)
- SSH access configured

---

## 1. OS Hardening

### 1.1 Update all packages

```bash
dnf update -y
```

This pulls the latest security patches and bug fixes for all installed packages. The `-y` flag auto-confirms the update.

Expected output (yours will differ):
```
Last metadata expiration check: 0:02:15 ago
Dependencies resolved.
...
Complete!
```

### 1.2 Set the hostname

```bash
hostnamectl set-hostname pg-prod-primary
```

This sets a meaningful hostname. You will see it in logs, monitoring dashboards, and replication views.

### 1.3 Configure the timezone

```bash
timedatectl set-timezone UTC
```

Production databases should always run in UTC. This avoids timezone confusion in logs and timestamps.

Verify:

```bash
timedatectl
```

Expected output (yours will differ):
```
               Local time: Sat 2026-04-19 12:00:00 UTC
           Universal time: Sat 2026-04-19 12:00:00 UTC
                 Time zone: UTC (UTC, +0000)
...
```

### 1.4 Disable SELinux (lab only)

In production, you would configure SELinux policies for PostgreSQL. For this lab, we disable it to avoid interference.

```bash
setenforce 0
```

```bash
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

The first command disables SELinux immediately. The second makes it persist across reboots.

### 1.5 Configure the firewall

```bash
firewall-cmd --permanent --add-port=5432/tcp
```

This opens the PostgreSQL port (5432) in the firewall. The `--permanent` flag ensures it survives reboots.

```bash
firewall-cmd --permanent --add-port=22/tcp
```

Keep SSH open so you can connect to the server.

```bash
firewall-cmd --reload
```

Apply the firewall changes without restarting the service.

```bash
firewall-cmd --list-all
```

Expected output (yours will differ):
```
public (active)
  target: default
  ports: 5432/tcp 22/tcp
  ...
```

### 1.6 Configure sysctl for PostgreSQL

```bash
vi /etc/sysctl.d/99-postgresql.conf
```

Add these lines:

```
vm.swappiness = 1
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
net.core.somaxconn = 4096
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 10
```

Save and exit (`:wq`).

- `vm.swappiness = 1` - Tells the kernel to avoid swapping unless absolutely necessary. Swap kills database performance.
- `vm.overcommit_memory = 2` - Prevents the kernel from overcommitting memory. PostgreSQL needs reliable memory allocation.
- `vm.overcommit_ratio = 80` - With overcommit mode 2, the kernel only commits 80% of physical RAM plus swap.
- `vm.dirty_background_ratio = 3` - Start flushing dirty pages to disk when 3% of memory is dirty. Keeps write-behind steady.
- `vm.dirty_ratio = 10` - Force synchronous writes when 10% of memory is dirty. Prevents massive write bursts.
- `net.core.somaxconn = 4096` - Increases the socket backlog for incoming connections.
- TCP keepalive settings detect dead connections faster than the default (7200 seconds).

Apply immediately:

```bash
sysctl --system
```

Expected output (yours will differ):
```
* Applying /etc/sysctl.d/99-postgresql.conf ...
vm.swappiness = 1
vm.overcommit_memory = 2
...
```

### 1.7 Disable Transparent Huge Pages

THP causes latency spikes in database workloads. Disable it.

```bash
vi /etc/systemd/system/disable-thp.service
```

Add:

```ini
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
```

Save and exit (`:wq`).

```bash
systemctl daemon-reload
```

```bash
systemctl enable --now disable-thp.service
```

Verify:

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

Expected output:
```
always madvise [never]
```

The `[never]` in brackets means THP is disabled.

---

## 2. Filesystem Layout

### 2.1 Create the directory structure

```bash
mkdir -p /opt/pgsql/data
```

```bash
mkdir -p /opt/pgsql/wal
```

```bash
mkdir -p /opt/pgsql/log
```

```bash
mkdir -p /opt/pgsql/backup
```

```bash
mkdir -p /opt/pgsql/tblspc
```

```bash
mkdir -p /opt/pgsql/scripts
```

Each directory has a purpose:
- `data` - PostgreSQL data directory (PGDATA)
- `wal` - Write-Ahead Log files, ideally on separate disk for performance
- `log` - PostgreSQL server logs
- `backup` - Local backup storage
- `tblspc` - Tablespace storage
- `scripts` - Maintenance scripts

> **Concept - Separate WAL from data**: WAL writes are sequential. Data writes are random. Putting them on the same disk means they compete for I/O. Separating them improves both write throughput and recovery speed.

### 2.2 Create the postgres OS user

```bash
useradd -m -d /home/postgres -s /bin/bash postgres
```

This creates the `postgres` system user. The `-m` flag creates a home directory. The `-s` flag sets bash as the default shell.

### 2.3 Set ownership

```bash
chown -R postgres:postgres /opt/pgsql
```

PostgreSQL requires that the data directory and all its contents are owned by the postgres user.

```bash
chmod 700 /opt/pgsql/data
```

The data directory must have permissions 700 (owner only). PostgreSQL refuses to start if the permissions are too open.

---

## 3. Install PostgreSQL 16

### 3.1 Add the PGDG repository

```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

This installs the official PostgreSQL Global Development Group (PGDG) repository. It contains the latest PostgreSQL packages built for your OS version.

### 3.2 Disable the built-in PostgreSQL module

```bash
dnf -qy module disable postgresql
```

CentOS Stream 9 ships with an older PostgreSQL in its AppStream module. Disabling it ensures `dnf` installs from PGDG instead.

### 3.3 Install PostgreSQL 16

```bash
dnf install -y postgresql16-server postgresql16-contrib
```

- `postgresql16-server` - The core database server, initdb, pg_ctl, and utilities.
- `postgresql16-contrib` - Extra modules like pg_stat_statements, pgcrypto, pg_trgm, and others you will need in production.

Expected output (yours will differ):
```
...
Installed:
  postgresql16-server-16.x-...
  postgresql16-contrib-16.x-...
Complete!
```

### 3.4 Verify the installation

```bash
/usr/pgsql-16/bin/postgres --version
```

Expected output:
```
postgres (PostgreSQL) 16.x
```

---

## 4. Initialize the Cluster

### 4.1 Initialize with checksums

Switch to the postgres user first:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data --data-checksums --waldir=/opt/pgsql/wal --encoding=UTF8 --locale=en_US.UTF-8
```

- `-D /opt/pgsql/data` - Sets the data directory location.
- `--data-checksums` - Enables page-level checksums. This detects silent data corruption.
- `--waldir=/opt/pgsql/wal` - Stores WAL files on a separate path (ideally a separate disk).
- `--encoding=UTF8` - Sets the default database encoding.
- `--locale=en_US.UTF-8` - Sets the collation locale.

Expected output (yours will differ):
```
The files belonging to this database system will be owned by user "postgres".
...
Data page checksums are enabled.
...
Success. You can now start the database server using:
    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data -l logfile start
```

> **Concept - Data checksums**: Without checksums, PostgreSQL cannot tell if a disk returned corrupted data. Checksums add about 1-2% overhead but let you detect corruption before it propagates to backups. Always enable them in production.

```bash
exit
```

Return to root for the next steps.

---

## 5. Configure PostgreSQL for Production

### 5.1 Edit postgresql.conf

Switch to postgres:

```bash
su - postgres
```

```bash
vi /opt/pgsql/data/postgresql.conf
```

Find and update these settings (or add them at the end of the file):

```
# Connection Settings
listen_addresses = '*'
port = 5432
max_connections = 200

# Memory
shared_buffers = '1GB'
effective_cache_size = '3GB'
work_mem = '16MB'
maintenance_work_mem = '256MB'
huge_pages = 'try'

# WAL Settings
wal_level = 'replica'
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = '2GB'
wal_compression = 'zstd'
archive_mode = on
archive_command = '/bin/true'

# Checkpoints
checkpoint_timeout = '15min'
checkpoint_completion_target = 0.9
max_wal_size = '4GB'
min_wal_size = '1GB'

# Logging
logging_collector = on
log_directory = '/opt/pgsql/log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = '1d'
log_rotation_size = 0
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_statement = 'ddl'

# Autovacuum
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = '30s'
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.02

# Query Planner
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 200

# Background Writer
bgwriter_delay = '200ms'
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0

# Extensions
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
pg_stat_statements.track = 'all'
```

Save and exit (`:wq`).

Key tuning explanations:
- `shared_buffers = '1GB'` - About 25% of RAM. This is PostgreSQL's main cache.
- `effective_cache_size = '3GB'` - About 75% of RAM. Tells the planner how much cache the OS provides.
- `work_mem = '16MB'` - Memory per sort/hash operation. Be careful - each query can use multiple work_mem allocations.
- `wal_level = 'replica'` - Required for streaming replication and PITR.
- `wal_compression = 'zstd'` - Compresses WAL records. Reduces I/O and storage.
- `log_min_duration_statement = 1000` - Logs any query taking more than 1 second. Essential for finding slow queries.
- `autovacuum_vacuum_scale_factor = 0.05` - Trigger vacuum when 5% of rows are dead (default is 20%, too lazy for production).
- `random_page_cost = 1.1` - Assume SSD storage. Default 4.0 is for spinning disks and makes the planner avoid indexes.

```bash
exit
```

---

## 6. Configure SSL

### 6.1 Generate a self-signed certificate

Run as root:

```bash
mkdir -p /opt/pgsql/ssl
```

```bash
openssl req -new -x509 -days 3650 -nodes -text -out /opt/pgsql/ssl/server.crt -keyout /opt/pgsql/ssl/server.key -subj "/CN=pg-prod-primary"
```

This creates a self-signed certificate valid for 10 years. The `-nodes` flag means no passphrase on the key (required for PostgreSQL to start unattended). In production, use certificates from your internal CA or a public CA.

```bash
chown postgres:postgres /opt/pgsql/ssl/server.crt
```

```bash
chown postgres:postgres /opt/pgsql/ssl/server.key
```

```bash
chmod 600 /opt/pgsql/ssl/server.key
```

The private key must be readable only by the postgres user.

### 6.2 Enable SSL in postgresql.conf

```bash
su - postgres
```

```bash
vi /opt/pgsql/data/postgresql.conf
```

Add these lines:

```
ssl = on
ssl_cert_file = '/opt/pgsql/ssl/server.crt'
ssl_key_file = '/opt/pgsql/ssl/server.key'
ssl_min_protocol_version = 'TLSv1.2'
```

Save and exit (`:wq`).

```bash
exit
```

---

## 7. Configure pg_hba.conf

### 7.1 Set up authentication rules

```bash
su - postgres
```

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Replace the entire contents with:

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections - trust for postgres (OS-level auth via su)
local   all             postgres                                peer

# Local connections - password for app users
local   all             all                                     scram-sha-256

# SSL-only remote connections
hostssl all             all             0.0.0.0/0               scram-sha-256

# Replication - SSL required
hostssl replication     replicator      0.0.0.0/0               scram-sha-256

# Reject all non-SSL remote connections
hostnossl all           all             0.0.0.0/0               reject
```

Save and exit (`:wq`).

Key decisions:
- `peer` for local postgres - You authenticate by being the `postgres` OS user. No password needed.
- `scram-sha-256` everywhere else - The strongest built-in password hashing. Never use `md5` or `trust` for remote connections.
- `hostssl` for remote - Forces all remote clients to use SSL encryption.
- `hostnossl ... reject` - Explicitly denies any unencrypted remote connection.
- Replication uses a dedicated `replicator` user with SSL required.

> **Concept - Defense in depth**: The `hostnossl reject` rule is not strictly necessary (since we only have `hostssl` rules above it). But it makes the intent explicit: unencrypted connections are forbidden. When a new DBA reads this file at 3 AM, clarity matters.

```bash
exit
```

---

## 8. Create the systemd Service

### 8.1 Create the service file

Run as root:

```bash
vi /etc/systemd/system/postgresql-16.service
```

Add:

```ini
[Unit]
Description=PostgreSQL 16 Production
After=syslog.target network-online.target
Wants=network-online.target

[Service]
Type=notify
User=postgres
Group=postgres

Environment=PGDATA=/opt/pgsql/data

OOMScoreAdjust=-1000

ExecStart=/usr/pgsql-16/bin/postgres -D /opt/pgsql/data
ExecReload=/bin/kill -HUP $MAINPID

TimeoutSec=300

Restart=on-failure
RestartSec=5

LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
```

Save and exit (`:wq`).

- `OOMScoreAdjust=-1000` - Tells the kernel to never kill PostgreSQL when memory is low. Kill other processes first.
- `Type=notify` - PostgreSQL sends a readiness notification to systemd when it is ready to accept connections.
- `Restart=on-failure` - Automatically restart if PostgreSQL crashes.
- `LimitNOFILE=65536` - Raise the file descriptor limit. Default 1024 is too low for production.

### 8.2 Enable and start

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
     Loaded: loaded (/etc/systemd/system/postgresql-16.service; enabled)
     Active: active (running) since ...
   Main PID: 12345 (postgres)
...
```

---

## 9. Create Roles and the Application Database

### 9.1 Connect as postgres

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql
```

### 9.2 Create the replicator role

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'R3pl!cat0r_2026';
```

This role is used by standby servers to connect for streaming replication. The `REPLICATION` attribute is required.

### 9.3 Create application roles

```sql
CREATE ROLE app_owner WITH LOGIN PASSWORD 'App0wn3r_2026' CREATEDB;
```

The `app_owner` role owns the application database and schema. It can create databases but is not a superuser.

```sql
CREATE ROLE app_readwrite WITH LOGIN PASSWORD 'AppRW_2026';
```

The application service connects with this role. It gets only the permissions it needs.

```sql
CREATE ROLE app_readonly WITH LOGIN PASSWORD 'AppRO_2026';
```

The read-only role is for reporting tools, dashboards, and analysts.

### 9.4 Create the application database

```sql
CREATE DATABASE appdb OWNER app_owner ENCODING 'UTF8' LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';
```

### 9.5 Connect to the application database

```sql
\c appdb
```

### 9.6 Create schemas

```sql
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION app_owner;
```

```sql
CREATE SCHEMA IF NOT EXISTS audit AUTHORIZATION app_owner;
```

- `app` - All application tables live here.
- `audit` - Audit trail tables live here, separated for access control.

### 9.7 Set the default search path

```sql
ALTER DATABASE appdb SET search_path TO app, public;
```

This means queries in `appdb` search the `app` schema first, then `public`. No need to prefix table names with `app.`.

### 9.8 Grant permissions

```sql
GRANT CONNECT ON DATABASE appdb TO app_readwrite;
```

```sql
GRANT CONNECT ON DATABASE appdb TO app_readonly;
```

```sql
GRANT USAGE ON SCHEMA app TO app_readwrite;
```

```sql
GRANT USAGE ON SCHEMA app TO app_readonly;
```

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;
```

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app GRANT SELECT ON TABLES TO app_readonly;
```

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app GRANT USAGE, SELECT ON SEQUENCES TO app_readwrite;
```

- `ALTER DEFAULT PRIVILEGES` - Automatically grants permissions on future tables that `app_owner` creates. Without this, you would need to run GRANT after every CREATE TABLE.

### 9.9 Enable extensions

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

- `pg_stat_statements` - Tracks query statistics. Essential for performance tuning.
- `pgcrypto` - Cryptographic functions for hashing and encryption.
- `pg_trgm` - Trigram matching for fuzzy text search.

---

## 10. Initial Schema Migration

### 10.1 Create application tables

Still connected to `appdb` as postgres, switch to app_owner:

```sql
SET ROLE app_owner;
```

```sql
CREATE TABLE app.customers (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    external_id     uuid NOT NULL DEFAULT gen_random_uuid(),
    email           text NOT NULL,
    full_name       text NOT NULL,
    status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
```

```sql
CREATE UNIQUE INDEX idx_customers_email ON app.customers (lower(email));
```

```sql
CREATE UNIQUE INDEX idx_customers_external_id ON app.customers (external_id);
```

```sql
CREATE TABLE app.orders (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id     bigint NOT NULL REFERENCES app.customers(id),
    order_number    text NOT NULL,
    status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
    total_cents     bigint NOT NULL CHECK (total_cents >= 0),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
```

```sql
CREATE UNIQUE INDEX idx_orders_order_number ON app.orders (order_number);
```

```sql
CREATE INDEX idx_orders_customer_id ON app.orders (customer_id);
```

```sql
CREATE INDEX idx_orders_status ON app.orders (status) WHERE status NOT IN ('delivered', 'cancelled');
```

The partial index on `status` only indexes active orders. Delivered and cancelled orders rarely need lookup by status.

```sql
CREATE TABLE app.order_items (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id        bigint NOT NULL REFERENCES app.orders(id),
    product_name    text NOT NULL,
    quantity        int NOT NULL CHECK (quantity > 0),
    unit_price_cents bigint NOT NULL CHECK (unit_price_cents >= 0),
    created_at      timestamptz NOT NULL DEFAULT now()
);
```

```sql
CREATE INDEX idx_order_items_order_id ON app.order_items (order_id);
```

### 10.2 Create the audit table

```sql
CREATE TABLE audit.activity_log (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name      text NOT NULL,
    operation       text NOT NULL,
    row_id          bigint,
    old_data        jsonb,
    new_data        jsonb,
    changed_by      text NOT NULL DEFAULT current_user,
    changed_at      timestamptz NOT NULL DEFAULT now()
);
```

```sql
CREATE INDEX idx_activity_log_table_op ON audit.activity_log (table_name, operation);
```

```sql
CREATE INDEX idx_activity_log_changed_at ON audit.activity_log (changed_at);
```

### 10.3 Create an audit trigger function

```sql
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.activity_log (table_name, operation, row_id, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.activity_log (table_name, operation, row_id, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.activity_log (table_name, operation, row_id, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.id, to_jsonb(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

### 10.4 Attach triggers

```sql
CREATE TRIGGER trg_customers_audit
    AFTER INSERT OR UPDATE OR DELETE ON app.customers
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();
```

```sql
CREATE TRIGGER trg_orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON app.orders
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();
```

### 10.5 Load sample data

```sql
INSERT INTO app.customers (email, full_name)
SELECT
    'user' || n || '@example.com',
    'Test User ' || n
FROM generate_series(1, 1000) AS n;
```

```sql
INSERT INTO app.orders (customer_id, order_number, status, total_cents)
SELECT
    (random() * 999 + 1)::bigint,
    'ORD-' || lpad(n::text, 8, '0'),
    (ARRAY['pending', 'confirmed', 'shipped', 'delivered'])[floor(random() * 4 + 1)::int],
    (random() * 50000 + 500)::bigint
FROM generate_series(1, 10000) AS n;
```

```sql
INSERT INTO app.order_items (order_id, product_name, quantity, unit_price_cents)
SELECT
    (random() * 9999 + 1)::bigint,
    'Product ' || (random() * 100 + 1)::int,
    (random() * 5 + 1)::int,
    (random() * 10000 + 100)::bigint
FROM generate_series(1, 30000);
```

### 10.6 Verify the data

```sql
SELECT 'customers' AS tbl, count(*) FROM app.customers
UNION ALL
SELECT 'orders', count(*) FROM app.orders
UNION ALL
SELECT 'order_items', count(*) FROM app.order_items
UNION ALL
SELECT 'audit_log', count(*) FROM audit.activity_log;
```

Expected output (yours will differ):
```
     tbl      | count
--------------+-------
 customers    |  1000
 orders       | 10000
 order_items  | 30000
 audit_log    | 11000
```

### 10.7 Reset role and exit

```sql
RESET ROLE;
```

```sql
\q
```

```bash
exit
```

---

## 11. Configure Log Rotation

### 11.1 Create a logrotate configuration

Run as root:

```bash
vi /etc/logrotate.d/postgresql-16
```

Add:

```
/opt/pgsql/log/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su postgres postgres
}
```

Save and exit (`:wq`).

- `daily` - Rotate logs every day.
- `rotate 30` - Keep 30 days of logs.
- `compress` - Gzip old logs to save space.
- `delaycompress` - Don't compress yesterday's log yet (in case something is still writing to it).
- `copytruncate` - Copy the log and truncate the original. This avoids needing to signal PostgreSQL.
- `su postgres postgres` - Run the rotation as the postgres user since the logs are owned by postgres.

---

## 12. Verify the Production Setup

### 12.1 Check PostgreSQL is running

```bash
systemctl status postgresql-16
```

### 12.2 Test SSL connection

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql "host=localhost dbname=appdb user=app_readwrite sslmode=require" -c "SELECT ssl_is_used();"
```

Expected output:
```
 ssl_is_used
-------------
 t
```

The `t` means SSL is active on this connection.

### 12.3 Test that non-SSL is rejected

```bash
/usr/pgsql-16/bin/psql "host=localhost dbname=appdb user=app_readwrite sslmode=disable" -c "SELECT 1;"
```

Expected output:
```
psql: error: connection to server at "localhost" (127.0.0.1), port 5432 failed: FATAL:  pg_hba.conf rejects connections for host "127.0.0.1", user "app_readwrite", database "appdb", no encryption
```

This confirms that `hostnossl reject` rule is working.

### 12.4 Check pg_stat_statements is loaded

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM pg_stat_statements;"
```

Expected output (yours will differ):
```
 count
-------
    42
```

Any number greater than 0 means the extension is collecting query statistics.

### 12.5 Check data checksums

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep checksum
```

Expected output:
```
Data page checksum version:           1
```

Version 1 means checksums are enabled.

### 12.6 Check logging works

```bash
ls -la /opt/pgsql/log/
```

Expected output (yours will differ):
```
-rw------- 1 postgres postgres 12345 Apr 19 12:00 postgresql-2026-04-19.log
```

```bash
exit
```

---

## Summary

You now have a production-grade PostgreSQL 16 deployment with:

- OS hardened (sysctl, THP disabled, firewall configured)
- Separate filesystem layout (data, WAL, log, backup)
- Data checksums enabled
- SSL enforced for all remote connections
- scram-sha-256 authentication everywhere
- Application database with proper schema separation
- Role-based access (owner, readwrite, readonly)
- Audit trail on all data changes
- pg_stat_statements for query monitoring
- Production-tuned configuration
- Log rotation configured

Next: [Build 02 - Replication and HA](02-replication-and-ha.md)
