# BUILD-13: Alertmanager Setup and Alert Rules

**Lab:** Voleon Group DBA Interview Prep
**Node:** pg-ops (34.228.32.17)
**Prerequisites:** BUILD-12 complete - Prometheus, node_exporter, and postgres_exporter are running

---

## What You Will Build

By the end of this guide you will have:

- Alertmanager 0.28.1 installed and running on pg-ops at port 9093
- A routing tree that sends critical alerts to one receiver and warning alerts to another
- 10 alert rules covering PostgreSQL health, replication lag, connections, disk, CPU, and node availability
- Recording rules that pre-compute expensive queries for faster dashboards
- Validated your setup by triggering a real alert and watching it flow through the pipeline

---

## Section 1: Understanding Alertmanager Architecture

### What Alertmanager Does

Prometheus evaluates alert rules on a schedule (every 15-30 seconds). When a rule condition is true, Prometheus fires an alert. But Prometheus does NOT send notifications itself - that is Alertmanager's job.

Alertmanager receives alerts from Prometheus and handles five things:

**Deduplication** - If the same alert fires from three different Prometheus instances, Alertmanager sends one notification, not three.

**Grouping** - Related alerts are batched into a single notification. Instead of 20 separate "disk low" emails for 20 servers, you get one email listing all 20 servers.

**Routing** - Different alerts go to different receivers. Critical database alerts might go to PagerDuty, while informational alerts go to a Slack channel.

**Silencing** - During a maintenance window you can tell Alertmanager to suppress notifications for specific alerts. The alerts still fire in Prometheus - they just do not generate notifications.

**Inhibition** - If a critical alert is firing, Alertmanager can suppress the related warning alerts. If the node is down, you do not need a separate "high CPU" notification for that same node.

### How Prometheus and Alertmanager Work Together

The architecture looks like this:

```
Targets (node_exporter, postgres_exporter)
    |
    | scrape metrics every 15s
    v
Prometheus
    |
    | evaluates alert rules every 15-30s
    | if rule fires -> sends alert to Alertmanager
    v
Alertmanager
    |
    | deduplicates, groups, routes
    v
Receivers (PagerDuty, Slack, email, webhook)
```

Prometheus is the brain that knows when something is wrong. Alertmanager is the notification manager that decides who to tell and when.

### Alert Lifecycle

Every alert goes through three states:

**Pending** - The rule condition is true, but not yet long enough. Most rules have a `for` duration (e.g., `for: 5m`). During those 5 minutes the alert is pending. This prevents false positives from transient spikes.

**Firing** - The condition has been true for the full `for` duration. Alertmanager now receives this alert and processes it.

**Resolved** - The condition is no longer true. Alertmanager sends a resolution notification (if configured).

You can see all three states in the Prometheus UI at `http://34.228.32.17:9090/alerts`.

---

## Section 2: Installing Alertmanager on pg-ops

All commands in this section run on **pg-ops** as **ec2-user**.

### Step 1: SSH into pg-ops

From your local machine:

```bash
ssh -i your-key.pem ec2-user@34.228.32.17
```

### Step 2: Move into the prometheus directory

This keeps all monitoring binaries in one place alongside Prometheus.

On **pg-ops**, as **ec2-user**:

```bash
cd /opt/prometheus
```

### Step 3: Download Alertmanager

This downloads the Alertmanager 0.28.1 binary for Linux amd64 from the official GitHub releases page.

On **pg-ops**, as **ec2-user**:

```bash
sudo wget https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz
```

Expected output (yours will differ):
```
--2026-06-18 14:22:10--  https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz
Resolving github.com... 140.82.114.4
Connecting to github.com|140.82.114.4|:443... connected.
HTTP request sent, awaiting response... 302 Found
Location: https://objects.githubusercontent.com/...
HTTP request sent, awaiting response... 200 OK
Length: 36254892 (35M) [application/octet-stream]
Saving to: 'alertmanager-0.28.1.linux-amd64.tar.gz'
alertmanager-0.28.1.linux-amd64.tar.gz    100%[=====>]  34.57M  ...
```

### Step 4: Extract the archive

This unpacks the tarball into a folder named `alertmanager-0.28.1.linux-amd64/`.

On **pg-ops**, as **ec2-user**:

```bash
sudo tar -xzf alertmanager-0.28.1.linux-amd64.tar.gz
```

### Step 5: Rename the extracted folder

This renames the folder to a cleaner name without the OS suffix.

On **pg-ops**, as **ec2-user**:

```bash
sudo mv alertmanager-0.28.1.linux-amd64 alertmanager-0.28.1
```

### Step 6: Create a symlink

The symlink lets you upgrade Alertmanager later by pointing the symlink to a new version without changing the systemd service file.

