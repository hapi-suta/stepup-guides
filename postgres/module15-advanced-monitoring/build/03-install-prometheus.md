# Build Guide 03 - Install Prometheus

**Module:** 15 - Advanced Monitoring
**Node:** pg-primary
**Time:** ~25 minutes

---

## Overview

Prometheus is a time-series monitoring system. It works on a pull model - instead of your applications pushing data to a central server, Prometheus regularly reaches out (scrapes) to each monitored target and pulls the current metrics. Each scrape is timestamped and stored in Prometheus's local time-series database.

In this guide you will install Prometheus 2.51.0, configure it to scrape postgres_exporter, and verify that PostgreSQL metrics are flowing into the Prometheus database.

---

## Step 1 - Log in to pg-primary

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

---

## Step 2 - Download Prometheus

```bash
curl -L -o /tmp/prometheus.tar.gz \
  https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz
```

Expected output (yours will differ):

```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  105M  100  105M    0     0  8234k      0  0:00:13  0:00:13 --:--:--  9102k
```

---

## Step 3 - Extract the archive

```bash
tar -xzf /tmp/prometheus.tar.gz -C /tmp/
```

---

## Step 4 - Move the binaries to /usr/local/bin

Prometheus ships with two binaries: `prometheus` (the main server) and `promtool` (a command-line utility for checking configuration files and running queries).

```bash
sudo mv /tmp/prometheus-2.51.0.linux-amd64/prometheus /usr/local/bin/
sudo mv /tmp/prometheus-2.51.0.linux-amd64/promtool /usr/local/bin/
```

```bash
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool
```

---

## Step 5 - Verify the binary

```bash
/usr/local/bin/prometheus --version
```

Expected output (yours will differ):

```
prometheus, version 2.51.0 (branch: HEAD, revision: abc1234)
  build user:       root@buildmachine
  build date:       20240301-12:00:00
  go version:       go1.21.8
  platform:         linux/amd64
```

---

## Step 6 - Create the prometheus OS user

```bash
sudo useradd --system --no-create-home --shell /sbin/nologin prometheus
```

---

## Step 7 - Create directories for Prometheus

Prometheus needs a directory for its configuration file and a separate directory for its data (the time-series database). Keeping data separate makes it easier to manage retention and disk space.

```bash
sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus
```

---

## Step 8 - Copy the default console libraries (optional but useful)

These are web UI assets that ship with Prometheus. Copy them so the built-in UI works fully.

```bash
sudo cp -r /tmp/prometheus-2.51.0.linux-amd64/consoles /etc/prometheus/
sudo cp -r /tmp/prometheus-2.51.0.linux-amd64/console_libraries /etc/prometheus/
```

---

## Step 9 - Set ownership on the directories

The `prometheus` OS user needs to read its config and write to the data directory.

```bash
sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown -R prometheus:prometheus /var/lib/prometheus
```

---

## Step 10 - Create the Prometheus configuration file

This is the main config file. The `global` section sets defaults that apply to all scrape jobs. The `scrape_configs` section lists the targets Prometheus will pull metrics from.

```bash
sudo vi /etc/prometheus/prometheus.yml
```

Add this content:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

  external_labels:
    environment: 'lab'
    instance: 'pg-primary'

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']
    metrics_path: /metrics
    scrape_interval: 15s
    params:
      collect[]:
        - stat_statements
        - postmaster
```

**What each section means:**
- `scrape_interval: 15s` - pull metrics from each target every 15 seconds
- `evaluation_interval: 15s` - check alert rules every 15 seconds
- `external_labels` - labels added to every metric, useful for filtering in Grafana
- `rule_files` - directory where alert rule files will live (you'll create these in Guide 05)
- `job_name: 'prometheus'` - Prometheus monitors itself
- `job_name: 'postgres'` - scrapes postgres_exporter on port 9187

Save and close the file.

---

## Step 11 - Create the rules directory

Prometheus needs this directory to exist even if it is empty for now.

```bash
sudo mkdir -p /etc/prometheus/rules
sudo chown -R prometheus:prometheus /etc/prometheus/rules
```

---

## Step 12 - Validate the configuration file

`promtool` checks your YAML for syntax errors and validates the configuration before you start the service.

```bash
sudo -u prometheus /usr/local/bin/promtool check config /etc/prometheus/prometheus.yml
```

Expected output (yours will differ):

```
Checking /etc/prometheus/prometheus.yml
  SUCCESS: 0 rule files found
