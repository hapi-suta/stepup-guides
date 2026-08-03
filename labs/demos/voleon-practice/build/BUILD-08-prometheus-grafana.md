# Build Guide 08: Prometheus and Grafana Monitoring

| | |
|---|---|
| **Time** | 75 minutes |
| **Server** | pg-ops (54.209.143.137) for Prometheus + Grafana; pg-primary (3.90.199.62), pg-replica (3.91.32.84), pg-container (34.235.89.112) for exporters |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn

- How Voleon's monitoring stack fits together (Prometheus, exporters, Grafana)
- How to install and start `node_exporter` on every server so you can track CPU, memory, and disk
- How to install and configure `postgres_exporter` on your PostgreSQL servers
- How to install Prometheus on pg-ops and configure it to scrape all exporters
- How to install Grafana and connect it to Prometheus as a data source
- How to build a basic dashboard with PostgreSQL and system metrics

## Prerequisites

- You have completed BUILD-01 through BUILD-07
- PostgreSQL 17 is running on pg-primary and pg-replica with the `quantdb` database
- The `quant_readonly` role exists in PostgreSQL (created in an earlier guide)
- Port 9100, 9187, 9090, and 3000 are open in your security groups for pg-ops
- Port 9100 and 9187 are open on pg-primary and pg-replica (at minimum for pg-ops to scrape them)

---

## Step 1: Understand the Monitoring Stack

The monitoring stack has three layers:

**Exporters** run on each managed server. They expose metrics as a plain-text HTTP endpoint. Two exporters matter here:
- `node_exporter` runs on every server and exposes OS-level metrics: CPU usage, memory, disk I/O, network traffic
- `postgres_exporter` runs on PostgreSQL servers and exposes database metrics: connection counts, replication lag, tuple stats, lock waits

**Prometheus** runs on pg-ops. It is a time-series database. Every few seconds it "scrapes" each exporter's HTTP endpoint and stores the numbers. You configure Prometheus with a list of targets (host:port pairs) and it handles the rest.

**Grafana** runs on pg-ops. It connects to Prometheus as a data source and lets you build dashboards by writing PromQL queries (Prometheus query language) and choosing chart types.

---

## Step 2: Install node_exporter on pg-primary

You will install node_exporter on each server separately. Start with pg-primary.

SSH into pg-primary from your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user** - download node_exporter:

```bash
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
```

`curl -L` follows HTTP redirects (GitHub uses them). `-O` saves the file using the remote filename.

Extract the archive:

```bash
tar xzf node_exporter-1.9.1.linux-amd64.tar.gz
```

`tar xzf` extracts (`x`) a gzip-compressed (`z`) archive from the file (`f`). This creates a directory named `node_exporter-1.9.1.linux-amd64/`.

Move the binary to a system-wide location:

```bash
sudo mv node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/
```

Verify the binary works:

```bash
/usr/local/bin/node_exporter --version
```

Expected output (yours will differ):

```
node_exporter, version 1.9.1 (branch: HEAD, revision: ...)
  build user:       root@...
  build date:       ...
  go version:       go1.22.x
  platform:         linux/amd64
```

Create the systemd service file so node_exporter starts automatically and restarts if it crashes:

```bash
sudo vi /etc/systemd/system/node_exporter.service
```

Enter the following:

```ini
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=ec2-user
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

- `After=network.target` tells systemd to start this service only after the network is up
- `Restart=on-failure` restarts the process automatically if it exits with a non-zero code
- `WantedBy=multi-user.target` means the service will start on normal system boot

Save and exit vi.

Reload systemd so it sees the new service file, then start and enable it:

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start node_exporter
```

```bash
sudo systemctl enable node_exporter
```

`daemon-reload` tells systemd to re-read its service files. `enable` makes the service start automatically on every boot.

Verify node_exporter is running and exposing metrics:

```bash
curl http://localhost:9100/metrics | head -10
```