On **pg-ops**, as **ec2-user**:

```bash
sudo ln -s /opt/prometheus/alertmanager-0.28.1 /opt/prometheus/alertmanager
```

### Step 7: Verify the symlink

On **pg-ops**, as **ec2-user**:

```bash
ls -la /opt/prometheus/ | grep alertmanager
```

Expected output (yours will differ):
```
lrwxrwxrwx 1 root root   41 Jun 18 14:25 alertmanager -> /opt/prometheus/alertmanager-0.28.1
drwxr-xr-x 4 root root 4096 Jun 18 14:24 alertmanager-0.28.1
```

### Step 8: Create the data directory

Alertmanager stores silences and notification log on disk. This directory holds that data so it survives a restart.

On **pg-ops**, as **ec2-user**:

```bash
sudo mkdir -p /opt/prometheus/alertmanager-data
```

### Step 9: Set ownership

The prometheus OS user (which runs the service) needs read/write access to this directory.

On **pg-ops**, as **ec2-user**:

```bash
sudo chown -R prometheus:prometheus /opt/prometheus/alertmanager-0.28.1
sudo chown -R prometheus:prometheus /opt/prometheus/alertmanager-data
sudo chown -R prometheus:prometheus /opt/prometheus/alertmanager
```

### Step 10: Remove the tarball

On **pg-ops**, as **ec2-user**:

```bash
sudo rm /opt/prometheus/alertmanager-0.28.1.linux-amd64.tar.gz
```

### Step 11: Create a placeholder config file

Alertmanager requires a valid config file before it will start. You will replace this with the full config in Section 3. For now, create a minimal version so the service can start.

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/alertmanager.yml
```

Add this content:

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'

receivers:
  - name: 'default'
```

Save and exit: press `Esc`, then type `:wq`, then press `Enter`.

Set ownership on the config file:

```bash
sudo chown prometheus:prometheus /opt/prometheus/alertmanager.yml
```

### Step 12: Create the systemd service file

The systemd service file tells the OS how to start, stop, and restart Alertmanager automatically.

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /etc/systemd/system/alertmanager.service
```

Add this content:

```ini
[Unit]
Description=Alertmanager
Documentation=https://prometheus.io/docs/alerting/latest/alertmanager/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/opt/prometheus/alertmanager \
    --config.file=/opt/prometheus/alertmanager.yml \
    --storage.path=/opt/prometheus/alertmanager-data \
    --web.listen-address=0.0.0.0:9093 \
    --log.level=info
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Each flag explained:
- `--config.file` - path to the alertmanager configuration
- `--storage.path` - where silences and notification state are stored on disk
- `--web.listen-address` - the port Alertmanager listens on (9093 is the standard)
- `--log.level=info` - log level; use `debug` if you need to troubleshoot routing

Save and exit.

### Step 13: Reload systemd and start Alertmanager

Tell systemd to read the new service file:

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl daemon-reload
```

Enable the service so it starts automatically on reboot:

```bash
sudo systemctl enable alertmanager
```

Start the service:

```bash
sudo systemctl start alertmanager
```

### Step 14: Verify Alertmanager is running

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl status alertmanager
```

Expected output (yours will differ):
```
alertmanager.service - Alertmanager
     Loaded: loaded (/etc/systemd/system/alertmanager.service; enabled; preset: disabled)
     Active: active (running) since Wed 2026-06-18 14:30:12 UTC; 8s ago
   Main PID: 18345 (alertmanager)
      Tasks: 7 (limit: 4661)
     Memory: 14.2M
        CPU: 89ms
     CGroup: /system.slice/alertmanager.service
             └─18345 /opt/prometheus/alertmanager ...
```

### Step 15: Verify the web UI is reachable

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9093/-/healthy
```

Expected output:
```
OK
```

You can also open `http://34.228.32.17:9093` in your browser. You should see the Alertmanager UI with an empty alerts list.

---

## Section 3: Configuring Alertmanager

You will now replace the placeholder config with a production-like configuration that has a full routing tree and multiple receivers.

### Understanding the Config Structure

An Alertmanager config has four top-level sections:

- `global` - defaults applied to all receivers (timeouts, SMTP server, etc.)
- `route` - the routing tree that decides which alerts go to which receiver
- `receivers` - the actual notification destinations
- `inhibit_rules` - rules that suppress certain alerts when others are firing

### The Route Tree

The route tree works like a series of if/else conditions. Every alert starts at the root route and travels down until it finds a matching child route. If no child matches, the alert uses the root route's receiver.

```
root route (default receiver)
  |
  +-- severity=critical --> critical receiver (PagerDuty)
  |
  +-- severity=warning  --> warning receiver (Slack)
```

