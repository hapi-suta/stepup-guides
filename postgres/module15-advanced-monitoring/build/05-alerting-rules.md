# Build Guide 05 - Prometheus Alerting Rules

**Module:** 15 - Advanced Monitoring
**Node:** pg-primary
**Time:** ~25 minutes

---

## Overview

Dashboards are for humans watching a screen. Alerting is for when no one is watching. Prometheus alerting rules evaluate PromQL expressions on a schedule. When a condition is true for longer than the configured duration, Prometheus marks the alert as FIRING and can send it to Alertmanager for notification routing.

In this guide you will write alerting rules for the most critical PostgreSQL failure conditions: the exporter going down, too many connections, long-running queries, and excessive replication lag. You will then trigger one of them deliberately so you can watch the state change from PENDING to FIRING.

---

## Step 1 - Log in to pg-primary

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

---

## Step 2 - Create the alerting rules file

Prometheus reads rule files from the paths listed under `rule_files:` in prometheus.yml. You configured it to read from `/etc/prometheus/rules/*.yml`, so any `.yml` file in that directory will be loaded.

```bash
sudo vi /etc/prometheus/rules/postgres.yml
```

Add this content:

```yaml
groups:
  - name: postgres_alerts
    interval: 30s
    rules:

      # Alert when postgres_exporter stops reporting metrics.
      # This could mean the exporter process crashed or lost its DB connection.
      - alert: PostgresExporterDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "postgres_exporter is down"
          description: "postgres_exporter on {{ $labels.instance }} has been unreachable for more than 1 minute. Metrics are no longer being collected."

      # Alert when active connection count exceeds 80% of max_connections.
      # Default max_connections is 100. 80% of 100 = 80 connections.
      # Adjust the threshold to match your max_connections setting.
      - alert: PostgresHighConnectionCount
        expr: sum(pg_stat_activity_count{state!="idle"}) by (instance) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High active connection count on {{ $labels.instance }}"
          description: "{{ $value }} non-idle connections have been open for more than 5 minutes. Check for connection leaks or missing connection pooling."

      # Alert when any query has been running for more than 5 minutes.
      # Long-running queries hold locks that block other work.
      - alert: PostgresLongRunningQuery
        expr: >
          pg_stat_activity_max_tx_duration{state="active",datname!=""}
          > 300
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Long-running query on {{ $labels.instance }}"
          description: "A query in database {{ $labels.datname }} has been running for {{ $value | humanizeDuration }}. Investigate with pg_stat_activity."

      # Alert when a transaction has been idle-in-transaction for more than 10 minutes.
      # Idle-in-transaction sessions hold locks without doing work.
      - alert: PostgresIdleInTransaction
        expr: >
          pg_stat_activity_max_tx_duration{state="idle in transaction",datname!=""}
          > 600
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Idle-in-transaction session on {{ $labels.instance }}"
          description: "A session in database {{ $labels.datname }} has been idle-in-transaction for {{ $value | humanizeDuration }}. It may be holding locks."

      # Alert when replication lag exceeds 30 seconds.
      # In this single-node lab this alert will not fire, but it is essential
      # in production streaming replication setups.
      - alert: PostgresReplicationLag
        expr: pg_replication_lag > 30
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag is high on {{ $labels.instance }}"
          description: "Replication lag is {{ $value | humanizeDuration }}. The standby may fall too far behind to be a useful failover target."

      # Alert when shared buffer cache hit ratio drops below 90%.
      # Below 90% means many queries are reading from disk instead of memory.
      - alert: PostgresLowCacheHitRatio
        expr: >
          (
            sum(rate(pg_stat_database_blks_hit[5m])) by (instance)
            /
            (
              sum(rate(pg_stat_database_blks_hit[5m])) by (instance)
              + sum(rate(pg_stat_database_blks_read[5m])) by (instance)
            )
          ) < 0.90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low cache hit ratio on {{ $labels.instance }}"
          description: "Cache hit ratio is {{ $value | humanizePercentage }}. Consider increasing shared_buffers or adding indexes to reduce sequential scans."

      # Alert when PostgreSQL has not had a successful checkpoint for more than 10 minutes.
      # This can indicate storage problems or excessive WAL generation.
      - alert: PostgresCheckpointWriteTimeTooHigh
        expr: >
          rate(pg_stat_bgwriter_checkpoint_write_time[5m]) /
          rate(pg_stat_bgwriter_checkpoints_timed[5m]) > 30000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Checkpoint write time is high on {{ $labels.instance }}"
          description: "Average checkpoint write time is {{ $value | humanizeDuration }}. This may indicate I/O bottlenecks or undersized shared_buffers."
```

Save and close the file.

---

## Step 3 - Validate the rules file with promtool

`promtool check rules` validates the PromQL expressions and YAML structure of your rules file before you reload Prometheus. Always run this before reloading.

```bash
sudo -u prometheus /usr/local/bin/promtool check rules /etc/prometheus/rules/postgres.yml
```