Expected output (yours will differ):

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 4.5e-05
go_gc_duration_seconds{quantile="0.25"} 6.3e-05
...
```

---

## Step 3: Install node_exporter on pg-replica

Leave pg-primary and SSH into pg-replica from your local machine:

```bash
exit
```

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

On **pg-replica**, as **ec2-user** - run the exact same steps as pg-primary:

```bash
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
```

```bash
tar xzf node_exporter-1.9.1.linux-amd64.tar.gz
```

```bash
sudo mv node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/
```

```bash
sudo vi /etc/systemd/system/node_exporter.service
```

Enter the same service file content as Step 2. Save and exit vi.

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start node_exporter
```

```bash
sudo systemctl enable node_exporter
```

Verify:

```bash
curl http://localhost:9100/metrics | head -5
```

Expected output (yours will differ):

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
...
```

---

## Step 4: Install node_exporter on pg-container

Leave pg-replica and SSH into pg-container:

```bash
exit
```

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

On **pg-container**, as **ec2-user**:

```bash
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
```

```bash
tar xzf node_exporter-1.9.1.linux-amd64.tar.gz
```

```bash
sudo mv node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/
```

```bash
sudo vi /etc/systemd/system/node_exporter.service
```

Enter the same service file content. Save and exit vi.

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start node_exporter
```

```bash
sudo systemctl enable node_exporter
```

Verify:

```bash
curl http://localhost:9100/metrics | head -5
```

Leave pg-container:

```bash
exit
```

---

## Step 5: Install postgres_exporter on pg-primary

SSH into pg-primary:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

On **pg-primary**, as **ec2-user** - download postgres_exporter:

```bash
curl -LO https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.0/postgres_exporter-0.17.0.linux-amd64.tar.gz
```

Extract it:

```bash
tar xzf postgres_exporter-0.17.0.linux-amd64.tar.gz
```

Move the binary:

```bash
sudo mv postgres_exporter-0.17.0.linux-amd64/postgres_exporter /usr/local/bin/
```

Verify:

```bash
/usr/local/bin/postgres_exporter --version
```

Expected output (yours will differ):

```
postgres_exporter version 0.17.0 (branch: HEAD, revision: ...)
```

Create the environment file. This tells postgres_exporter how to connect to PostgreSQL. It uses the `quant_readonly` role which already exists in your database.

```bash
sudo vi /etc/default/postgres_exporter
```

Enter the following:

```bash
DATA_SOURCE_NAME="postgresql://quant_readonly:quant_readonly_2026@localhost:5432/quantdb?sslmode=disable"
```

- `DATA_SOURCE_NAME` is the environment variable postgres_exporter reads at startup
- Using a read-only role is a security best practice - the exporter only needs to SELECT from system views
- `sslmode=disable` is acceptable here because the connection is local (loopback)

Save and exit vi.

Set permissions on the env file so the credentials are not world-readable:

```bash
sudo chmod 640 /etc/default/postgres_exporter
```

Create the systemd service:

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

Enter the following:

```ini
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql-17.service

[Service]
Type=simple
User=ec2-user
EnvironmentFile=/etc/default/postgres_exporter
ExecStart=/usr/local/bin/postgres_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

- `After=postgresql-17.service` ensures postgres_exporter starts after PostgreSQL is up
- `EnvironmentFile` loads the `DATA_SOURCE_NAME` variable from the file you just created

Save and exit vi.

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start postgres_exporter
```

```bash
sudo systemctl enable postgres_exporter
```

Verify:

```bash
curl http://localhost:9187/metrics | head -10
```