### Step 1: Open the config file for editing

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/alertmanager.yml
```

Replace all existing content with the following. Read the inline comments - each section is explained.

```yaml
# /opt/prometheus/alertmanager.yml

global:
  # How long to wait before declaring an alert resolved if we stop
  # receiving it from Prometheus. 5 minutes is a safe default.
  resolve_timeout: 5m

route:
  # Group alerts by these labels. All alerts with the same values
  # for alertname and cluster will be batched into one notification.
  group_by: ['alertname', 'cluster', 'instance']

  # How long to wait before sending the first notification for a new group.
  # This allows related alerts to arrive and be bundled together.
  group_wait: 30s

  # After the first notification, how long to wait before sending
  # another notification if new alerts join the group.
  group_interval: 5m

  # How long to wait before re-sending a notification for an already
  # firing alert. This prevents alert fatigue from constant repeats.
  repeat_interval: 4h

  # The fallback receiver if no child route matches.
  receiver: 'default'

  # Child routes - evaluated top to bottom. First match wins.
  routes:
    - matchers:
        - severity="critical"
      receiver: 'critical'
      # Critical alerts re-notify every 1 hour (not 4h like default).
      repeat_interval: 1h
      # Stop evaluating further routes after this one matches.
      continue: false

    - matchers:
        - severity="warning"
      receiver: 'warning'
      repeat_interval: 4h
      continue: false

receivers:
  # In production this would be a PagerDuty integration key.
  # For this lab we use a webhook that logs to /dev/null.
  - name: 'critical'
    webhook_configs:
      - url: 'http://localhost:9999/critical'
        send_resolved: true

  # In production this would be a Slack webhook URL.
  - name: 'warning'
    webhook_configs:
      - url: 'http://localhost:9999/warning'
        send_resolved: true

  # The null receiver - accepts alerts and discards them silently.
  # Useful for alerts you want to track in Prometheus but not notify on.
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:9999/default'
        send_resolved: false

inhibit_rules:
  # If a critical alert is firing for a given alertname+instance,
  # suppress any warning alert for the same alertname+instance.
  # This prevents alert storms - if postgres is down, we do not need
  # a separate "too many connections" warning for the same instance.
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ['alertname', 'instance']
```

Save and exit.

### Step 2: Validate the config

Alertmanager ships with `amtool` for checking configs before applying them.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/amtool check-config /opt/prometheus/alertmanager.yml
```

Expected output:
```
Checking '/opt/prometheus/alertmanager.yml'  SUCCESS
Found receivers: 3
Found inhibit rules: 1
```

If you see any errors, re-open the file and fix indentation. YAML is whitespace-sensitive - each level must use exactly 2 spaces, not tabs.

### Step 3: Reload Alertmanager

Send SIGHUP to tell Alertmanager to reload its config without restarting.

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl reload alertmanager
```

Verify the reload worked:

```bash
sudo journalctl -u alertmanager -n 20 --no-pager
```

Expected output (yours will differ):
```
Jun 18 14:45:01 pg-ops alertmanager[18345]: ts=2026-06-18T14:45:01.123Z caller=coordinator.go:113 level=info component=configuration msg="Loading configuration file" file=/opt/prometheus/alertmanager.yml
Jun 18 14:45:01 pg-ops alertmanager[18345]: ts=2026-06-18T14:45:01.145Z caller=coordinator.go:126 level=info component=configuration msg="Completed loading of configuration file" file=/opt/prometheus/alertmanager.yml
```

---

## Section 4: Writing Prometheus Alert Rules

Alert rules live in a separate YAML file. Prometheus loads them via the `rule_files` section of `prometheus.yml`. When a rule's expression evaluates to true, Prometheus fires the alert to Alertmanager.

### Alert Rule Structure

Each rule has:

- `alert` - the alert name (becomes the `alertname` label)
- `expr` - the PromQL expression that must be true for the alert to fire
- `for` - how long the condition must be true before firing (the pending period)
- `labels` - additional labels to attach (like `severity`)
- `annotations` - human-readable descriptions and runbook links

### Step 1: Create the alert rules file

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/alert_rules.yml
```

Add the following content. Each rule is explained inline.

