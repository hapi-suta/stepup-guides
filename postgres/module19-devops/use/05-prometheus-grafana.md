# Module 19 - USE 05: Prometheus and Grafana Exercise

## Objective

Install postgres_exporter, configure Prometheus to scrape it, import a Grafana dashboard, and create an alert for replication lag.

---

## Setup

Make sure PostgreSQL 16 is running on your server.

```bash
sudo systemctl status postgresql-16
```

---

## Exercise 1: Install and Configure postgres_exporter

### Create the Monitoring User

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to PostgreSQL.

```bash
psql
```

Create a dedicated user for monitoring.

```sql
CREATE ROLE monitoring WITH LOGIN PASSWORD 'MonitorPass123';
```

Grant the pg_monitor role. This built-in role provides read access to stats without superuser.

```sql
GRANT pg_monitor TO monitoring;
```

Exit psql.

```sql
\q
```

Add the monitoring user to pg_hba.conf.

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Add this line (before other host lines):

```
host    all    monitoring    127.0.0.1/32    scram-sha-256
```

Reload PostgreSQL to apply the change.

```bash
pg_ctl -D /opt/pgsql/data reload
```

Test the connection.

```bash
psql -h 127.0.0.1 -U monitoring -d postgres -c "SELECT 1;"
```

Exit the postgres user.

```bash
exit
```

### Download and Install postgres_exporter

```bash
curl -L -o /tmp/postgres_exporter-0.15.0.linux-amd64.tar.gz https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz
```

```bash
sudo tar -xzf /tmp/postgres_exporter-0.15.0.linux-amd64.tar.gz -C /opt/
```

```bash
sudo cp /opt/postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/local/bin/
```

### Create the systemd Service

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

```ini
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
Environment="DATA_SOURCE_NAME=postgresql://monitoring:MonitorPass123@127.0.0.1:5432/postgres?sslmode=disable"
ExecStart=/usr/local/bin/postgres_exporter \
    --web.listen-address=:9187 \
    --collector.stat_bgwriter \
    --collector.stat_database \
    --collector.stat_user_tables \
    --collector.stat_statements \
    --log.level=warn
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Start the exporter.

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start postgres_exporter
```

```bash
sudo systemctl enable postgres_exporter
```

### Verify Metrics

```bash
curl -s http://localhost:9187/metrics | head -10
```

Expected output (yours will differ):
```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 1.234e-05
...
```

Check for a PostgreSQL-specific metric.

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

Expected output (yours will differ):
```
# HELP pg_up Whether the last scrape of metrics from PostgreSQL was able to connect to the server
# TYPE pg_up gauge
pg_up 1
```

The value `1` means the exporter is successfully connected to PostgreSQL.

---

## Exercise 2: Configure Prometheus Scrape Target

### Install Prometheus (if not already installed)

```bash
sudo useradd -r -s /sbin/nologin prometheus
```

```bash
curl -L -o /tmp/prometheus-2.50.1.linux-amd64.tar.gz https://github.com/prometheus/prometheus/releases/download/v2.50.1/prometheus-2.50.1.linux-amd64.tar.gz
```

```bash
sudo tar -xzf /tmp/prometheus-2.50.1.linux-amd64.tar.gz -C /opt/
```

```bash
sudo mv /opt/prometheus-2.50.1.linux-amd64 /opt/prometheus
```

```bash
sudo mkdir -p /opt/prometheus/data
```

```bash
sudo mkdir -p /opt/prometheus/rules
```

```bash
sudo chown -R prometheus:prometheus /opt/prometheus
```

### Configure the Scrape Target

```bash
sudo vi /opt/prometheus/prometheus.yml
```

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "postgresql"
    static_configs:
      - targets: ["localhost:9187"]
        labels:
          role: "primary"
          environment: "lab"
```

### Start Prometheus

```bash
sudo vi /etc/systemd/system/prometheus.service
```

```ini
[Unit]
Description=Prometheus
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/opt/prometheus/prometheus \
    --config.file=/opt/prometheus/prometheus.yml \
    --storage.tsdb.path=/opt/prometheus/data \
    --storage.tsdb.retention.time=15d \
    --web.listen-address=:9090 \
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start prometheus
```

```bash
sudo systemctl enable prometheus
```

### Verify the Target is Being Scraped

Wait about 15 seconds, then check the targets.

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A5 "postgresql"
```

Expected output (yours will differ):
```
            "labels": {
                "instance": "localhost:9187",
                "job": "postgresql",
                "role": "primary",
                "environment": "lab"
            },
            "health": "up",
```

The `"health": "up"` means Prometheus is successfully scraping metrics from postgres_exporter.

### Query a Metric

```bash
curl -s "http://localhost:9090/api/v1/query?query=pg_stat_database_tup_inserted" | python3 -m json.tool | head -20
```

---

## Exercise 3: Import a Grafana Dashboard

### Install Grafana (if not already installed)

```bash
sudo vi /etc/yum.repos.d/grafana.repo
```

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

```bash
sudo dnf install -y grafana
```

```bash
sudo systemctl start grafana-server
```

```bash
sudo systemctl enable grafana-server
```

### Add Prometheus as a Data Source

```bash
curl -s -X POST http://admin:admin@localhost:3000/api/datasources \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://localhost:9090",
        "access": "proxy",
        "isDefault": true
    }'
```

Expected output (yours will differ):
```json
{"datasource":{"id":1,"name":"Prometheus",...},"message":"Datasource added"}
```

### Import the PostgreSQL Dashboard