Expected output (yours will differ):

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
...
# HELP pg_stat_activity_count number of connections in this state
# TYPE pg_stat_activity_count gauge
pg_stat_activity_count{datname="quantdb",state="active"} 1
...
```

Leave pg-primary:

```bash
exit
```

---

## Step 6: Install postgres_exporter on pg-replica

SSH into pg-replica:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

On **pg-replica**, as **ec2-user**:

```bash
curl -LO https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.0/postgres_exporter-0.17.0.linux-amd64.tar.gz
```

```bash
tar xzf postgres_exporter-0.17.0.linux-amd64.tar.gz
```

```bash
sudo mv postgres_exporter-0.17.0.linux-amd64/postgres_exporter /usr/local/bin/
```

```bash
sudo vi /etc/default/postgres_exporter
```

Enter the same content as Step 5:

```bash
DATA_SOURCE_NAME="postgresql://quant_readonly:quant_readonly_2026@localhost:5432/quantdb?sslmode=disable"
```

Save and exit vi.

```bash
sudo chmod 640 /etc/default/postgres_exporter
```

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

Enter the same service file content as Step 5. Save and exit vi.

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start postgres_exporter
```

```bash
sudo systemctl enable postgres_exporter
```

Verify:

```bash
curl http://localhost:9187/metrics | head -5
```

Leave pg-replica:

```bash
exit
```

---

## Step 7: Install Prometheus on pg-ops

SSH into pg-ops:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

On **pg-ops**, as **ec2-user** - download Prometheus:

```bash
curl -LO https://github.com/prometheus/prometheus/releases/download/v3.4.1/prometheus-3.4.1.linux-amd64.tar.gz
```

Extract it:

```bash
tar xzf prometheus-3.4.1.linux-amd64.tar.gz
```

Create the installation directory:

```bash
sudo mkdir -p /opt/prometheus
```

Move all Prometheus files into it:

```bash
sudo mv prometheus-3.4.1.linux-amd64/* /opt/prometheus/
```

Verify the binary works:

```bash
/opt/prometheus/prometheus --version
```

Expected output (yours will differ):

```
prometheus, version 3.4.1 (branch: HEAD, revision: ...)
  build user:       root@...
  build date:       ...
  go version:       go1.22.x
  platform:         linux/amd64
```

---

## Step 8: Configure Prometheus Scrape Targets

The `prometheus.yml` file tells Prometheus which targets to scrape and how often.

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/prometheus.yml
```

Replace the entire file content with the following:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "node"
    static_configs:
      - targets:
          - "172.31.19.86:9100"
          - "172.31.22.69:9100"
          - "172.31.21.45:9100"
          - "172.31.26.19:9100"
        labels:
          env: "voleon-cbus"

  - job_name: "postgres"
    static_configs:
      - targets:
          - "172.31.19.86:9187"
          - "172.31.22.69:9187"
        labels:
          env: "voleon-cbus"
```

Key points:
- `scrape_interval: 15s` means Prometheus polls each target every 15 seconds
- The `node` job scrapes `node_exporter` (port 9100) on all four servers including pg-ops itself (172.31.26.19)
- The `postgres` job scrapes `postgres_exporter` (port 9187) only on pg-primary and pg-replica
- Private IPs are used because all servers are in the same VPC
- `labels` attach extra key-value metadata to every metric from these targets, useful for filtering in Grafana

Save and exit vi.

---

## Step 9: Create the Prometheus Systemd Service

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /etc/systemd/system/prometheus.service
```

Enter the following:

```ini
[Unit]
Description=Prometheus Monitoring System
After=network.target

[Service]
Type=simple
User=ec2-user
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.listen-address=0.0.0.0:9090
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

- `--config.file` points to the config you just wrote
- `--storage.tsdb.path` is where Prometheus stores its time-series data on disk
- `--web.listen-address=0.0.0.0:9090` makes the Prometheus web UI available on port 9090 from any IP

Save and exit vi.

Create the data directory:

```bash
sudo mkdir -p /opt/prometheus/data
sudo chown ec2-user:ec2-user /opt/prometheus/data
```

Apply the SELinux file context so systemd can execute files from `/opt/prometheus/`:

```bash
sudo restorecon -Rv /opt/prometheus/
```

`restorecon` resets SELinux security labels to their defaults. Without this, SELinux may block systemd from starting the binary.

Expected output (yours will differ):

```
Relabeled /opt/prometheus/prometheus from unconfined_u:object_r:default_t:s0 to ...
```