```yaml
# /opt/prometheus/alert_rules.yml

groups:
  - name: postgresql
    interval: 30s
    rules:

      # ----------------------------------------------------------------
      # Rule 1: PostgresDown
      # pg_up is 1 when postgres_exporter can connect to PostgreSQL,
      # and 0 when it cannot. This is the most critical alert.
      # No 'for' clause means it fires immediately (no pending state).
      # ----------------------------------------------------------------
      - alert: PostgresDown
        expr: pg_up == 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down on {{ $labels.instance }}"
          description: "postgres_exporter cannot connect to PostgreSQL on {{ $labels.instance }}. The database may be crashed or the exporter may have lost its connection."
          runbook: "Check: sudo systemctl status postgresql-17 on the affected node."

      # ----------------------------------------------------------------
      # Rule 2: ReplicationLagHigh (warning)
      # pg_stat_replication_pg_wal_lsn_diff measures how many bytes
      # of WAL the replica is behind the primary. 50MB of lag is a
      # soft warning - investigate but not yet an emergency.
      # ----------------------------------------------------------------
      - alert: ReplicationLagHigh
        expr: pg_stat_replication_pg_wal_lsn_diff > 52428800
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag high on {{ $labels.instance }}"
          description: "Replica {{ $labels.application_name }} is {{ $value | humanize1024 }}B behind the primary. Lag has been above 50MB for 5 minutes."
          runbook: "Check replica load, network throughput, and pg_stat_replication on the primary."

      # ----------------------------------------------------------------
      # Rule 3: ReplicationLagCritical
      # 200MB of lag means the replica is significantly behind.
      # If the primary crashes now, you will lose 200MB of transactions
      # on failover (unless synchronous replication is configured).
      # ----------------------------------------------------------------
      - alert: ReplicationLagCritical
        expr: pg_stat_replication_pg_wal_lsn_diff > 209715200
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag critical on {{ $labels.instance }}"
          description: "Replica {{ $labels.application_name }} is {{ $value | humanize1024 }}B behind the primary. RPO is at risk."
          runbook: "Immediate investigation required. Check replica I/O, network, and consider promoting if primary is failing."

      # ----------------------------------------------------------------
      # Rule 4: TooManyConnections
      # pg_settings_max_connections is the configured max_connections.
      # pg_stat_activity_count is the current connection count.
      # At 80% saturation, new connections may be refused under spike load.
      # ----------------------------------------------------------------
      - alert: TooManyConnections
        expr: >
          (sum by (instance) (pg_stat_activity_count) / pg_settings_max_connections) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL connections at {{ $value | humanizePercentage }} on {{ $labels.instance }}"
          description: "Connection pool is over 80% full for 5 minutes. Risk of connection exhaustion."
          runbook: "Check pg_stat_activity for long-running idle connections. Consider pgBouncer or increasing max_connections (requires restart)."

      # ----------------------------------------------------------------
      # Rule 5: DeadTuplesHigh
      # Dead tuples are rows that have been deleted or updated but not
      # yet vacuumed. High dead tuples indicate autovacuum is not keeping
      # up, which causes table bloat and index bloat over time.
      # ----------------------------------------------------------------
      - alert: DeadTuplesHigh
        expr: pg_stat_user_tables_n_dead_tup > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High dead tuple count in {{ $labels.schemaname }}.{{ $labels.relname }} on {{ $labels.instance }}"
          description: "Table {{ $labels.schemaname }}.{{ $labels.relname }} has {{ $value }} dead tuples. Autovacuum may not be keeping up."
          runbook: "Run VACUUM ANALYZE on the table. Check pg_stat_user_tables.last_autovacuum and autovacuum logs."

      # ----------------------------------------------------------------
      # Rule 6: DiskSpaceLow (warning)
      # node_filesystem_avail_bytes is free bytes on the filesystem.
      # node_filesystem_size_bytes is the total capacity.
      # Dividing them gives the free ratio. We exclude tmpfs mounts
      # (fstype!="tmpfs") to avoid noise from in-memory filesystems.
      # ----------------------------------------------------------------
      - alert: DiskSpaceLow
        expr: >
          (
            node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint!~"/boot.*"}
            /
            node_filesystem_size_bytes{fstype!="tmpfs",mountpoint!~"/boot.*"}
          ) < 0.20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low on {{ $labels.instance }} ({{ $labels.mountpoint }})"
          description: "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has less than 20% free space ({{ $value | humanizePercentage }} remaining)."
          runbook: "Check what is consuming space: du -sh /var/lib/pgsql/17/data/*. Consider pg_basebackup cleanup or WAL archiving configuration."

      # ----------------------------------------------------------------
      # Rule 7: DiskSpaceCritical
      # Under 10% free, PostgreSQL may stop writing WAL and crash.
      # The `for: 2m` is short because disk filling is urgent and fast.
      # ----------------------------------------------------------------
      - alert: DiskSpaceCritical
        expr: >
          (
            node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint!~"/boot.*"}
            /
            node_filesystem_size_bytes{fstype!="tmpfs",mountpoint!~"/boot.*"}
          ) < 0.10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Disk space critical on {{ $labels.instance }} ({{ $labels.mountpoint }})"
          description: "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is below 10% free ({{ $value | humanizePercentage }} remaining). PostgreSQL may crash."
          runbook: "IMMEDIATE ACTION: Free disk space or expand volume. PostgreSQL will stop if disk fills completely."

      # ----------------------------------------------------------------
      # Rule 8: HighCPU
      # node_cpu_seconds_total tracks CPU time split by mode. The 'idle'
      # mode is time the CPU spent doing nothing. Subtracting idle from 1
      # gives utilization. rate() calculates the per-second rate over 5m.
      # avg by (instance) collapses all CPU cores into one value per host.
      # ----------------------------------------------------------------
      - alert: HighCPU
        expr: >
          (
            1 - avg by (instance) (
              rate(node_cpu_seconds_total{mode="idle"}[5m])
            )
          ) > 0.80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU utilization on {{ $labels.instance }}"
          description: "CPU utilization on {{ $labels.instance }} has been above 80% for 5 minutes (current: {{ $value | humanizePercentage }})."
          runbook: "Check top or pg_stat_activity for long-running queries. Look for vacuum storms or autovacuum workers."

      # ----------------------------------------------------------------
      # Rule 9: NodeDown
      # The 'up' metric is set automatically by Prometheus for every
      # scrape target. If node_exporter is unreachable, up == 0.
      # This catches complete node failures, not just PostgreSQL failures.
      # ----------------------------------------------------------------
      - alert: NodeDown
        expr: up{job="node"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Node is unreachable: {{ $labels.instance }}"
          description: "node_exporter on {{ $labels.instance }} has been unreachable for 1 minute. The node may be down or the network path may be broken."
          runbook: "Try to ping the instance. Check AWS console for instance state. If node is up but port 9100 is blocked, check security group rules."

      # ----------------------------------------------------------------
      # Rule 10: BgwriterMaxwrittenClean
      # pg_stat_bgwriter_maxwritten_clean_total counts how many times
      # the background writer stopped its cleaning scan because it had
      # already written bgwriter_lru_maxpages buffers. A rising counter
      # means the background writer cannot keep up with dirty pages.
      # ----------------------------------------------------------------
      - alert: BgwriterMaxwrittenClean
        expr: >
          rate(pg_stat_bgwriter_maxwritten_clean_total[5m]) > 0
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Background writer hitting maxpages limit on {{ $labels.instance }}"
          description: "PostgreSQL background writer on {{ $labels.instance }} is repeatedly hitting the bgwriter_lru_maxpages limit. Consider increasing bgwriter_lru_maxpages or bgwriter_lru_multiplier."
          runbook: "Check pg_stat_bgwriter. Consider increasing bgwriter_lru_maxpages in postgresql.conf (requires reload)."
```

