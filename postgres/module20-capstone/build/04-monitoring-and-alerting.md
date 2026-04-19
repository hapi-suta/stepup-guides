# Build 04: Monitoring and Alerting

Install postgres_exporter and Prometheus for metrics collection, import Grafana dashboards, and configure alerting rules for critical PostgreSQL conditions. Each alert gets an on-call runbook.

Run all steps on the **primary** server unless noted otherwise.

---

## Prerequisites

- Completed Build 01-03
- PostgreSQL 16 running with pg_stat_statements enabled
- Replication configured (Build 02)
- Backups configured (Build 03)

---

## 1. Install postgres_exporter

### 1.1 Download postgres_exporter

Run as root:

```bash
curl -LO https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz
```

This downloads the Prometheus exporter for PostgreSQL. It exposes PostgreSQL metrics as a Prometheus endpoint.

```bash
tar xzf postgres_exporter-0.15.0.linux-amd64.tar.gz
```

```bash
cp postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/local/bin/
```

```bash
chmod 755 /usr/local/bin/postgres_exporter
```

### 1.2 Create a monitoring role in PostgreSQL

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "CREATE ROLE monitoring WITH LOGIN PASSWORD 'M0n!tor_2026';"
```

```bash
/usr/pgsql-16/bin/psql -c "GRANT pg_monitor TO monitoring;"
```

The `pg_monitor` role is a built-in PostgreSQL role that grants read access to all monitoring views and functions. This is safer than giving superuser access.

```bash
/usr/pgsql-16/bin/psql -c "GRANT CONNECT ON DATABASE appdb TO monitoring;"
```

```bash
exit
```

### 1.3 Create the environment file

```bash
vi /etc/default/postgres_exporter
```

Add:

```
DATA_SOURCE_NAME=postgresql://monitoring:M0n!tor_2026@localhost:5432/appdb?sslmode=require
```

Save and exit (`:wq`).

```bash
chmod 600 /etc/default/postgres_exporter
```

### 1.4 Create a custom queries file

```bash
vi /etc/postgres_exporter_queries.yaml
```

Add:

```yaml
pg_replication_lag:
  query: |
    SELECT
      CASE
        WHEN pg_is_in_recovery() THEN
          EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))
        ELSE 0
      END AS lag_seconds
  master: true
  metrics:
    - lag_seconds:
        usage: "GAUGE"
        description: "Replication lag in seconds"

pg_database_size:
  query: |
    SELECT datname, pg_database_size(datname) AS size_bytes
    FROM pg_database
    WHERE datname NOT IN ('template0', 'template1')
  master: true
  metrics:
    - datname:
        usage: "LABEL"
        description: "Database name"
    - size_bytes:
        usage: "GAUGE"
        description: "Database size in bytes"

pg_dead_tuples_ratio:
  query: |
    SELECT
      schemaname,
      relname,
      CASE WHEN n_live_tup > 0
        THEN n_dead_tup::float / n_live_tup::float * 100
        ELSE 0
      END AS dead_ratio
    FROM pg_stat_user_tables
    WHERE n_live_tup > 1000
    ORDER BY dead_ratio DESC
    LIMIT 20
  master: true
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - relname:
        usage: "LABEL"
        description: "Table name"
    - dead_ratio:
        usage: "GAUGE"
        description: "Dead tuple ratio percentage"