Start and enable Prometheus:

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start prometheus
```

```bash
sudo systemctl enable prometheus
```

Verify Prometheus is running and can reach its targets:

```bash
curl http://localhost:9090/api/v1/targets | python3 -m json.tool | head -40
```

`python3 -m json.tool` pretty-prints JSON output so it is readable in the terminal.

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "activeTargets": [
            {
                "discoveredLabels": {
                    "__address__": "172.31.19.86:9100",
                    "__metrics_path__": "/metrics",
                    ...
                },
                "health": "up",
                ...
            },
```

Look for `"health": "up"` for each target. If a target shows `"health": "down"`, check that the exporter is running on that server and that the security group allows Prometheus to reach that port.

---

## Step 10: Also Install node_exporter on pg-ops

pg-ops itself should be monitored too. The Prometheus config already includes 172.31.26.19:9100 as a target, so you just need to install the exporter here.

Still on **pg-ops**, as **ec2-user**:

```bash
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
```

```bash
tar xzf node_exporter-1.9.1.linux-amd64.tar.gz
```

```bash
sudo mv node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/
```

```bash
sudo vi /etc/systemd/system/node_exporter.service
```

Enter the same service file content used in Step 2. Save and exit vi.

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl start node_exporter
```

```bash
sudo systemctl enable node_exporter
```

```bash
curl http://localhost:9100/metrics | head -5
```

---

## Step 11: Install Grafana on pg-ops

Still on **pg-ops**, as **ec2-user** - add the Grafana repository:

```bash
sudo vi /etc/yum.repos.d/grafana.repo
```

Enter the following:

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

This adds the official Grafana RPM repository. `gpgcheck=1` verifies package signatures before installing.

Save and exit vi.

Install Grafana:

```bash
sudo dnf install -y grafana
```

Expected output (yours will differ):

```
Updating Subscription Management repositories.
...
Installed:
  grafana-11.x.x ...
Complete!
```

Start and enable Grafana:

```bash
sudo systemctl start grafana-server
```

```bash
sudo systemctl enable grafana-server
```

Verify the service is running:

```bash
sudo systemctl status grafana-server
```

Expected output (yours will differ):

```
grafana-server.service - Grafana instance
     Loaded: loaded (/usr/lib/systemd/system/grafana-server.service; enabled; ...)
     Active: active (running) since Sun 2026-06-15 10:15:02 UTC; 5s ago
   Main PID: 12345 (grafana)