Save and exit.

Set correct ownership:

```bash
sudo chown prometheus:prometheus /opt/prometheus/alert_rules.yml
```

### Step 2: Update prometheus.yml to load alert rules

You need to tell Prometheus where to find the alert rules file and where to send fired alerts (Alertmanager).

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/prometheus.yml
```

Add (or update) the `rule_files` and `alerting` sections at the top level alongside `global` and `scrape_configs`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 30s

# Tell Prometheus where Alertmanager is running.
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - 'localhost:9093'

# Tell Prometheus which files contain alert and recording rules.
rule_files:
  - '/opt/prometheus/alert_rules.yml'
  - '/opt/prometheus/recording_rules.yml'

scrape_configs:
  # ... your existing scrape jobs remain here unchanged ...
```

Important: only add the `alerting` and `rule_files` sections. Do not remove or change your existing `scrape_configs`. Save and exit.

### Step 3: Validate the alert rules with promtool

`promtool` is a utility bundled with Prometheus. The `check rules` subcommand validates that the rule syntax is correct and all PromQL expressions are parseable before you apply them to a live instance.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check rules /opt/prometheus/alert_rules.yml
```

Expected output:
```
Checking /opt/prometheus/alert_rules.yml
  SUCCESS: 10 rules found
```

If you see errors, the output will point to the specific line. Fix the indentation and run again.

### Step 4: Validate the full prometheus.yml

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check config /opt/prometheus/prometheus.yml
```

Expected output:
```
Checking /opt/prometheus/prometheus.yml
  SUCCESS: 1 rule files found
 > Checking /opt/prometheus/alert_rules.yml
  SUCCESS: 10 rules found
```