Import the community PostgreSQL dashboard (ID 9628).

```bash
curl -s -X POST http://admin:admin@localhost:3000/api/dashboards/import \
    -H "Content-Type: application/json" \
    -d '{
        "dashboard": {
            "id": null,
            "uid": "pg-overview",
            "title": "PostgreSQL Overview",
            "tags": ["postgresql"],
            "timezone": "browser",
            "refresh": "30s",
            "panels": [
                {
                    "title": "Database Up",
                    "type": "stat",
                    "gridPos": {"h": 4, "w": 4, "x": 0, "y": 0},
                    "targets": [{"expr": "pg_up", "legendFormat": "{{instance}}"}]
                },
                {
                    "title": "Active Connections",
                    "type": "gauge",
                    "gridPos": {"h": 4, "w": 4, "x": 4, "y": 0},
                    "targets": [{"expr": "sum(pg_stat_activity_count)", "legendFormat": "connections"}]
                },
                {
                    "title": "TPS",
                    "type": "timeseries",
                    "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
                    "targets": [{"expr": "rate(pg_stat_database_xact_commit[5m])", "legendFormat": "{{datname}}"}]
                },
                {
                    "title": "Database Size",
                    "type": "timeseries",
                    "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
                    "targets": [{"expr": "pg_database_size_bytes", "legendFormat": "{{datname}}"}]
                },
                {
                    "title": "Tuples Inserted/s",
                    "type": "timeseries",
                    "gridPos": {"h": 8, "w": 8, "x": 0, "y": 12},
                    "targets": [{"expr": "rate(pg_stat_database_tup_inserted[5m])", "legendFormat": "{{datname}}"}]
                },
                {
                    "title": "Tuples Updated/s",
                    "type": "timeseries",
                    "gridPos": {"h": 8, "w": 8, "x": 8, "y": 12},
                    "targets": [{"expr": "rate(pg_stat_database_tup_updated[5m])", "legendFormat": "{{datname}}"}]
                },
                {
                    "title": "Cache Hit Ratio",
                    "type": "stat",
                    "gridPos": {"h": 4, "w": 8, "x": 16, "y": 12},
                    "targets": [{"expr": "pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read + 0.001) * 100", "legendFormat": "{{datname}}"}]
                }
            ]
        },
        "overwrite": true,
        "folderId": 0
    }'
```

Verify the dashboard was imported. Open a browser to `http://your-server:3000` and log in with `admin`/`admin`. The dashboard should appear under Dashboards.

---

## Exercise 4: Create an Alert for Replication Lag

### Create the Alert Rule File

```bash
sudo vi /opt/prometheus/rules/postgresql-alerts.yml
```

```yaml
groups:
  - name: postgresql-replication
    rules:
      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag > 30
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag detected on {{ $labels.instance }}"
          description: "Replication lag is {{ $value }} seconds."

      - alert: PostgreSQLReplicationLagCritical
        expr: pg_replication_lag > 300
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Critical replication lag on {{ $labels.instance }}"
          description: "Replication lag is {{ $value }} seconds. Risk of data loss."

  - name: postgresql-connections
    rules:
      - alert: PostgreSQLHighConnections
        expr: sum(pg_stat_activity_count) / on() pg_settings_max_connections * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Connection usage above 80%"
          description: "{{ $value }}% of max_connections in use."

  - name: postgresql-availability
    rules:
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down on {{ $labels.instance }}"
          description: "postgres_exporter cannot connect to the database."
```

Set permissions.

```bash
sudo chown prometheus:prometheus /opt/prometheus/rules/postgresql-alerts.yml
```

### Reload Prometheus to Pick Up the Rules

```bash
curl -X POST http://localhost:9090/-/reload
```

### Verify Rules Are Loaded

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep "alertname"
```

Expected output (yours will differ):
```
                        "alertname": "PostgreSQLReplicationLag"
                        "alertname": "PostgreSQLReplicationLagCritical"
                        "alertname": "PostgreSQLHighConnections"
                        "alertname": "PostgreSQLDown"
```

### Test the Alert by Stopping PostgreSQL

Switch to the postgres user.

```bash
sudo -iu postgres
```

Stop PostgreSQL.

```bash
pg_ctl -D /opt/pgsql/data stop -m fast
```

Exit the postgres user.

```bash
exit
```

Wait about 2 minutes, then check if the alert fired.

```bash
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | head -20
```

Expected output (yours will differ):
```json
{
    "status": "success",
    "data": {
        "alerts": [
            {
                "labels": {
                    "alertname": "PostgreSQLDown",
                    "severity": "critical",
                    ...
                },
                "state": "firing",
                ...
            }
        ]
    }
}
```

Restart PostgreSQL.

```bash
sudo -iu postgres
```

```bash
pg_ctl -D /opt/pgsql/data -l /opt/pgsql/log/startup.log start
```

Exit the postgres user.

```bash
exit
```

Wait another minute and verify the alert resolves.

```bash
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep "state"
```

---

## Checklist

- [ ] Created monitoring user with pg_monitor role
- [ ] Installed and started postgres_exporter on port 9187
- [ ] Configured Prometheus to scrape postgres_exporter
- [ ] Verified Prometheus target shows "health": "up"
- [ ] Installed Grafana and added Prometheus data source
- [ ] Imported PostgreSQL dashboard with key panels
- [ ] Created alert rules for replication lag, connections, and availability
- [ ] Tested PostgreSQLDown alert by stopping PostgreSQL
- [ ] Verified alert resolved after restarting PostgreSQL
