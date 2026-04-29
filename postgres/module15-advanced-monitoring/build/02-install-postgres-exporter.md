# Build Guide 02 - Install postgres_exporter

**Module:** 15 - Advanced Monitoring
**Node:** pg-primary
**Time:** ~25 minutes

---

## Overview

`postgres_exporter` is a small program that connects to PostgreSQL, runs a set of SQL queries against system views like `pg_stat_activity` and `pg_stat_bgwriter`, and exposes the results as Prometheus metrics on port 9187. Prometheus then scrapes those metrics on a schedule.

In this guide you will:
- Download postgres_exporter v0.15.0
- Create a dedicated OS user to run it
- Create a PostgreSQL monitoring role with read-only access
- Write a systemd service unit so it starts automatically
- Verify metrics are flowing on port 9187

---

## Step 1 - Log in to pg-primary

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

---

## Step 2 - Download postgres_exporter

The `-L` flag tells curl to follow redirects. GitHub releases use a redirect, so this flag is required. The `-o` flag sets the output filename.

```bash
curl -L -o /tmp/postgres_exporter.tar.gz \
  https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz
```

Expected output (yours will differ):

```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 9.2M  100 9.2M    0     0  5432k      0  0:00:01  0:00:01 --:--:--  5432k
```

---

## Step 3 - Extract the archive

```bash
tar -xzf /tmp/postgres_exporter.tar.gz -C /tmp/
```

The `-x` flag extracts, `-z` handles gzip compression, `-f` specifies the file, and `-C` sets the destination directory.

---

## Step 4 - Move the binary to /usr/local/bin

```bash
sudo mv /tmp/postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/local/bin/
```

---

## Step 5 - Set correct permissions on the binary

```bash
sudo chmod 755 /usr/local/bin/postgres_exporter
```

---

## Step 6 - Verify the binary works

```bash
/usr/local/bin/postgres_exporter --version
```

Expected output (yours will differ):

```
postgres_exporter version 0.15.0 (branch: HEAD, revision: abc1234)
  build user:       root@buildmachine
  build date:       20240301-12:00:00
  go version:       go1.21.0
  platform:         linux/amd64
```

---

## Step 7 - Create a dedicated OS user for postgres_exporter

Running services as a dedicated low-privilege user is a security best practice. The `--no-create-home` and `--shell /sbin/nologin` flags prevent this user from logging in interactively.

```bash
sudo useradd --system --no-create-home --shell /sbin/nologin postgres_exporter
```

---

## Step 8 - Switch to the postgres user to create the monitoring role

```bash
sudo -i -u postgres
```

---

## Step 9 - Connect to PostgreSQL

```bash
psql
```

---

## Step 10 - Create the monitoring role

This creates a PostgreSQL role named `postgres_exporter` that can log in. The `pg_monitor` role is a built-in PostgreSQL role that grants read access to all monitoring views including `pg_stat_activity`, `pg_stat_replication`, and `pg_stat_statements`.

```sql
CREATE ROLE postgres_exporter WITH LOGIN PASSWORD 'monitor_secret_2024';
GRANT pg_monitor TO postgres_exporter;
```

Expected output (yours will differ):

```
CREATE ROLE
GRANT ROLE
```

---

## Step 11 - Grant access to the pg_stat_statements view in stepup_store

The `pg_monitor` role grants access to system views, but `pg_stat_statements` lives in the user database. You need to grant access there explicitly.

```sql
\c stepup_store
GRANT SELECT ON pg_stat_statements TO postgres_exporter;
```

Expected output (yours will differ):

```
You are now connected to database "stepup_store" as user "postgres".
GRANT
```

---

## Step 12 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Step 13 - Create the environment file for postgres_exporter

The `DATA_SOURCE_NAME` environment variable tells postgres_exporter how to connect to PostgreSQL. The format is a standard PostgreSQL connection URI. Store this in a file so the systemd service can read it without exposing credentials in the service unit itself.

```bash
sudo mkdir -p /etc/postgres_exporter
```

```bash
sudo vi /etc/postgres_exporter/postgres_exporter.env
```

Add this content to the file:

```
DATA_SOURCE_NAME=postgresql://postgres_exporter:monitor_secret_2024@localhost:5432/postgres?sslmode=disable
```

Save and close the file (`:wq` in vi).

---

## Step 14 - Set secure permissions on the environment file

