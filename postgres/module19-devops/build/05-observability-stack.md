# Module 19 - BUILD 05: Observability Stack for PostgreSQL

## Overview

Observability means being able to understand what your database is doing at any moment - not just "is it up?" but "why is it slow?" This guide covers the full stack: Prometheus for metrics collection, postgres_exporter for exposing PostgreSQL metrics, Grafana for dashboards, log aggregation, and alerting.

---

## Prerequisites

- CentOS Stream 9 server with PostgreSQL 16 installed and running
- `postgres` OS user configured
- Ports 9090 (Prometheus), 9187 (postgres_exporter), and 3000 (Grafana) available

---

## Part 1: Prometheus + postgres_exporter Setup

### 1.1 How It Works

The data flow is:

```
PostgreSQL --> postgres_exporter --> Prometheus --> Grafana
                (collects)          (stores)      (displays)
```

- **postgres_exporter** connects to PostgreSQL and converts internal stats into Prometheus-format metrics
- **Prometheus** scrapes those metrics every 15 seconds and stores them as time series
- **Grafana** queries Prometheus and renders dashboards

### 1.2 Install postgres_exporter

Download the exporter binary. The `-L` flag follows redirects.

```bash
curl -L -o /tmp/postgres_exporter-0.15.0.linux-amd64.tar.gz https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz
```

Extract it.

```bash
sudo tar -xzf /tmp/postgres_exporter-0.15.0.linux-amd64.tar.gz -C /opt/
```

Move the binary to a standard location.

```bash
sudo cp /opt/postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/local/bin/
```

Verify it works.

```bash
postgres_exporter --version
```

Expected output (yours will differ):
```
postgres_exporter, version 0.15.0 (branch: HEAD, revision: ...)
```

### 1.3 Create a Monitoring User in PostgreSQL

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to PostgreSQL.

```bash
psql
```

Create a dedicated monitoring user with minimal privileges.

```sql
CREATE ROLE monitoring WITH LOGIN PASSWORD 'MonitorPass123';
```

Grant the necessary permissions.

```sql
GRANT pg_monitor TO monitoring;
```

The `pg_monitor` role is a built-in PostgreSQL role that grants read access to various statistics views and functions. It is the recommended way to give monitoring tools access without giving them superuser.

Create a monitoring database.

```sql
CREATE DATABASE monitoring OWNER monitoring;
```

Exit psql.

```sql
\q
```

Update pg_hba.conf to allow the monitoring user to connect locally. Open the file.

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Add this line before the first `host` line:

```
host    all             monitoring      127.0.0.1/32            scram-sha-256
```

Reload PostgreSQL to apply the pg_hba.conf change.

```bash
pg_ctl -D /opt/pgsql/data reload
```

Exit the postgres user.

```bash
exit
```

### 1.4 Configure postgres_exporter as a systemd Service

Create a systemd unit file. This ensures the exporter starts automatically and restarts on failure.

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

```ini
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network-online.target postgresql-16.service
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
Environment="DATA_SOURCE_NAME=postgresql://monitoring:MonitorPass123@127.0.0.1:5432/monitoring?sslmode=disable"
ExecStart=/usr/local/bin/postgres_exporter \
    --web.listen-address=:9187 \
    --collector.process_idle \
    --collector.postmaster \
    --collector.stat_bgwriter \
    --collector.stat_database \
    --collector.stat_user_tables \
    --collector.statio_user_tables \
    --collector.stat_statements \
    --log.level=warn
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Key flags:
- `--web.listen-address=:9187` - Port where metrics are exposed
- `--collector.*` - Enable specific metric collectors
- `--log.level=warn` - Only log warnings and errors (reduces noise)
- `Restart=always` - Automatically restart if the process crashes

Reload systemd to pick up the new service file.

```bash
sudo systemctl daemon-reload
```

Start the exporter.

```bash
sudo systemctl start postgres_exporter
```

Enable it to start on boot.

```bash
sudo systemctl enable postgres_exporter
```

Check the status.

```bash
sudo systemctl status postgres_exporter
```

Expected output (yours will differ):
```
 postgres_exporter.service - Prometheus PostgreSQL Exporter
     Loaded: loaded (/etc/systemd/system/postgres_exporter.service; enabled)
     Active: active (running) since ...