pg_connection_usage:
  query: |
    SELECT
      count(*) AS current_connections,
      (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections,
      count(*)::float / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections')::float * 100 AS usage_percent
    FROM pg_stat_activity
  master: true
  metrics:
    - current_connections:
        usage: "GAUGE"
        description: "Current number of connections"
    - max_connections:
        usage: "GAUGE"
        description: "Maximum allowed connections"
    - usage_percent:
        usage: "GAUGE"
        description: "Connection usage percentage"

pg_backup_age:
  query: |
    SELECT
      EXTRACT(EPOCH FROM (now() - pg_stat_get_activity(pid).backend_start))::int AS backup_age_seconds
    FROM pg_stat_activity
    WHERE backend_type = 'walsender' AND state = 'streaming'
    LIMIT 1
  master: true
  metrics:
    - backup_age_seconds:
        usage: "GAUGE"
        description: "Age of oldest backup in seconds"

pg_disk_usage:
  query: |
    SELECT
      spcname,
      pg_tablespace_size(oid) AS size_bytes
    FROM pg_tablespace
  master: true
  metrics:
    - spcname:
        usage: "LABEL"
        description: "Tablespace name"
    - size_bytes:
        usage: "GAUGE"
        description: "Tablespace size in bytes"
```

Save and exit (`:wq`).

### 1.5 Create the systemd service

```bash
vi /etc/systemd/system/postgres_exporter.service
```

Add:

```ini
[Unit]
Description=Prometheus PostgreSQL Exporter
After=postgresql-16.service
Wants=postgresql-16.service

[Service]
Type=simple
User=nobody
Group=nobody
EnvironmentFile=/etc/default/postgres_exporter
ExecStart=/usr/local/bin/postgres_exporter \
    --extend.query-path=/etc/postgres_exporter_queries.yaml \
    --web.listen-address=:9187 \
    --collector.process_idle \
    --collector.postmaster
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Save and exit (`:wq`).

- `--extend.query-path` - Load custom queries for additional metrics.
- `--web.listen-address=:9187` - The default Prometheus scrape port for postgres_exporter.
- `--collector.process_idle` - Export per-process idle time metrics.

### 1.6 Start postgres_exporter

```bash
systemctl daemon-reload
```

```bash
systemctl enable postgres_exporter
```

```bash
systemctl start postgres_exporter
```

### 1.7 Verify metrics are being exported

```bash
curl -s http://localhost:9187/metrics | head -20
```

Expected output (yours will differ):
```
# HELP pg_exporter_last_scrape_duration_seconds Duration of the last scrape of metrics from PostgreSQL.
# TYPE pg_exporter_last_scrape_duration_seconds gauge
pg_exporter_last_scrape_duration_seconds 0.023
# HELP pg_up Whether the PostgreSQL server is up.
# TYPE pg_up gauge
pg_up 1
...
```

The `pg_up 1` line confirms the exporter is connected to PostgreSQL.

### 1.8 Open the firewall

```bash
firewall-cmd --permanent --add-port=9187/tcp
```

```bash
firewall-cmd --reload
```

---

## 2. Install Prometheus

### 2.1 Download Prometheus

```bash
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz
```

```bash
tar xzf prometheus-2.51.0.linux-amd64.tar.gz
```

```bash
mkdir -p /opt/prometheus
```

```bash
cp prometheus-2.51.0.linux-amd64/prometheus /opt/prometheus/
```

```bash
cp prometheus-2.51.0.linux-amd64/promtool /opt/prometheus/
```

### 2.2 Create the Prometheus user

```bash
useradd -r -s /sbin/nologin prometheus
```

```bash
mkdir -p /opt/prometheus/data
```

```bash
chown -R prometheus:prometheus /opt/prometheus
```

### 2.3 Configure Prometheus

```bash
vi /opt/prometheus/prometheus.yml
```

Add:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']
        labels:
          instance: 'pg-prod-primary'
          role: 'primary'

  - job_name: 'postgresql-standby'
    static_configs:
      - targets: ['[STANDBY_IP]:9187']
        labels:
          instance: 'pg-prod-standby'
          role: 'standby'

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100', '[STANDBY_IP]:9100']
```

Save and exit (`:wq`).

Replace `[STANDBY_IP]` with your standby server's IP address.

- `scrape_interval: 15s` - Prometheus collects metrics every 15 seconds.
- `evaluation_interval: 15s` - Alert rules are evaluated every 15 seconds.
- The `labels` section adds metadata to each target so you can filter by role in dashboards.

### 2.4 Create alerting rules

```bash
vi /opt/prometheus/alerts.yml
```

Add:

```yaml
groups:
  - name: postgresql_alerts
    rules:

      - alert: PostgresqlDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down on {{ $labels.instance }}"
          description: "PostgreSQL has been unreachable for more than 1 minute."
          runbook: "Check systemctl status postgresql-16. Check /opt/pgsql/log/ for errors. Try systemctl restart postgresql-16."

      - alert: ReplicationLagHigh
        expr: pg_replication_lag_lag_seconds > 30
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag > 30s on {{ $labels.instance }}"
          description: "Replication lag is {{ $value }} seconds."
          runbook: "Check network between primary and standby. Check pg_stat_replication on primary. Check standby log for replay errors."

      - alert: ConnectionUsageHigh
        expr: pg_connection_usage_usage_percent > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Connection usage > 80% on {{ $labels.instance }}"
          description: "{{ $value }}% of max_connections are in use."
          runbook: "Check pg_stat_activity for idle connections. Check application connection pool settings. Consider pgBouncer if not using one."

      - alert: DeadTupleRatioHigh
        expr: pg_dead_tuples_ratio_dead_ratio > 20
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Dead tuple ratio > 20% on {{ $labels.instance }} table {{ $labels.relname }}"
          description: "Table {{ $labels.relname }} has {{ $value }}% dead tuples."
          runbook: "Check if autovacuum is running on this table. Run VACUUM ANALYZE manually if needed. Check autovacuum_vacuum_scale_factor settings."

      - alert: DiskUsageHigh
        expr: (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"} * 100 > 85
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk usage > 85% on {{ $labels.instance }}"
          description: "Root filesystem is {{ $value }}% full."
          runbook: "Check du -sh /opt/pgsql/*. Remove old WAL files if safe. Remove old pg_log files. Check backup retention. Consider expanding the volume."

      - alert: ReplicationSlotInactive
        expr: pg_replication_slots_active == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Inactive replication slot on {{ $labels.instance }}"
          description: "Slot {{ $labels.slot_name }} is inactive. WAL is accumulating."
          runbook: "Check if the standby is running. If the standby is permanently gone, drop the slot with pg_drop_replication_slot(). Inactive slots prevent WAL cleanup and will fill the disk."

      - alert: LongRunningTransaction
        expr: pg_stat_activity_max_tx_duration{datname!~"template.*"} > 600
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Transaction running > 10 minutes on {{ $labels.instance }}"
          description: "A transaction has been open for {{ $value }} seconds."
          runbook: "Query pg_stat_activity for long-running transactions. Check if the application has a connection leak. Cancel with pg_cancel_backend() or terminate with pg_terminate_backend()."

      - alert: CheckpointTooFrequent
        expr: rate(pg_stat_bgwriter_checkpoints_req_total[5m]) > 0.5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Checkpoints too frequent on {{ $labels.instance }}"
          description: "Requested checkpoints happening more than once every 2 minutes."
          runbook: "Increase max_wal_size and checkpoint_timeout. Frequent checkpoints cause I/O spikes and slow down queries."
```

Save and exit (`:wq`).

```bash
chown prometheus:prometheus /opt/prometheus/alerts.yml
```

### 2.5 Validate the alert rules

```bash
/opt/prometheus/promtool check rules /opt/prometheus/alerts.yml
```

Expected output:
```
Checking /opt/prometheus/alerts.yml
  SUCCESS: 8 rules found
```

### 2.6 Create the Prometheus systemd service

```bash
vi /etc/systemd/system/prometheus.service
```

Add:

```ini
[Unit]
Description=Prometheus Monitoring
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/opt/prometheus/prometheus \
    --config.file=/opt/prometheus/prometheus.yml \
    --storage.tsdb.path=/opt/prometheus/data \
    --storage.tsdb.retention.time=30d \
    --web.listen-address=:9090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Save and exit (`:wq`).

- `--storage.tsdb.retention.time=30d` - Keep 30 days of metrics history.
- `--web.listen-address=:9090` - Prometheus UI and API on port 9090.

```bash
systemctl daemon-reload
```

```bash
systemctl enable prometheus
```

```bash
systemctl start prometheus
```

### 2.7 Verify Prometheus is running

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | head -20
```

Expected output (yours will differ):
```json
{
    "status": "success",
    "data": {
        "activeTargets": [
            {
                "labels": {
                    "instance": "pg-prod-primary",
                    "job": "postgresql"
                },
                "health": "up",
                ...
```

### 2.8 Open the firewall

```bash
firewall-cmd --permanent --add-port=9090/tcp
```

```bash
firewall-cmd --reload
```

---

## 3. Install Grafana

### 3.1 Add the Grafana repository

```bash
vi /etc/yum.repos.d/grafana.repo
```

Add:

```ini
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
```

Save and exit (`:wq`).

### 3.2 Install Grafana

```bash
dnf install -y grafana
```

### 3.3 Start Grafana

```bash
systemctl enable grafana-server
```

```bash
systemctl start grafana-server
```

### 3.4 Open the firewall

```bash
firewall-cmd --permanent --add-port=3000/tcp
```

```bash
firewall-cmd --reload
```

### 3.5 Access Grafana

Open a browser and go to `http://[YOUR_SERVER_IP]:3000`

Default credentials: admin / admin. You will be prompted to change the password.

### 3.6 Add Prometheus as a data source

1. Go to Configuration (gear icon) -> Data Sources
2. Click "Add data source"
3. Select "Prometheus"
4. URL: `http://localhost:9090`
5. Click "Save & test"

Expected result: "Data source is working"

### 3.7 Import PostgreSQL dashboards

1. Go to Dashboards -> Import
2. Enter dashboard ID: `9628`
3. Click Load
4. Select the Prometheus data source
5. Click Import

Dashboard 9628 is the official PostgreSQL dashboard for postgres_exporter. It shows connections, transactions, tuple operations, cache hit ratio, and more.

Import a second dashboard for node metrics:

1. Go to Dashboards -> Import
2. Enter dashboard ID: `1860`
3. Click Load
4. Select the Prometheus data source
5. Click Import

Dashboard 1860 is the Node Exporter Full dashboard. It shows CPU, memory, disk, and network metrics.

---

## 4. On-Call Runbooks

Create a runbook for each alert. These live in your scripts directory for quick reference during incidents.

### 4.1 Create the runbooks directory

```bash
mkdir -p /opt/pgsql/scripts/runbooks
```

```bash
chown postgres:postgres /opt/pgsql/scripts/runbooks
```

### 4.2 PostgreSQL Down runbook

```bash
vi /opt/pgsql/scripts/runbooks/postgresql-down.md
```

Add:

```
# PostgreSQL Down

## Alert: PostgresqlDown
## Severity: Critical

### Step 1: Check the service status
    systemctl status postgresql-16

### Step 2: Check the PostgreSQL log
    tail -100 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log

### Step 3: Check disk space
    df -h /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/log

### Step 4: Try to start
    systemctl start postgresql-16

### Step 5: If start fails, check for corrupted files
    su - postgres
    /usr/pgsql-16/bin/pg_controldata /opt/pgsql/data

### Step 6: If data is corrupt, failover
    On standby: repmgr standby promote
    Then restore primary from backup

### Escalation
If not resolved in 15 minutes, page the DBA team lead.
```

Save and exit (`:wq`).

### 4.3 Replication Lag runbook

```bash
vi /opt/pgsql/scripts/runbooks/replication-lag.md
```

Add:

```
# Replication Lag High

## Alert: ReplicationLagHigh
## Severity: Warning

### Step 1: Check replication status on primary
    su - postgres
    psql -c "SELECT client_addr, state, sent_lsn, replay_lsn,
             pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_behind
             FROM pg_stat_replication;"

### Step 2: Check the standby is replaying
    On standby:
    su - postgres
    psql -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
             pg_last_xact_replay_timestamp();"

### Step 3: Check for recovery conflicts
    On standby:
    psql -c "SELECT * FROM pg_stat_database_conflicts WHERE datname = 'appdb';"

### Step 4: Check network latency
    ping -c 5 [PRIMARY_IP]

### Step 5: Check standby CPU and I/O
    top -bn1 | head -20
    iostat -x 1 5

### Common causes:
- Network congestion between servers
- Standby disk I/O is saturated
- Long-running queries on standby blocking replay
- Large transaction on primary (bulk load)

### Resolution:
- If network: check for bandwidth saturation
- If I/O: check for competing workloads on standby
- If query conflict: cancel the blocking query on standby
- If bulk load: lag is expected, wait for it to catch up
```

Save and exit (`:wq`).

### 4.4 Connection Usage runbook

```bash
vi /opt/pgsql/scripts/runbooks/connection-usage.md
```

Add:

```
# Connection Usage High

## Alert: ConnectionUsageHigh
## Severity: Warning

### Step 1: Check current connections
    su - postgres
    psql -c "SELECT state, count(*) FROM pg_stat_activity
             GROUP BY state ORDER BY count DESC;"

### Step 2: Find idle connections
    psql -c "SELECT pid, usename, datname, state,
             now() - state_change AS idle_time
             FROM pg_stat_activity
             WHERE state = 'idle'
             ORDER BY idle_time DESC
             LIMIT 20;"

### Step 3: Check connections by application
    psql -c "SELECT application_name, count(*)
             FROM pg_stat_activity
             GROUP BY application_name
             ORDER BY count DESC;"

### Step 4: Kill idle connections older than 1 hour
    psql -c "SELECT pg_terminate_backend(pid)
             FROM pg_stat_activity
             WHERE state = 'idle'
             AND now() - state_change > interval '1 hour'
             AND pid != pg_backend_pid();"

### Prevention:
- Set idle_in_transaction_session_timeout = '5min'
- Use pgBouncer with transaction pooling
- Set connection limits per role: ALTER ROLE app_readwrite CONNECTION LIMIT 50;
```

Save and exit (`:wq`).

### 4.5 Dead Tuple Ratio runbook

```bash
vi /opt/pgsql/scripts/runbooks/dead-tuples.md
```

Add:

```
# Dead Tuple Ratio High

## Alert: DeadTupleRatioHigh
## Severity: Warning

### Step 1: Check which tables have high dead tuples
    su - postgres
    psql -d appdb -c "SELECT schemaname, relname, n_live_tup, n_dead_tup,
                       round(n_dead_tup::numeric/greatest(n_live_tup,1)*100, 1) AS pct,
                       last_autovacuum, last_autoanalyze
                       FROM pg_stat_user_tables
                       WHERE n_dead_tup > 1000
                       ORDER BY pct DESC;"

### Step 2: Check if autovacuum is running
    psql -c "SELECT pid, datname, relid::regclass, phase, heap_blks_total, heap_blks_scanned
             FROM pg_stat_progress_vacuum;"

### Step 3: Check if autovacuum is blocked
    psql -c "SELECT a.pid, a.wait_event, a.query
             FROM pg_stat_activity a
             WHERE a.backend_type = 'autovacuum worker';"

### Step 4: Manual vacuum if needed
    psql -d appdb -c "VACUUM ANALYZE app.orders;"

### Step 5: Check autovacuum settings for the table
    psql -d appdb -c "SELECT relname, reloptions
                       FROM pg_class
                       WHERE relname = 'orders';"

### Prevention:
- Lower autovacuum_vacuum_scale_factor for large tables
- Monitor autovacuum runtime
- Avoid long-running transactions (they block vacuum)
```

Save and exit (`:wq`).

### 4.6 Disk Usage runbook

```bash
vi /opt/pgsql/scripts/runbooks/disk-usage.md
```

Add:

```
# Disk Usage High

## Alert: DiskUsageHigh
## Severity: Critical

### Step 1: Check which filesystems are full
    df -h

### Step 2: Find the biggest consumers
    du -sh /opt/pgsql/data
    du -sh /opt/pgsql/wal
    du -sh /opt/pgsql/log
    du -sh /opt/pgsql/backup

### Step 3: Check for WAL accumulation
    su - postgres
    psql -c "SELECT count(*) FROM pg_ls_waldir();"

### Step 4: Check for inactive replication slots
    psql -c "SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS bytes_retained
             FROM pg_replication_slots
             ORDER BY bytes_retained DESC;"

### Step 5: Emergency - remove old logs
    ls -lah /opt/pgsql/log/
    # Remove logs older than 7 days
    find /opt/pgsql/log -name "*.log" -mtime +7 -delete

### Step 6: Emergency - drop inactive slots
    psql -c "SELECT pg_drop_replication_slot('slot_name');"

### Step 7: Check backup retention
    pgbackrest --stanza=prod info
    pgbackrest --stanza=prod expire

### Prevention:
- Monitor disk usage with alerts at 70%, 80%, 85%
- Set up log rotation
- Review backup retention policy
- Monitor replication slot WAL retention
```

Save and exit (`:wq`).

---

## 5. Test Each Alert

### 5.1 Test the connection usage alert

Generate connections to approach the 80% threshold:

```bash
su - postgres
```

```bash
for i in $(seq 1 160); do /usr/pgsql-16/bin/psql -d appdb -c "SELECT pg_sleep(120);" & done
```

This launches 160 background psql sessions, each sleeping for 120 seconds. With max_connections=200, this is 80%.

Wait 5 minutes, then check Prometheus:

```bash
curl -s 'http://localhost:9090/api/v1/alerts' | python3 -m json.tool | head -30
```

You should see the ConnectionUsageHigh alert firing.

Clean up the test connections:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query = 'SELECT pg_sleep(120)' AND pid != pg_backend_pid();"
```

```bash
exit
```

### 5.2 Verify Prometheus targets

```bash
curl -s 'http://localhost:9090/api/v1/targets' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    print(f\"{t['labels'].get('instance', t['labels']['job'])}: {t['health']}\")
"
```

Expected output (yours will differ):
```
pg-prod-primary: up
pg-prod-standby: up
localhost:9090: up
```

---

## 6. Install node_exporter (Optional but Recommended)

node_exporter provides OS-level metrics (CPU, memory, disk, network) to Prometheus.

### 6.1 Download and install

Run as root on **both** servers:

```bash
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
```

```bash
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
```

```bash
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
```

### 6.2 Create the systemd service

```bash
vi /etc/systemd/system/node_exporter.service
```

Add:

```ini
[Unit]
Description=Prometheus Node Exporter
After=network-online.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Save and exit (`:wq`).

```bash
systemctl daemon-reload
```

```bash
systemctl enable node_exporter
```

```bash
systemctl start node_exporter
```

### 6.3 Open the firewall

```bash
firewall-cmd --permanent --add-port=9100/tcp
```

```bash
firewall-cmd --reload
```

### 6.4 Verify

```bash
curl -s http://localhost:9100/metrics | head -5
```

Expected output (yours will differ):
```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
...
```

---

## Summary

You now have a complete monitoring and alerting stack:

- postgres_exporter collecting PostgreSQL metrics every 15 seconds
- Custom queries for replication lag, dead tuples, connection usage, disk
- Prometheus scraping and storing 30 days of metrics
- 8 alert rules covering the critical failure modes
- Grafana dashboards for visualization
- On-call runbooks for each alert
- node_exporter for OS-level metrics

Next: [Build 05 - Day Two Operations](05-day-two-operations.md)