### Step 5: Reload Prometheus

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl reload prometheus
```

Wait 5 seconds, then verify the reload succeeded:

```bash
sudo journalctl -u prometheus -n 15 --no-pager
```

Expected output (yours will differ):
```
Jun 18 14:55:01 pg-ops prometheus[12301]: ts=2026-06-18T14:55:01Z caller=main.go:1067 level=info msg="Loading configuration file" filename=/opt/prometheus/prometheus.yml
Jun 18 14:55:01 pg-ops prometheus[12301]: ts=2026-06-18T14:55:01Z caller=main.go:1101 level=info msg="Completed loading of configuration file" filename=/opt/prometheus/prometheus.yml
```

---

## Section 5: Testing Alerts

### Step 1: Verify all rules loaded in Prometheus

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | head -60
```

Expected output (yours will differ):
```json
{
    "status": "success",
    "data": {
        "groups": [
            {
                "name": "postgresql",
                "interval": 30,
                "rules": [
                    {
                        "name": "PostgresDown",
                        "type": "alerting",
                        "state": "inactive",
                        ...
                    },
```

You should see all 10 alert rules listed with state `"inactive"` (meaning their conditions are currently false - which is good).

### Step 2: Check the Prometheus alerts page

Open `http://34.228.32.17:9090/alerts` in your browser.

You should see all 10 rules listed. All should show as `0 active` in green. This confirms the rules loaded correctly.

### Step 3: Trigger a test alert by stopping postgres_exporter

You will temporarily stop postgres_exporter on pg-primary, which causes the `PostgresDown` alert to fire. This lets you watch the full alert lifecycle in real time.

Open a second terminal and SSH into pg-primary:

```bash
ssh -i your-key.pem ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user** - stop the exporter:

```bash
sudo systemctl stop postgres_exporter
```

This stops the exporter process. Prometheus will attempt to scrape it at the next interval and receive a connection refused error, which sets `pg_up` to 0.

Wait 30 seconds. Then on your **pg-ops terminal**, check the Prometheus alerts page at `http://34.228.32.17:9090/alerts`.

You should see `PostgresDown` change from `inactive` to `firing`. Because the rule has `for: 0m`, it goes straight to firing with no pending state.

### Step 4: Check Alertmanager received the alert

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool
```

Expected output (yours will differ):
```json
[
    {
        "annotations": {
            "description": "postgres_exporter cannot connect to PostgreSQL ...",
            "runbook": "Check: sudo systemctl status postgresql-17 ...",
            "summary": "PostgreSQL is down on 100.26.54.122:9187"
        },
        "labels": {
            "alertname": "PostgresDown",
            "instance": "100.26.54.122:9187",
            "severity": "critical"
        },
        "status": {
            "state": "active",
            ...
        }
    }
]
```

You can also see the alert in the Alertmanager UI at `http://34.228.32.17:9093`.

### Step 5: Silence the alert in the UI

Silences are useful during maintenance windows. Practice creating one now.

1. Open `http://34.228.32.17:9093` in your browser
2. Click on the `PostgresDown` alert
3. Click **Silence** in the top right of the alert panel
4. Set a duration of 1 hour
5. Add a comment: "Testing silence functionality - lab exercise"
6. Add your name as creator
7. Click **Create**

The alert moves to the **Silenced** tab. It is still firing in Prometheus, but Alertmanager will not send notifications while the silence is active.

### Step 6: Restore postgres_exporter

Switch back to your **pg-primary terminal**.

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl start postgres_exporter
```

Verify it is running:

```bash
sudo systemctl status postgres_exporter | head -5
```

Expected output (yours will differ):
```
  postgres_exporter.service - Prometheus PostgreSQL Exporter
     Loaded: loaded (...)
     Active: active (running) since Wed 2026-06-18 15:05:22 UTC; 3s ago
...
```

Exit pg-primary:

```bash
exit
```

Within 30-60 seconds, Prometheus detects that `pg_up` is back to 1 and the alert resolves. In the Alertmanager UI, the alert disappears from the active list.

### Step 7: Expire the silence

Back in the Alertmanager UI, click the **Silences** tab. Find the silence you created and click **Expire** to remove it immediately rather than waiting for the 1-hour duration.

### Step 8: Check alert state via API

On **pg-ops**, as **ec2-user**:

```bash
curl -s 'http://localhost:9090/api/v1/alerts' | python3 -m json.tool
```

When no alerts are firing, you will see:

```json
{
    "status": "success",
    "data": {
        "alerts": []
    }
}
```

---

## Section 6: Recording Rules for Performance

### What Recording Rules Are

Recording rules pre-compute frequently used PromQL expressions and save the result as a new metric. Instead of computing a complex expression every time a dashboard panel loads, Prometheus computes it once per evaluation interval and stores the result.

Benefits:
- Dashboard queries run in milliseconds instead of seconds
- Reduces CPU load on Prometheus for complex aggregations
- Creates cleaner metric names that are easier to reference in alerts

The naming convention for recording rules is `level:metric:operation`. For example, `node:cpu_utilization:ratio` means "at the node level, the cpu_utilization metric, expressed as a ratio".

### Step 1: Create the recording rules file

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/recording_rules.yml
```