```

### 1.5 Verify Metrics Are Available

Use curl to check the metrics endpoint. The `-s` flag silences progress output.

```bash
curl -s http://localhost:9187/metrics | head -20
```

Expected output (yours will differ):
```
# HELP pg_database_size_bytes Database size in bytes
# TYPE pg_database_size_bytes gauge
pg_database_size_bytes{datname="monitoring"} 8.765432e+06
pg_database_size_bytes{datname="postgres"} 7.654321e+06
...
```

Check for specific metrics.

```bash
curl -s http://localhost:9187/metrics | grep pg_stat_database_tup_inserted
```

Expected output (yours will differ):
```
# HELP pg_stat_database_tup_inserted Number of rows inserted
# TYPE pg_stat_database_tup_inserted counter
pg_stat_database_tup_inserted{datname="monitoring"} 0
pg_stat_database_tup_inserted{datname="postgres"} 145
```

### 1.6 Install Prometheus

Create a prometheus user. The `-r` flag creates a system account. The `-s /sbin/nologin` prevents interactive login.

```bash
sudo useradd -r -s /sbin/nologin prometheus
```

Download Prometheus.

```bash
curl -L -o /tmp/prometheus-2.50.1.linux-amd64.tar.gz https://github.com/prometheus/prometheus/releases/download/v2.50.1/prometheus-2.50.1.linux-amd64.tar.gz
```

Extract it.

```bash
sudo tar -xzf /tmp/prometheus-2.50.1.linux-amd64.tar.gz -C /opt/
```

```bash
sudo mv /opt/prometheus-2.50.1.linux-amd64 /opt/prometheus
```

Create data directories.

```bash
sudo mkdir -p /opt/prometheus/data
```

```bash
sudo chown -R prometheus:prometheus /opt/prometheus
```

### 1.7 Configure Prometheus

```bash
sudo vi /opt/prometheus/prometheus.yml
```

```yaml
# prometheus.yml - Prometheus configuration

global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alerting rules (covered in Part 4)
rule_files:
  - "rules/*.yml"

# Scrape targets
scrape_configs:
  # Prometheus monitors itself
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # PostgreSQL primary
  - job_name: "postgresql-primary"
    static_configs:
      - targets: ["localhost:9187"]
        labels:
          role: "primary"
          instance_name: "pg-primary"

  # PostgreSQL replicas (add more targets as needed)
  # - job_name: "postgresql-replica"
  #   static_configs:
  #     - targets: ["replica1:9187", "replica2:9187"]
  #       labels:
  #         role: "replica"
```

Key settings:
- `scrape_interval: 15s` - How often Prometheus collects metrics (15 seconds is standard)
- `evaluation_interval: 15s` - How often alerting rules are evaluated
- `labels` - Custom labels attached to every metric from this target

### 1.8 Create Prometheus systemd Service

```bash
sudo vi /etc/systemd/system/prometheus.service
```

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
    --web.listen-address=:9090 \
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Key flags:
- `--storage.tsdb.retention.time=30d` - Keep metrics for 30 days
- `--web.enable-lifecycle` - Allows reloading config via HTTP API

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start prometheus
```

```bash
sudo systemctl enable prometheus
```

Verify Prometheus is scraping postgres_exporter.

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | head -30
```

Expected output (yours will differ):
```json
{
    "status": "success",
    "data": {
        "activeTargets": [
            {
                "labels": {
                    "instance": "localhost:9187",
                    "job": "postgresql-primary",
                    "role": "primary"
                },
                "health": "up",
                ...
            }
        ]
    }
}
```

The `"health": "up"` confirms Prometheus is successfully scraping metrics.

---

## Part 2: Grafana Dashboards for PostgreSQL

### 2.1 Install Grafana

Add the Grafana repository.

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

Install Grafana.

```bash
sudo dnf install -y grafana
```

Start and enable Grafana.

```bash
sudo systemctl start grafana-server
```

```bash
sudo systemctl enable grafana-server
```

Verify it is running.

```bash
sudo systemctl status grafana-server
```

Grafana is now available at `http://your-server:3000`. The default login is `admin` / `admin`.

### 2.2 Add Prometheus as a Data Source

You can do this via the Grafana API. The `-X POST` flag sends an HTTP POST request.

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
{"datasource":{"id":1,"name":"Prometheus","type":"prometheus",...},"id":1,"message":"Datasource added","name":"Prometheus"}
```

### 2.3 Import a PostgreSQL Dashboard

The community maintains excellent pre-built dashboards. Dashboard ID 9628 is the most popular PostgreSQL dashboard.

```bash
curl -s -X POST http://admin:admin@localhost:3000/api/dashboards/import \
    -H "Content-Type: application/json" \
    -d '{
        "dashboard": {
            "id": null,
            "uid": null,
            "title": "PostgreSQL Overview",
            "tags": ["postgresql", "database"],
            "timezone": "browser",
            "schemaVersion": 16,
            "version": 0,
            "refresh": "30s"
        },
        "overwrite": true,
        "inputs": [],
        "folderId": 0
    }'