Expected output (yours will differ):

```
Checking /etc/prometheus/rules/postgres.yml
  SUCCESS: 7 rules found
```

If you see `FAILED`, check the line number in the error message and fix the YAML in the rules file.

---

## Step 4 - Fix ownership on the rules file

```bash
sudo chown prometheus:prometheus /etc/prometheus/rules/postgres.yml
```

---

## Step 5 - Reload Prometheus to pick up the new rules

Because you started Prometheus with `--web.enable-lifecycle`, you can reload its configuration without restarting the process. A `POST` to `/-/reload` triggers a hot reload.

```bash
curl -s -X POST http://localhost:9090/-/reload
```

Expected output (yours will differ):

```

```

An empty response means the reload was accepted. Check the status endpoint to confirm:

```bash
curl -s http://localhost:9090/-/healthy
```

Expected output (yours will differ):

```
Prometheus Server is Healthy.
```

---

## Step 6 - Verify the rules are loaded in the Prometheus UI

Open your browser and navigate to:

```
http://<your-server-ip>:9090/alerts
```

You should see a section called `postgres_alerts` with 7 rules listed. Each rule shows its current state: `inactive`, `pending`, or `firing`.

- **Inactive** - the PromQL expression is currently false
- **Pending** - the expression became true, but has not been true for the full `for:` duration yet
- **Firing** - the expression has been true for longer than `for:` and the alert is active

---

## Step 7 - View the loaded rules via API

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep '"name"'
```

Expected output (yours will differ):

```
            "name": "postgres_alerts",
            "name": "PostgresExporterDown",
            "name": "PostgresHighConnectionCount",
            "name": "PostgresLongRunningQuery",
            "name": "PostgresIdleInTransaction",
            "name": "PostgresReplicationLag",
            "name": "PostgresLowCacheHitRatio",
            "name": "PostgresCheckpointWriteTimeTooHigh",
```

---

## Step 8 - Trigger a test alert by stopping postgres_exporter

You will stop postgres_exporter so the `PostgresExporterDown` alert fires. The `for: 1m` setting means you need to wait 1 minute for the alert to move from PENDING to FIRING.

```bash
sudo systemctl stop postgres_exporter
```

---

## Step 9 - Watch the alert state change

Check the /alerts page in Prometheus every 30 seconds. Within 1-2 minutes you should see `PostgresExporterDown` change from `inactive` to `pending` to `firing`.

You can also poll via the API:

```bash
curl -s 'http://localhost:9090/api/v1/alerts' | python3 -m json.tool | grep -A3 '"alertname"'
```

Expected output after the alert fires (yours will differ):

```json
            "alertname": "PostgresExporterDown",
            "instance": "localhost:9187",
            "job": "postgres",
            "severity": "critical",
```

---

## Step 10 - Restart postgres_exporter to resolve the alert

```bash
sudo systemctl start postgres_exporter
```

Wait about 1-2 minutes. The alert should return to `inactive` state once Prometheus successfully scrapes the exporter again.

---

## Step 11 - (Optional) Install Alertmanager for notification routing

Prometheus fires alerts, but it does not send emails or Slack messages by itself. That is Alertmanager's job. Alertmanager receives alerts from Prometheus and routes them to notification channels.

Download Alertmanager:

```bash
curl -L -o /tmp/alertmanager.tar.gz \
  https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
```

```bash
tar -xzf /tmp/alertmanager.tar.gz -C /tmp/
```

```bash
sudo mv /tmp/alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
sudo mv /tmp/alertmanager-0.27.0.linux-amd64/amtool /usr/local/bin/
```

Create the Alertmanager config directory:

```bash
sudo mkdir -p /etc/alertmanager
sudo mkdir -p /var/lib/alertmanager
```

Create a minimal Alertmanager configuration that logs alerts to stdout (no external notifications):

```bash
sudo vi /etc/alertmanager/alertmanager.yml
```

Add this content:

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'null'

receivers:
  - name: 'null'
```

Save and close the file. This configuration silences all notifications - it is useful for testing that the alert pipeline works end-to-end before adding real notification targets.

Connect Prometheus to Alertmanager by adding this section to `/etc/prometheus/prometheus.yml` (before the `rule_files:` line):

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093
```

You would then create a systemd service for Alertmanager (similar to the Prometheus service) and reload both services.

For this lab, this optional configuration is not required. The focus is on writing and testing alert rules inside Prometheus itself.

---

## Summary

You have:
- Written 7 alerting rules covering the most important PostgreSQL failure conditions
- Validated the rules file with `promtool check rules`
- Hot-reloaded Prometheus to activate the rules
- Triggered the `PostgresExporterDown` alert by stopping the exporter
- Watched the alert state transition from inactive to pending to firing
- Restored normal operation and watched the alert resolve

You now have a complete monitoring stack: postgres_exporter collects metrics, Prometheus stores and evaluates them, Grafana visualizes them, and alerting rules notify you when thresholds are crossed.