Add the following content:

```yaml
# /opt/prometheus/recording_rules.yml

groups:
  - name: node_recordings
    interval: 60s
    rules:

      # Pre-compute CPU utilization as a ratio (0 to 1).
      # This averages across all CPU cores per instance.
      # Without this rule, dashboards compute the full rate() expression
      # on every panel load. With this rule, they just query
      # node:cpu_utilization:ratio directly.
      - record: node:cpu_utilization:ratio
        expr: >
          1 - avg by (instance) (
            rate(node_cpu_seconds_total{mode="idle"}[5m])
          )

      # Pre-compute disk usage as a ratio (0 to 1) per instance and mountpoint.
      # Grafana disk panels can query this instead of dividing two raw metrics.
      - record: node:disk_usage:ratio
        expr: >
          1 - (
            node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint!~"/boot.*"}
            /
            node_filesystem_size_bytes{fstype!="tmpfs",mountpoint!~"/boot.*"}
          )

  - name: postgresql_recordings
    interval: 60s
    rules:

      # Pre-compute connection usage as a ratio (0 to 1).
      # Dashboard panels display this as a percentage gauge without
      # needing to know max_connections at query time.
      - record: pg:connections_usage:ratio
        expr: >
          sum by (instance) (pg_stat_activity_count) / pg_settings_max_connections

      # Pre-compute replication lag in bytes under a cleaner metric name.
      # Alert rules and dashboards reference this instead of the raw
      # pg_stat_replication_pg_wal_lsn_diff metric with its long name.
      - record: pg:replication_lag:bytes
        expr: >
          pg_stat_replication_pg_wal_lsn_diff
```

Save and exit.

Set correct ownership:

```bash
sudo chown prometheus:prometheus /opt/prometheus/recording_rules.yml
```

### Step 2: Validate the recording rules

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check rules /opt/prometheus/recording_rules.yml
```

Expected output:
```
Checking /opt/prometheus/recording_rules.yml
  SUCCESS: 4 rules found
```

### Step 3: Verify prometheus.yml references both files

The `rule_files` section you added in Section 4 already includes the recording rules path. Confirm it is there:

On **pg-ops**, as **ec2-user**:

```bash
grep -A5 'rule_files' /opt/prometheus/prometheus.yml
```

Expected output:
```yaml
rule_files:
  - '/opt/prometheus/alert_rules.yml'
  - '/opt/prometheus/recording_rules.yml'
```

If the recording_rules.yml line is missing, add it now:

```bash
sudo vi /opt/prometheus/prometheus.yml
```

### Step 4: Reload Prometheus

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl reload prometheus
```

Wait 5 seconds, then verify the recording rules are producing data:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=node:cpu_utilization:ratio' | python3 -m json.tool | head -30
```

Expected output (yours will differ - values depend on actual CPU load):
```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "node:cpu_utilization:ratio",
                    "instance": "172.31.19.86:9100"
                },
                "value": [1718718600, "0.0234"]
            },
```

The value `0.0234` means 2.34% CPU utilization on that instance. If the query returns results, the recording rule is working.

---

## Section 7: Alertmanager Operations

### amtool - The Command Line Interface for Alertmanager

`amtool` is bundled with Alertmanager. It lets you inspect and manage Alertmanager from the command line, which is useful for scripting and automation.

All `amtool` commands run on **pg-ops** as **ec2-user**.

Set the Alertmanager URL so you do not have to type it with every command:

```bash
export ALERTMANAGER_URL=http://localhost:9093
```

### Check the Alertmanager Config

This re-validates the config file and shows a summary of what was loaded.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/amtool check-config /opt/prometheus/alertmanager.yml
```

Expected output:
```
Checking '/opt/prometheus/alertmanager.yml'  SUCCESS
Found receivers: 3
Found inhibit rules: 1
```

### List Active Alerts

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/amtool --alertmanager.url=http://localhost:9093 alert
```

When no alerts are firing, the output will be empty. When alerts are firing, you will see a table like:

```
Alertname          Starts At                Summary
PostgresDown       2026-06-18 15:30:00 UTC  PostgreSQL is down on 100.26.54.122:9187
```

### Create a Silence from the CLI

This is the CLI equivalent of the silence you created in the UI. It is useful for scripts that create silences automatically before maintenance windows.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/amtool \
  --alertmanager.url=http://localhost:9093 \
  silence add \
  --author="ec2-user" \
  --comment="Manual maintenance window" \
  --duration="2h" \
  alertname="PostgresDown"
```