```

### 2.4 Create a Custom Dashboard via JSON

For a production-ready PostgreSQL dashboard, create a JSON definition.

```bash
sudo vi /opt/prometheus/grafana-pg-dashboard.json
```

```json
{
  "dashboard": {
    "title": "PostgreSQL DBA Dashboard",
    "tags": ["postgresql", "dba"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Transactions Per Second",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "rate(pg_stat_database_xact_commit{datname!='template0'}[5m]) + rate(pg_stat_database_xact_rollback{datname!='template0'}[5m])",
            "legendFormat": "{{datname}}"
          }
        ]
      },
      {
        "title": "Active Connections",
        "type": "gauge",
        "gridPos": {"h": 8, "w": 6, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "pg_stat_activity_count{state='active'}",
            "legendFormat": "Active"
          }
        ]
      },
      {
        "title": "Database Size",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 6, "x": 18, "y": 0},
        "targets": [
          {
            "expr": "pg_database_size_bytes{datname!='template0'}",
            "legendFormat": "{{datname}}"
          }
        ]
      },
      {
        "title": "Cache Hit Ratio",
        "type": "stat",
        "gridPos": {"h": 8, "w": 6, "x": 0, "y": 8},
        "targets": [
          {
            "expr": "pg_stat_database_blks_hit{datname!='template0'} / (pg_stat_database_blks_hit{datname!='template0'} + pg_stat_database_blks_read{datname!='template0'}) * 100",
            "legendFormat": "{{datname}}"
          }
        ]
      },
      {
        "title": "Replication Lag (bytes)",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 6, "y": 8},
        "targets": [
          {
            "expr": "pg_replication_slots_confirmed_flush_lsn - pg_replication_slots_restart_lsn",
            "legendFormat": "{{slot_name}}"
          }
        ]
      },
      {
        "title": "Tuple Operations",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 6, "x": 18, "y": 8},
        "targets": [
          {
            "expr": "rate(pg_stat_database_tup_inserted[5m])",
            "legendFormat": "inserts/s"
          },
          {
            "expr": "rate(pg_stat_database_tup_updated[5m])",
            "legendFormat": "updates/s"
          },
          {
            "expr": "rate(pg_stat_database_tup_deleted[5m])",
            "legendFormat": "deletes/s"
          }
        ]
      }
    ]
  },
  "overwrite": true,
  "folderId": 0
}
```

Import the dashboard.

```bash
curl -s -X POST http://admin:admin@localhost:3000/api/dashboards/import \
    -H "Content-Type: application/json" \
    -d @/opt/prometheus/grafana-pg-dashboard.json
```

---

## Part 3: Log Aggregation

### 3.1 Configure PostgreSQL Logging

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check current logging settings.

```bash
psql -c "SHOW logging_collector;"
```

```bash
psql -c "SHOW log_directory;"
```

```bash
psql -c "SHOW log_filename;"
```

If logging_collector is off, enable it. Open postgresql.conf.

```bash
vi /opt/pgsql/data/postgresql.conf
```

Ensure these settings are present:

```ini
logging_collector = on
log_directory = '/opt/pgsql/log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_connections = on
log_disconnections = on
log_lock_waits = on
log_statement = 'ddl'
log_checkpoints = on
log_temp_files = 0
```

Key settings:
- `log_min_duration_statement = 1000` - Log any query taking more than 1 second
- `log_lock_waits = on` - Log when a query waits for a lock
- `log_checkpoints = on` - Log checkpoint activity (helps tune checkpoint settings)
- `log_temp_files = 0` - Log when temp files are created (indicates work_mem too low)

Restart PostgreSQL to apply logging_collector change (this one requires restart, not just reload).

```bash
pg_ctl -D /opt/pgsql/data -l /opt/pgsql/log/startup.log restart -m fast
```

Exit the postgres user.

```bash
exit
```

### 3.2 rsyslog Configuration

To forward PostgreSQL logs to a central syslog server.

```bash
sudo vi /etc/rsyslog.d/postgresql.conf
```

```
# Forward PostgreSQL logs to central syslog
module(load="imfile")