```

If you see any errors, re-open the file with `vi` and fix the YAML formatting.

---

## Step 13 - Create the systemd service unit

```bash
sudo vi /etc/systemd/system/prometheus.service
```

Add this content:

```ini
[Unit]
Description=Prometheus Monitoring System
After=network.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.listen-address=:9090 \
  --web.enable-lifecycle \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.console.templates=/etc/prometheus/consoles
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**What the flags mean:**
- `--config.file` - path to prometheus.yml
- `--storage.tsdb.path` - where to store the time-series data on disk
- `--storage.tsdb.retention.time=30d` - keep 30 days of data, then delete old blocks
- `--web.listen-address=:9090` - the Prometheus HTTP UI and API listen on port 9090
- `--web.enable-lifecycle` - allows reloading config via HTTP POST without restarting the process

Save and close the file.

---

## Step 14 - Reload systemd and enable the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable prometheus
```

Expected output (yours will differ):

```
Created symlink /etc/systemd/system/multi-user.target.wants/prometheus.service -> /etc/systemd/system/prometheus.service.
```

---

## Step 15 - Start Prometheus

```bash
sudo systemctl start prometheus
```

---

## Step 16 - Check the service status

```bash
sudo systemctl status prometheus
```

Expected output (yours will differ):

```
● prometheus.service - Prometheus Monitoring System
     Loaded: loaded (/etc/systemd/system/prometheus.service; enabled; preset: disabled)
     Active: active (running) since Tue 2024-03-01 14:30:00 UTC; 5s ago
   Main PID: 13456 (prometheus)
      Tasks: 7 (limit: 4915)
     Memory: 52.1M
        CPU: 0.341s
     CGroup: /system.slice/prometheus.service
             └─13456 /usr/local/bin/prometheus ...
```

---

## Step 17 - Check Prometheus logs if the service failed

```bash
sudo journalctl -u prometheus -n 50 --no-pager
```

---

## Step 18 - Verify Prometheus is listening on port 9090

```bash
ss -tlnp | grep 9090
```

Expected output (yours will differ):

```
LISTEN 0      128          0.0.0.0:9090      0.0.0.0:*    users:(("prometheus",pid=13456,fd=7))
```

---

## Step 19 - Check the Prometheus API health endpoint

```bash
curl -s http://localhost:9090/-/healthy
```

Expected output (yours will differ):

```
Prometheus Server is Healthy.
```

---

## Step 20 - Check that Prometheus can see its targets

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A5 '"health"'
```

Expected output (yours will differ):

```
            "health": "up",
            "lastError": "",
            "lastScrape": "2024-03-01T14:30:15Z",
            "lastScrapeDuration": 0.012345,
            "scrapeInterval": "15s",
```

Both the `prometheus` and `postgres` jobs should show `"health": "up"`. If `postgres` shows `"health": "down"`, check that postgres_exporter is still running with `sudo systemctl status postgres_exporter`.

---

## Step 21 - Run a test PromQL query

PromQL is Prometheus's query language. This query asks for the current number of PostgreSQL connections grouped by state.

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_activity_count' | python3 -m json.tool | head -40
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "pg_stat_activity_count",
                    "datname": "postgres",
                    "instance": "localhost:9187",
                    "job": "postgres",
                    "state": "idle"
                },
                "value": [
                    1709301015.123,
                    "3"
                ]
            },
```

Seeing data here confirms the full pipeline: PostgreSQL - postgres_exporter - Prometheus is working.

---

## Step 22 - Access the Prometheus web UI

Open a browser and navigate to:

```
http://<your-server-ip>:9090
```

Click **Status > Targets** in the top navigation. You should see two rows - one for `prometheus` and one for `postgres` - both with a green `UP` badge.

If you cannot reach the UI from your browser, check that port 9090 is open in your AWS security group. Add an inbound rule: `TCP port 9090, source: My IP`.

---

## Summary

You have:
- Installed Prometheus 2.51.0 from the official release
- Created a dedicated `prometheus` OS user and data directory
- Configured Prometheus to scrape postgres_exporter every 15 seconds
- Validated the configuration with `promtool`
- Confirmed both Prometheus and the postgres job are UP

In the next guide you will install Grafana and build your first PostgreSQL dashboard.