This creates a 2-hour silence that suppresses any `PostgresDown` alert. The command prints the silence ID.

Expected output (yours will differ):
```
b3f8a7c2-1234-5678-abcd-ef0123456789
```

### List Active Silences

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/amtool \
  --alertmanager.url=http://localhost:9093 \
  silence query
```

Expected output (yours will differ):
```
ID                                    Matchers               Ends At                  Created By  Comment
b3f8a7c2-1234-5678-abcd-ef0123456789  alertname=PostgresDown  2026-06-18 17:30:00 UTC  ec2-user    Manual maintenance window
```

### Expire a Silence

Use the silence ID from the list above.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/amtool \
  --alertmanager.url=http://localhost:9093 \
  silence expire b3f8a7c2-1234-5678-abcd-ef0123456789
```

Replace `b3f8a7c2-1234-5678-abcd-ef0123456789` with the actual ID from your output.

### Alertmanager API Endpoints for Automation

The Alertmanager HTTP API is what tools and scripts use to integrate programmatically. All endpoints accept and return JSON.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | /-/healthy | Health check - returns 200 OK if running |
| GET | /-/ready | Readiness check - returns 200 OK when ready |
| POST | /-/reload | Reload config (same as SIGHUP) |
| GET | /api/v2/alerts | List all active alerts |
| POST | /api/v2/alerts | Push custom alerts directly to Alertmanager |
| GET | /api/v2/silences | List all silences |
| POST | /api/v2/silences | Create a new silence |
| GET | /api/v2/silences/{id} | Get a specific silence |
| DELETE | /api/v2/silences/{id} | Expire a silence |

### Example: Push a Custom Alert via API

You can inject alerts directly into Alertmanager from scripts, bypassing Prometheus entirely. This is useful for infrastructure events from tools that do not expose Prometheus metrics.

On **pg-ops**, as **ec2-user**:

```bash
curl -s -X POST http://localhost:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[
    {
      "labels": {
        "alertname": "TestAlert",
        "severity": "warning",
        "instance": "pg-ops:9093"
      },
      "annotations": {
        "summary": "This is a test alert injected via API",
        "description": "This alert was pushed directly to Alertmanager from a curl command."
      },
      "generatorURL": "http://localhost:9090"
    }
  ]'
```

Check the Alertmanager UI to see the `TestAlert` appear. It will auto-resolve after `resolve_timeout` (5 minutes) because no Prometheus rule is continuously sending it.

### Webhook Receiver Pattern for Production

In this lab, the receivers point to `http://localhost:9999/...` which does not exist, so notifications are silently dropped. In a real environment you would replace these with actual endpoints.

For a Slack integration, the receiver would look like:

```yaml
receivers:
  - name: 'warning'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#database-alerts'
        send_resolved: true
        title: '{{ .CommonAnnotations.summary }}'
        text: '{{ .CommonAnnotations.description }}'
```

For PagerDuty:

```yaml
receivers:
  - name: 'critical'
    pagerduty_configs:
      - routing_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'
        description: '{{ .CommonAnnotations.summary }}'
        severity: '{{ .CommonLabels.severity }}'
```

For a custom webhook (your own service that receives JSON):

```yaml
receivers:
  - name: 'custom'
    webhook_configs:
      - url: 'https://your-service.com/api/alerts'
        send_resolved: true
        http_config:
          authorization:
            credentials: 'your-api-token'
```

---

## Summary: What You Built

You now have a complete alerting pipeline:

| Component | Location | Port | Purpose |
|-----------|----------|------|---------|
| Alertmanager | pg-ops | 9093 | Receives alerts, routes to receivers |
| Alert rules | /opt/prometheus/alert_rules.yml | - | 10 rules covering PostgreSQL, disk, CPU, nodes |
| Recording rules | /opt/prometheus/recording_rules.yml | - | 4 pre-computed metrics for dashboard performance |

### Key Files

| File | Purpose |
|------|---------|
| /opt/prometheus/alertmanager.yml | Alertmanager config - routing tree and receivers |
| /opt/prometheus/alert_rules.yml | Alert rule definitions for Prometheus |
| /opt/prometheus/recording_rules.yml | Pre-computed metric definitions |
| /etc/systemd/system/alertmanager.service | Systemd service definition |
| /opt/prometheus/alertmanager-data/ | Alertmanager persistence (silences, notification log) |

### How to Verify Everything is Working

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl status prometheus | grep Active
sudo systemctl status alertmanager | grep Active
```

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep '"name"' | head -15
```

```bash
curl -s http://localhost:9093/-/healthy
```

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool
```

---

*BUILD-13 complete. Alertmanager is running, alert rules are loaded, and the alerting pipeline is tested end-to-end.*