input(type="imfile"
      File="/opt/pgsql/log/postgresql-*.log"
      Tag="postgresql:"
      Severity="info"
      Facility="local0")

# Forward to remote syslog server (uncomment for production)
# local0.* @@logserver.internal:514
```

Restart rsyslog to apply.

```bash
sudo systemctl restart rsyslog
```

### 3.3 CloudWatch Agent (for AWS)

If running on AWS, configure the CloudWatch agent to ship PostgreSQL logs.

```bash
sudo vi /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/pgsql/log/postgresql-*.log",
            "log_group_name": "/postgresql/primary",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC",
            "retention_in_days": 30
          }
        ]
      }
    }
  }
}
```

---

## Part 4: Alerting Rules for DBA Scenarios

### 4.1 Create Prometheus Alert Rules

```bash
sudo mkdir -p /opt/prometheus/rules
```

```bash
sudo vi /opt/prometheus/rules/postgresql-alerts.yml
```

```yaml
groups:
  - name: postgresql-critical
    rules:
      # Alert if PostgreSQL is down
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down on {{ $labels.instance }}"
          description: "PostgreSQL exporter cannot connect to the database."
          runbook_url: "https://wiki.internal/runbooks/postgresql-down"

      # Alert if too many connections
      - alert: PostgreSQLTooManyConnections
        expr: pg_stat_activity_count / on() pg_settings_max_connections * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL connection usage above 80% on {{ $labels.instance }}"
          description: "Current connections: {{ $value }}% of max_connections"

      # Alert if connections at max
      - alert: PostgreSQLConnectionsExhausted
        expr: pg_stat_activity_count / on() pg_settings_max_connections * 100 > 95
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL connections nearly exhausted on {{ $labels.instance }}"
          description: "{{ $value }}% of connections in use. New connections will be refused."

  - name: postgresql-performance
    rules:
      # Alert if cache hit ratio drops
      - alert: PostgreSQLLowCacheHitRatio
        expr: |
          pg_stat_database_blks_hit{datname!~"template.*"}
          / (pg_stat_database_blks_hit{datname!~"template.*"} + pg_stat_database_blks_read{datname!~"template.*"})
          < 0.95
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low cache hit ratio on {{ $labels.datname }}"
          description: "Cache hit ratio is {{ $value | humanizePercentage }}. Consider increasing shared_buffers."

      # Alert on high commit latency
      - alert: PostgreSQLHighCommitLatency
        expr: rate(pg_stat_database_blk_write_time[5m]) > 100
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High I/O latency on {{ $labels.instance }}"
          description: "Block write time is elevated. Check disk performance."

  - name: postgresql-replication
    rules:
      # Alert on replication lag
      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag > 30
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag on {{ $labels.instance }}"
          description: "Replication is {{ $value }}s behind primary."

      # Alert if replication lag is critical
      - alert: PostgreSQLReplicationLagCritical
        expr: pg_replication_lag > 300
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Critical replication lag on {{ $labels.instance }}"
          description: "Replication is {{ $value }}s behind. Data loss risk."

      # Alert if replica is not streaming
      - alert: PostgreSQLReplicaNotStreaming
        expr: pg_replication_is_replica == 1 and pg_stat_wal_receiver_status != 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Replica not streaming on {{ $labels.instance }}"
          description: "WAL receiver is not connected to the primary."

  - name: postgresql-storage
    rules:
      # Alert on database size growth
      - alert: PostgreSQLDatabaseSizeLarge
        expr: pg_database_size_bytes > 100 * 1024 * 1024 * 1024
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Database {{ $labels.datname }} exceeds 100 GB"
          description: "Current size: {{ $value | humanize1024 }}B"

      # Alert on table bloat (dead tuples)
      - alert: PostgreSQLTableBloat
        expr: pg_stat_user_tables_n_dead_tup > 1000000
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "High dead tuple count on {{ $labels.relname }}"
          description: "{{ $value }} dead tuples. VACUUM may be blocked or autovacuum is behind."
```

Set permissions.

```bash
sudo chown -R prometheus:prometheus /opt/prometheus/rules
```

Reload Prometheus to pick up the new rules.

```bash
curl -X POST http://localhost:9090/-/reload
```

Verify rules are loaded.

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | head -20
```

---

## Part 5: Runbook Automation (PagerDuty, OpsGenie Integration)

### 5.1 Install Alertmanager

Alertmanager receives alerts from Prometheus and routes them to notification channels.

```bash
curl -L -o /tmp/alertmanager-0.27.0.linux-amd64.tar.gz https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
```