```

Look for `active (running)` in the output.

---

## Step 12: Access Grafana in Your Browser

Open a browser on your local machine and go to:

```
http://54.209.143.137:3000
```

You will see the Grafana login screen. Log in with:

- Username: `admin`
- Password: `admin`

Grafana will immediately prompt you to change the default password. Set a new password and save it somewhere secure.

---

## Step 13: Add Prometheus as a Data Source

Once logged in:

1. Click the hamburger menu (three horizontal lines) in the top-left corner
2. Click **Connections**
3. Click **Data sources**
4. Click **Add data source**
5. Click **Prometheus**
6. In the **Connection** section, set the URL to:
   ```
   http://localhost:9090
   ```
7. Leave all other settings at their defaults
8. Scroll to the bottom and click **Save & test**

Grafana will test the connection. You should see a green banner that says "Successfully queried the Prometheus API."

---

## Step 14: Create a Monitoring Dashboard

Now create a dashboard with four panels that cover the most important PostgreSQL and system metrics.

From the Grafana home screen:

1. Click the `+` icon in the left sidebar
2. Click **New dashboard**
3. Click **Add visualization**
4. Make sure **Prometheus** is selected as the data source

### Panel 1: PostgreSQL Active Connections

In the query box at the bottom, enter:

```
pg_stat_activity_count{datname="quantdb"}
```

This query returns the number of connections per state (active, idle, idle in transaction, etc.) for the quantdb database.

- Set the panel title to: `PostgreSQL - Active Connections (quantdb)`
- Set the visualization type to **Time series** (top right of the panel editor)
- Click **Apply**

### Panel 2: Replication Lag

Click **Add** then **Visualization** to add a second panel.

In the query box, enter:

```
pg_replication_lag
```

This metric is exposed by postgres_exporter on the primary and shows how many seconds behind the replica is.

- Set the panel title to: `PostgreSQL - Replication Lag (seconds)`
- Visualization type: **Stat** (shows a single large number - good for lag)
- Click **Apply**

### Panel 3: CPU Usage

Add a third panel.

In the query box, enter:

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

This calculates the percentage of CPU time that is NOT idle, which equals CPU usage. `rate()` computes the per-second rate over a 5-minute window. `avg by (instance)` averages across all CPU cores per server.

- Set the panel title to: `System - CPU Usage %`
- Visualization type: **Time series**
- Click **Apply**

### Panel 4: Available Disk Space

Add a fourth panel.

In the query box, enter:

```
node_filesystem_avail_bytes{mountpoint="/"}
```

This returns the available bytes on the root filesystem for each server.

- Set the panel title to: `System - Root Filesystem Available`
- Visualization type: **Time series**
- Click **Apply**

Save the dashboard:

1. Click the floppy disk icon (save) in the top-right corner
2. Name the dashboard: `Voleon PostgreSQL Overview`
3. Click **Save**

---

## Step 15: Verify All Prometheus Targets Are Up

Go back to the Prometheus UI at:

```
http://54.209.143.137:9090
```

Click **Status** in the top navigation bar, then click **Targets**.

You should see a table with all your targets listed. The **State** column should show `UP` for every target.

Expected targets:
- `172.31.19.86:9100` - node (pg-primary)
- `172.31.22.69:9100` - node (pg-replica)
- `172.31.21.45:9100` - node (pg-container)
- `172.31.26.19:9100` - node (pg-ops)
- `172.31.19.86:9187` - postgres (pg-primary)
- `172.31.22.69:9187` - postgres (pg-replica)

If any target shows `DOWN`, click the target link to see the error message. Common causes:
- The exporter is not running on that server (`sudo systemctl status node_exporter`)
- The security group does not allow traffic on that port from pg-ops
- The private IP in `prometheus.yml` has a typo

---

## Step 16: Run a Quick PromQL Query to Confirm Data

In the Prometheus UI, click **Graph** in the top navigation bar.

In the expression box, enter:

```
pg_stat_activity_count{datname="quantdb", state="active"}
```

Click **Execute**.

You should see a table of results, one row per PostgreSQL server that has postgres_exporter running. Click the **Graph** tab to see the metric charted over time.

Try one more query - replication lag:

```
pg_replication_lag
```

This should return a value close to 0 if your replica is healthy and caught up.

---

## Summary

You have:

- Installed `node_exporter` on all four servers (pg-primary, pg-replica, pg-container, pg-ops) and confirmed each exposes metrics on port 9100
- Installed `postgres_exporter` on pg-primary and pg-replica using the `quant_readonly` role for database access, exposing PostgreSQL metrics on port 9187
- Installed Prometheus 3.4.1 on pg-ops, configured scrape targets using private IPs, and fixed the SELinux context
- Installed Grafana on pg-ops and added Prometheus as a data source
- Built a four-panel dashboard covering PostgreSQL connections, replication lag, CPU usage, and disk availability
- Verified all Prometheus scrape targets are in `UP` state

Your full monitoring stack:

```
pg-ops (54.209.143.137)
  - Prometheus  :9090  (scrapes all targets every 15s)
  - Grafana     :3000  (reads from Prometheus, shows dashboards)
  - node_exporter :9100

pg-primary (3.90.199.62)
  - node_exporter    :9100
  - postgres_exporter :9187

pg-replica (3.91.32.84)
  - node_exporter    :9100
  - postgres_exporter :9187

pg-container (34.235.89.112)
  - node_exporter    :9100
```

Continue to BUILD-09 for the next section of the Voleon DBA practice lab.