Only root and the postgres_exporter user should be able to read this file because it contains the database password.

```bash
sudo chown root:postgres_exporter /etc/postgres_exporter/postgres_exporter.env
sudo chmod 640 /etc/postgres_exporter/postgres_exporter.env
```

---

## Step 15 - Create the systemd service unit

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

Add this content:

```ini
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql-16.service
Wants=postgresql-16.service

[Service]
Type=simple
User=postgres_exporter
Group=postgres_exporter
EnvironmentFile=/etc/postgres_exporter/postgres_exporter.env
ExecStart=/usr/local/bin/postgres_exporter \
  --web.listen-address=:9187 \
  --web.telemetry-path=/metrics \
  --collector.stat_statements \
  --collector.postmaster
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**What the flags mean:**
- `--web.listen-address=:9187` - listen on port 9187 on all interfaces
- `--web.telemetry-path=/metrics` - expose metrics at the /metrics HTTP path
- `--collector.stat_statements` - collect query statistics from pg_stat_statements
- `--collector.postmaster` - collect postmaster start time metrics

Save and close the file.

---

## Step 16 - Reload systemd so it sees the new service

```bash
sudo systemctl daemon-reload
```

---

## Step 17 - Enable the service to start on boot

```bash
sudo systemctl enable postgres_exporter
```

Expected output (yours will differ):

```
Created symlink /etc/systemd/system/multi-user.target.wants/postgres_exporter.service -> /etc/systemd/system/postgres_exporter.service.
```

---

## Step 18 - Start postgres_exporter

```bash
sudo systemctl start postgres_exporter
```

---

## Step 19 - Check the service status

```bash
sudo systemctl status postgres_exporter
```

Expected output (yours will differ):

```
● postgres_exporter.service - Prometheus PostgreSQL Exporter
     Loaded: loaded (/etc/systemd/system/postgres_exporter.service; enabled; preset: disabled)
     Active: active (running) since Tue 2024-03-01 14:23:11 UTC; 3s ago
   Main PID: 12345 (postgres_export)
      Tasks: 6 (limit: 4915)
     Memory: 14.2M
        CPU: 0.052s
     CGroup: /system.slice/postgres_exporter.service
             └─12345 /usr/local/bin/postgres_exporter ...
```

The status must show `active (running)`. If it shows `failed`, check the logs in the next step.

---

## Step 20 - Check logs if the service failed

```bash
sudo journalctl -u postgres_exporter -n 50 --no-pager
```

The `-u` flag filters by unit name, `-n 50` shows the last 50 lines, and `--no-pager` prints directly to the terminal.

---

## Step 21 - Test the metrics endpoint

```bash
curl -s http://localhost:9187/metrics | head -30
```

Expected output (yours will differ):

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 4.21e-05
go_gc_duration_seconds{quantile="0.25"} 5.12e-05
# HELP pg_stat_activity_count Number of connections in each state
# TYPE pg_stat_activity_count gauge
pg_stat_activity_count{datname="postgres",state="active"} 1
pg_stat_activity_count{datname="postgres",state="idle"} 3
...
```

---

## Step 22 - Verify PostgreSQL-specific metrics are present

```bash
curl -s http://localhost:9187/metrics | grep pg_stat_bgwriter
```

Expected output (yours will differ):

```
# HELP pg_stat_bgwriter_buffers_alloc Number of buffers allocated
# TYPE pg_stat_bgwriter_buffers_alloc counter
pg_stat_bgwriter_buffers_alloc 12483
# HELP pg_stat_bgwriter_buffers_backend Number of buffers written directly by a backend
...
```

If you see `pg_stat_bgwriter` metrics, postgres_exporter is successfully collecting data from PostgreSQL.

---

## Step 23 - Check that port 9187 is listening

```bash
ss -tlnp | grep 9187
```

Expected output (yours will differ):

```
LISTEN 0      128          0.0.0.0:9187      0.0.0.0:*    users:(("postgres_export",pid=12345,fd=3))
```

---

## Summary

You have:
- Downloaded and installed postgres_exporter v0.15.0
- Created a dedicated OS user `postgres_exporter`
- Created a PostgreSQL monitoring role with `pg_monitor` access
- Configured a systemd service with the database connection string
- Verified metrics are available at `http://localhost:9187/metrics`

In the next guide you will install Prometheus to scrape and store these metrics over time.