```bash
sudo tar -xzf /tmp/alertmanager-0.27.0.linux-amd64.tar.gz -C /opt/
```

```bash
sudo mv /opt/alertmanager-0.27.0.linux-amd64 /opt/alertmanager
```

```bash
sudo chown -R prometheus:prometheus /opt/alertmanager
```

### 5.2 Configure Alertmanager

```bash
sudo vi /opt/alertmanager/alertmanager.yml
```

```yaml
# alertmanager.yml - Alert routing and notification config

global:
  resolve_timeout: 5m

route:
  # Default receiver
  receiver: 'dba-team-slack'
  # Group alerts by alertname and instance
  group_by: ['alertname', 'instance']
  # Wait 30s to group related alerts before sending
  group_wait: 30s
  # Wait 5m between notifications for the same group
  group_interval: 5m
  # Wait 3h before re-sending a resolved alert
  repeat_interval: 3h

  # Route critical alerts to PagerDuty
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      continue: true
    - match:
        severity: critical
      receiver: 'dba-team-slack'

receivers:
  # Slack notifications
  - name: 'dba-team-slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#dba-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *{{ .Labels.severity | toUpper }}*: {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ if .Annotations.runbook_url }}Runbook: {{ .Annotations.runbook_url }}{{ end }}
          {{ end }}
        send_resolved: true

  # PagerDuty for critical alerts
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - routing_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'
        severity: '{{ .GroupLabels.severity }}'
        description: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
        details:
          description: '{{ .CommonAnnotations.description }}'
          runbook_url: '{{ .CommonAnnotations.runbook_url }}'

  # OpsGenie example (alternative to PagerDuty)
  # - name: 'opsgenie-critical'
  #   opsgenie_configs:
  #     - api_key: 'YOUR_OPSGENIE_API_KEY'
  #       message: '{{ .GroupLabels.alertname }}'
  #       description: '{{ .CommonAnnotations.description }}'
  #       priority: 'P1'
```

### 5.3 Point Prometheus to Alertmanager

Update the Prometheus config.

```bash
sudo vi /opt/prometheus/prometheus.yml
```

Add the alerting section at the top (after `global:`):

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093
```

### 5.4 Start Alertmanager

```bash
sudo vi /etc/systemd/system/alertmanager.service
```

```ini
[Unit]
Description=Prometheus Alertmanager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/opt/alertmanager/alertmanager \
    --config.file=/opt/alertmanager/alertmanager.yml \
    --storage.path=/opt/alertmanager/data \
    --web.listen-address=:9093
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start alertmanager
```

```bash
sudo systemctl enable alertmanager
```

Verify Alertmanager is running.

```bash
curl -s http://localhost:9093/api/v2/status | python3 -m json.tool | head -10
```

### 5.5 Test an Alert

Temporarily fire a test alert to verify the pipeline works.

```bash
curl -X POST http://localhost:9093/api/v2/alerts \
    -H "Content-Type: application/json" \
    -d '[{
        "labels": {
            "alertname": "TestAlert",
            "severity": "warning",
            "instance": "localhost:9187"
        },
        "annotations": {
            "summary": "This is a test alert",
            "description": "Testing the alert pipeline from Prometheus to Slack"
        },
        "startsAt": "2026-04-19T00:00:00Z"
    }]'
```

Check the Alertmanager UI at `http://your-server:9093` to see the active alert.

---

## Service Summary

After completing this guide, you should have these services running:

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Database |
| postgres_exporter | 9187 | Exports PG metrics |
| Prometheus | 9090 | Collects and stores metrics |
| Alertmanager | 9093 | Routes alerts |
| Grafana | 3000 | Dashboards and visualization |

Check all services are running.

```bash
sudo systemctl status postgres_exporter prometheus grafana-server alertmanager
```

---

## Key Takeaways

1. postgres_exporter converts PostgreSQL internal stats into Prometheus-format metrics
2. Use the `pg_monitor` role for monitoring users - never give superuser to exporters
3. Prometheus scrapes metrics every 15 seconds and stores them as time series
4. Grafana dashboards make it easy to spot trends and anomalies at a glance
5. Alert on symptoms (high latency, connection exhaustion) not just causes
6. Include runbook URLs in alert annotations so on-call engineers know what to do
7. Route critical alerts to PagerDuty/OpsGenie for 24/7 coverage
8. Ship PostgreSQL logs to a central location for searching and correlation
9. Log slow queries (`log_min_duration_statement`) and lock waits (`log_lock_waits`) at minimum
